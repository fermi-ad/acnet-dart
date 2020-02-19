import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'rad50.dart';
import 'status.dart';

enum State { Disconnected, Connected }

class _Context {
  int _handle;
  WebSocket _socket;

  _Context(this._handle, this._socket);
}

class Connection {
  Future<_Context> _ctxt;
  List<Completer<List<int>>> _requests = [];
  State _currentState = State.Disconnected;
  StreamSubscription<dynamic> _sub; // ignore: cancel_subscriptions
  Completer<State> _stateEvent = Completer();

  // 'nack_disconnect' is a packet that is returned when we lose connection
  // with ACNET. It has one layout, so we can define it once and use it
  // everywhere it can be returned.

  static const List<int> _NACK_DISCONNECT = [0, 0, 0xde, 1];

  /// Allows an application to query the current state of the ACNET connection.
  /// This state is volatile in that, right after reading the state is
  /// "Connected", the ACNET connection could end.
  State get state => this._currentState;

  /// Returns a Future<State> so applications can block and be notified when
  /// the state of the connection has changed.
  Future<State> get nextState => this._stateEvent.future;

  /// Returns the ACNET handle associated with the connection.
  Future<String> get handle async {
    final ctxt = await this._ctxt;

    return toString(ctxt._handle);
  }

  // Posts a new connection state event. We save the completer to a local
  // temporary so that the completer in the object will always have an
  // unresolved Future. This way, if a task immediate awaits on `nextState`,
  // they'll block.

  void _postNewState(State s) {
    final tmp = this._stateEvent;

    this._stateEvent = Completer();
    tmp.complete(s);
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
                      .then((ByteData ack) {
                        final h = ack.getUint32(5);

                        // Before updating the context, we notify listeners of
                        // our state events that we just connected.

                        this._postNewState(State.Connected);
                        return _Context(h, s);
                      });
                }));

    this._requests = [];
    this._postNewState(State.Disconnected);
  }

  Connection() {
    this._reset(Duration());
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
    var pkt = event as List<int>;

    // Packets must be at least 2 bytes, so we can see whether it's network
    // data or an ACK packet.

    if (pkt.length >= 2 && pkt[0] == 0) {
      if (pkt[1] == 2) {
        this._requests.first.complete(pkt);
        this._requests.removeAt(0);
      } else
        print("TODO: handle messages from network.");
    } else
      print("received bad packet: $pkt");
  }

  // Perform a transaction with acnetd. This requires a command packet
  // be sent over the WebSocket, which then returns a reply packet.

  Future<ByteData> _xact(WebSocket s, List<int> pkt) {
    Completer<List<int>> c = Completer();

    s.add(pkt);
    this._requests.add(c);
    return c.future.then((List<int> ack) {
      // XXX: I wish there was a way to avoid this copy.
      final pkt = Uint8List.fromList(ack);

      return ByteData.view(pkt.buffer, 2);
    });
  }

  /// Helper method to convert an ACNET node name into an address.
  Future<int> getNodeAddress(String name) async {
    final _Context ctxt = await this._ctxt;
    final pkt = Uint8List(16);

    {
      final bd = ByteData.view(pkt.buffer);

      bd.setUint32(0, 0x0001000b);
      bd.setUint32(4, ctxt._handle);
      bd.setUint32(12, toRad50(name));
    }

    final ack = await this._xact(ctxt._socket, pkt);

    if (ack.lengthInBytes >= 4) {
      final status = Status.fromRaw(ack.getInt16(2));

      if (ack.getUint16(0) == 4 && status.isGood) {
        if (ack.lengthInBytes >= 6)
          return ack.getUint16(4);
        else
          throw ACNET_BUG;
      } else
        throw status;
    } else
      throw ACNET_BUG;
  }

  /// Helper method to convert an ACNET trunk/node into a name.
  Future<String> getNodeName(int addr) async {
    final _Context ctxt = await this._ctxt;
    final pkt = Uint8List(14);

    {
      final bd = ByteData.view(pkt.buffer);

      bd.setUint32(0, 0x0001000c);
      bd.setUint32(4, ctxt._handle);
      bd.setUint16(12, addr);
    }

    final ack = await this._xact(ctxt._socket, pkt);

    if (ack.lengthInBytes >= 4) {
      final status = Status.fromRaw(ack.getInt16(2));

      if (ack.getUint16(0) == 5 && status.isGood) {
        if (ack.lengthInBytes >= 8)
          return toString(ack.getUint32(4));
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

    if (ack.lengthInBytes >= 4) {
      final status = Status.fromRaw(ack.getInt16(2));

      if (ack.getUint16(0) == 4 && status.isGood) {
        if (ack.lengthInBytes >= 6)
          return await this.getNodeName(ack.getUint16(4));
        else
          throw ACNET_BUG;
      } else
        throw status;
    } else
      throw ACNET_BUG;
  }
}
