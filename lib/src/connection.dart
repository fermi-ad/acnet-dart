import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'rad50.dart';
import 'status.dart';

/// The possible states of an ACNET connection. These are retrieved using
/// the `Connection.state` and `Connection.stateStream` properties.
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

/// A structure that holds reply information from ACNET. The [sender] field
/// holds the trunk/node address from where the reply was sent. The [status]
/// field holds an ACNET status value associated with the reply. The [message]
/// field holds the actual reply data. In low-level communications (i.e. when
/// a library hasn't been written for the service) the type of [message] will
/// simply be `List<int>`.
class Reply<T> {
  final int sender;
  final Status status;
  final T message;

  const Reply(this.sender, this.status, this.message);

  String toString() => "Reply(${this.sender}, ${this.status}, ${this.message})";

  /// Maps the reply to hold a different type by calling a mapping function.
  /// With the proper mapping functions, this method can be used to serialize
  /// data types to and from List<int> (used by the low-level ACNET methods.)
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

  // 'NACK_DISCONNECT' is a packet that is returned when we lose connection
  // with ACNET. It has one layout, so we can define it once and use it
  // everywhere it can be returned.

  static final Uint8List _NACK_DISCONNECT = Uint8List.fromList([0, 0, 0xde, 1]);

  /// Allows an application to query the current state of the ACNET connection.
  /// This state is volatile in that, right after reading the state, the
  /// connection could change to a new state. To properly track state changes,
  /// you should use the [stateStream] property.
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
    final Uri wsUrl = Uri(
        scheme: "wss",
        host: "www-bd.fnal.gov",
        port: 443,
        path: "acnet-ws-test");

    // Free up resources to a subscription that may still exist.

    this._sub?.cancel();
    this._sub = null;

    // Prepare a new context. `Future.delayed` returns a Future that resolves
    // after a timeout. When constructing a new Connection, the timeout is 0
    // seconds. When trying to reconnect, the timeout is typically set to 5
    // seconds.

    this._ctxt = Future.delayed(d, () async {
      while (true) {
        try {
          final ws = await WebSocket.connect(wsUrl.toString(),
              protocols: ['acnet-client'],
              compression: CompressionOptions(enabled: false));

          // Subscribe to events of the WebSocket.

          _sub = ws.listen(this._onData,
              onError: this._onError, onDone: this._onDone);

          const reqConPkt = const [
            0,
            1,
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
          ];

          // Send the CONNECT command to ACNET. The `_xact` method
          // returns a Future with the ACK status from ACNET.

          final List<int> ack = await _xact(ws, reqConPkt);
          final bd = ByteData.view((ack as Uint8List).buffer, 4);
          final h = bd.getUint32(5);

          // Before updating the context, we notify listeners of
          // our state events that we just connected.

          _postNewState(AcnetState.Connected);
          return _Context(h, ws);
        } catch (error) {
          // Some sort of error occurred. Notify subscribers we are in a
          // disconnected state.

          _postNewState(AcnetState.Disconnected);
          await Future.delayed(Duration(seconds: 5));
        }
      }
    });

    this._requests = [];
    this._postNewState(AcnetState.Disconnected);
  }

  /// Creates a new connection to ACNET. This only allows a client to connect
  /// anonymously (so `acnetd` will provide the handle name.)
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

          if (bd.getUint16(0, Endian.little) == 4) this._rpyMap.remove(reqId);
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

  /// Converts an ACNET node name into an address by querying the node table
  /// of the local `acnetd` instance.
  Future<int> getNodeAddress(String name) async {
    if (name == "LOCAL") return 0;

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

  /// Converts an ACNET trunk/node into a name by querying the node table of
  /// the local `acnetd` instance.
  Future<String> getNodeName(int addr) async {
    if (addr == 0) return "LOCAL";

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

  /// Get the local node name. ACNET clients don't necessarily know the ACNET
  /// node on which they're running. If a client needed this information, this
  /// method asks `acnetd` for the node. This method can be useful on a system
  /// that provides several ACNET node (i.e. "virtual nodes"). This method
  /// would which node, of a set of virtual nodes, the client is using.
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

    if (part.length != 2) throw ACNET_INVARG;

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

  /// Sends an ACNET request to a remote task which will only receive one
  /// reply. [task] is the address of the remote task. It takes the form
  /// "TASK@NODE". [data] is a binary packet of data to send. [timeout]
  /// indicates, in milliseconds, how long we should wait for a reply before
  /// an ACNET_UTIME error status is returned.
  ///
  /// The [timeout] parameter should always be preferred rather than pairing
  /// the returned Future with a timeout Future. This is because ACNET requests
  /// always have a timeout associated with them and it complicates the code
  /// as to whether an ACNET timeout occurred or whether a local timeout
  /// expired and the Futures were canceled. Letting ACNET do the timeout
  /// allows resources to be properly cleaned up.
  Future<Reply<List<int>>> requestReply(
      {String task, List<int> data, int timeout = 1000}) async {
    try {
      final p = await _parseAddress(task);
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
            throw ACNET_BUG;
        } else
          throw status;
      } else
        throw ACNET_BUG;
    } catch (status) {
      print("exception: $status");
      return Reply(0, status, Uint8List(0));
    }
  }
}
