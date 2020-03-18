import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'rad50.dart';
import 'status.dart';

/// The possible states of the ACNET connection. These are retrieved using
/// the `Connection.state` and `Connection.nextState` properties.
enum AcnetState { Disconnected, Connected }

class _Context {
  int _handle;
  WebSocket _socket;

  _Context(this._handle, this._socket);
}

class _Pair<T1, T2> {
  final T1 item1;
  final T2 item2;

  const _Pair(this.item1, this.item2);
}

/// Replies from ACNET take the following format. In low-level communications
/// (i.e. when a library hasn't been written for the service) the type of the
/// message will simply be `List<int>`.
class Reply<T> {
  final int sender;
  final Status status;
  final T message;

  const Reply(this.sender, this.status, this.message);

  String toString() => "Reply(${this.sender}, ${this.status}, ${this.message})";

  Reply<R> map<R>(R f(T)) => Reply(this.sender, this.status, f(this.message));
}

typedef ReplyHandler(Reply<List<int>> reply);

/// Manages an ACNET connection. If the connection to the control system
/// breaks, attempts will be made to reconnect. While the connection is
/// broken, tasks trying to send requests will block.
class Connection {
  Future<_Context> _ctxt;
  List<Completer<List<int>>> _requests = [];
  AcnetState _currentState = AcnetState.Connected;
  StreamController<AcnetState> _stateStream = StreamController.broadcast();
  StreamSubscription<dynamic> _sub; // ignore: cancel_subscriptions
  Map<int, ReplyHandler> _rpyMap = {};

  // 'nack_disconnect' is a packet that is returned when we lose connection
  // with ACNET. It has one layout, so we can define it once and use it
  // everywhere it can be returned.

  static final Uint8List _NACK_DISCONNECT =
    Uint8List.fromList([0, 0, 0xde, 1]);

  /// Allows an application to query the current state of the ACNET connection.
  /// This state is volatile in that, right after reading the state is
  /// "Connected", the ACNET connection could end.
  AcnetState get state => this._currentState;

  /// Returns a Stream<State> so applications can subscribe and be notified when
  /// the state of the connection has changed.
  Stream<AcnetState> get stateStream => this._stateStream.stream;

  /// Returns the ACNET handle associated with the connection.
  Future<String> get handle async {
    final ctxt = await this._ctxt;

    return toString(ctxt._handle);
  }

  // Posts a new connection state event. We save the completer to a local
  // temporary so that the completer in the object will always have an
  // unresolved Future. This way, if a task immediate awaits on `nextState`,
  // they'll block.

  void _postNewState(AcnetState s) {
    _currentState = s;
    this._stateStream.add(s);
  }

  void _reset(Duration d) {
    final Uri wsUrl =
      Uri(scheme: "wss", host: "www-bd.fnal.gov", port:443,
          path:"acnet-ws-test");

    // Free up resources to a subscription that may still exist.

    this._sub?.cancel();
    this._sub = null;

    // Prepare a new context. `Future.delayed` returns a Future that resolves
    // after a timeout. When constructing, the timeout is 0 seconds. Future
    // restarts (when trying to reconnect) we wait 5 seconds.

    this._ctxt =
        Future.delayed(d, () =>

            // `WebSocket.connect` returns a Future that returns a WebSocket.
            // We don't want anyone to use the WebSocket until we register a
            // handle with ACNET, so we add a `then` chain to do further
            // processing.

            WebSocket.connect(wsUrl.toString(), protocols: ['acnet-client'])
                .then((s) {

                  // 's' is the Websocket. We create a subscriber to it so
                  // we'll get notified with its events.

                  this._sub = s.listen(this._onData, onError: this._onError,
                                       onDone: this._onDone);

                  const reqConPkt = [0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0];

                  // Send the CONNECT command to ACNET. The `_xact` method
                  // returns a Future with the ACK status from ACNET. We
                  // feed this result into a `then` which builds the _Context
                  // that resolves the outermost Future.

                  return this._xact(s, reqConPkt)
                      .then((List<int> ack) {
                        final bd = ByteData.view((ack as Uint8List).buffer, 4);
                        final h = bd.getUint32(5);

                        // Before updating the context, we notify listeners of
                        // our state events that we just connected.

                        this._postNewState(AcnetState.Connected);
                        return _Context(h, s);
                      });
                }));

    this._requests = [];
    this._postNewState(AcnetState.Disconnected);
  }

  Connection() {
    this._reset(Duration(seconds: 0));
  }

  void _onDone() {

    // Hold onto the list of pending transactions and clear the "public"
    // list. As we send errors to clients, we don't want them adding new
    // entries to the list.

    var tmp = this._requests;

    this._reset(Duration(seconds: 5));
    tmp.forEach((e) => e.complete(_NACK_DISCONNECT));
  }

  void _onError(error) {
    this._onDone();
  }

  void _onData(dynamic event) {
    final pkt = event as List<int>;

    // Packets must be at least 2 bytes, so we can see whether it's network
    // data or an ACK packet.

    if (pkt.length >= 2 && pkt[0] == 0) {

      // If the first "header" is 2, we have a reply to an acnetd client
      // command.

      if (pkt[1] == 2) {

        // Use the packet to resolve the first Future in the request list
        // and then remove it.

        this._requests.first.complete(pkt);
        this._requests.removeAt(0);
      }

      // We assume the packet contains data from an ACNET network frame.
      // The length needs to be long enough to hold an ACNET header.

      else if (pkt.length >= 20) {

        // Grab the status, trunk/node address of the sender, and the
        // request ID. Use the request ID to look-up the callback associated
        // with it.

        final bd = ByteData.view(Uint8List.fromList(pkt).buffer, 2);
        final status = Status.fromRaw(bd.getInt16(2, Endian.little));
        final tn = bd.getUint16(4);
        final reqId = bd.getUint16(14, Endian.little);
        final entry = this._rpyMap[reqId];

        // If the was an entry for the request, handle it.

        if (entry != null) {

          // If the "MULT" bit is clear, then this is the last reply for the
          // request. Remove it from the map. (If the 'flags' field is 5, it's
          // a reply with more to follow, a 4 means it's the last reply.)

          if (bd.getUint16(0, Endian.little) == 4)
            this._rpyMap.remove(reqId);
          entry(Reply(tn, status, Uint8List.view(bd.buffer, 20)));
        } else
          print("bad request ID: $reqId");
      } else
        print("received bad packet (shorter than ACNET header): $pkt");
    } else
      print("received bad packet: $pkt");
  }

  // Perform a transaction with acnetd. This requires a command packet
  // be sent over the WebSocket, which then returns a reply packet.

  Future<List<int>> _xact(WebSocket s, List<int> pkt) {
    Completer<Uint8List> c = Completer();

    s.add(pkt);
    this._requests.add(c);
    return c.future;
  }

  /// Helper method to convert an ACNET node name into an address.
  Future<int> getNodeAddress(String name) async {
    if (name == "LOCAL")
      return 0;

    final _Context ctxt = await this._ctxt;
    final pkt = Uint8List(16);

    {
      final bd = ByteData.view(pkt.buffer);

      bd.setUint32(0, 0x0001000b);
      bd.setUint32(4, ctxt._handle);
      bd.setUint32(12, toRad50(name));
    }

    final ack = await this._xact(ctxt._socket, pkt);

    if (ack.length >= 6) {
      final bd = ByteData.view((ack as Uint8List).buffer, 4);
      final status = Status.fromRaw(bd.getInt16(2));

      if (bd.getUint16(0) == 4 && status.isGood) {
        if (ack.length >= 8)
          return bd.getUint16(4);
        else
          throw ACNET_BUG;
      } else
        throw status;
    } else
      throw ACNET_BUG;
  }

  /// Helper method to convert an ACNET trunk/node into a name.
  Future<String> getNodeName(int addr) async {
    if (addr == 0)
      return "LOCAL";

    final _Context ctxt = await this._ctxt;
    final pkt = Uint8List(14);

    {
      final bd = ByteData.view(pkt.buffer);

      bd.setUint32(0, 0x0001000c);
      bd.setUint32(4, ctxt._handle);
      bd.setUint16(12, addr);
    }

    final ack = await this._xact(ctxt._socket, pkt);

    if (ack.length >= 6) {
      final bd = ByteData.view((ack as Uint8List).buffer, 4);
      final status = Status.fromRaw(bd.getInt16(2));

      if (bd.getUint16(0) == 5 && status.isGood) {
        if (ack.length >= 10)
          return toString(bd.getUint32(4));
        else
          throw ACNET_BUG;
      } else
        throw status;
    } else
      throw ACNET_BUG;
  }

  /// Helper method to get the local node name.
  Future<String> getLocalNode() async {
    final _Context ctxt = await this._ctxt;
    final pkt = Uint8List(12);

    {
      final bd = ByteData.view(pkt.buffer);

      bd.setUint32(0, 0x0001000d);
      bd.setUint32(4, ctxt._handle);
    }

    final ack = await this._xact(ctxt._socket, pkt);

    if (ack.length >= 6) {
      final bd = ByteData.view((ack as Uint8List).buffer, 4);
      final status = Status.fromRaw(bd.getInt16(2));

      if (bd.getUint16(0) == 4 && status.isGood) {
        if (ack.length >= 8)
          return await this.getNodeName(bd.getUint16(4));
        else
          throw ACNET_BUG;
      } else
        throw status;
    } else
      throw ACNET_BUG;
  }

  Future<_Pair<int, int>> _parseAddress(String addr) async {
    final part = addr.split("@");

    if (part.length != 2)
      throw ACNET_INVARG;

    if (part[1][0] == "#") {
      final node = int.tryParse(part[1].substring(1));

      if (node != null) {
        return _Pair(toRad50(part[0]), node);
      } else {
        throw ACNET_INVARG;
      }
    } else {
      final node = await this.getNodeAddress(part[1]);

      return _Pair(toRad50(part[0]), node);
    }
  }

  Future<Reply<List<int>>> rpc({ String task, List<int> data, int timeout = 1000 }) {
    return this._parseAddress(task)
        .then((p) async {
          final buf = Uint8List(24 + data.length);
          final ctxt = await this._ctxt;

          {
            final bd = ByteData.view(buf.buffer);

            bd.setUint32(0, 0x00010012);
            bd.setUint32(4, ctxt._handle);
            bd.setUint32(12, p.item1);
            bd.setUint16(16, p.item2);
            bd.setUint16(18, 0);
            bd.setUint32(20, timeout);
          }
          buf.setAll(24, data);

          final ack = await this._xact(ctxt._socket, buf);

          if (ack.length >= 6) {
            final bd = ByteData.view((ack as Uint8List).buffer, 2);
            final status = Status.fromRaw(bd.getInt16(4));

            if (bd.getUint16(2) == 2 && status.isGood) {
              if (ack.length >= 8) {
                final reqId = bd.getUint16(6);
                final c = Completer<Reply<List<int>>>();

                this._rpyMap[reqId] = c.complete;
                return c.future;
              } else
                return Reply(0, ACNET_BUG, Uint8List(0));
            } else
              return Reply(0, status, Uint8List(0));
          } else
            return Reply(0, ACNET_BUG, Uint8List(0));
      }).catchError((status) {
        print("exception: $status");
        return Reply(0, status, Uint8List(0));
      });
  }
}
