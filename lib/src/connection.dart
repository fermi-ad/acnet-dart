import 'dart:async';
import 'dart:io';
import 'rad50.dart';

enum State { Disconnected, Connected }

class Connection {
  Future<WebSocket> _socket;
  List<Completer<List<int>>> _requests = [];
  StreamSubscription<dynamic> _sub; // ignore: cancel_subscriptions
  Future<String> handle;
  State _currentState = State.Disconnected;
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

    Completer<String> cHandle = Completer();

    this.handle = cHandle.future;

    // Free up resources to a subscription that may still exist.

    this._sub?.cancel();
    this._sub = null;

    this._socket =
        Future.delayed(d, () =>
            WebSocket.connect(wsUrl.toString(), protocols: ['acnet-client'])
                .then((s) {
                  const reqConPkt = [0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                     0, 0, 0, 0];

                  this._sub = s.listen(this.onData, onError: this.onError,
                                       onDone: this.onDone);
                  return this._xact(s, reqConPkt)
                      .then((ack) {
                        final h = (ack[7] << 24) + (ack[8] << 16) +
                            (ack[9] << 8) + ack[10];

                        this._postNewState(State.Connected);
                        cHandle.complete(toString(h));
                        return s;
                      });
                }));

    this._requests = [];
    this._postNewState(State.Disconnected);
  }

  Connection() {
    this._reset(Duration());
  }

  void onDone() {
    // Hold onto the list of pending transactions and clear the "public"
    // list. As we send errors to clients, we don't want them adding new
    // entries to the list.

    var tmp = this._requests;

    this._reset(Duration(seconds: 5));
    tmp.forEach((e) => e.complete(_NACK_DISCONNECT));
  }

  void onError(error) {
    this.onDone();
  }

  void onData(dynamic event) {
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

  Future<List<int>> _xact(WebSocket s, List<int> pkt) {
    Completer<List<int>> c = Completer();

    s.add(pkt);
    this._requests.add(c);
    return c.future;
  }
}
