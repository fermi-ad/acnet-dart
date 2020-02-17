import 'dart:async';
import 'dart:io';
import 'rad50.dart';

class Connection {
  Future<WebSocket> socket;
  List<Completer<List<int>>> requests = [];
  StreamSubscription<dynamic> sub; // ignore: cancel_subscriptions
  Future<String> handle;

  // 'nack_disconnect' is a packet that is returned when we lose connection
  // with ACNET. It has one layout, so we can define it once and use it
  // everywhere it can be returned.

  static const List<int> NACK_DISCONNECT = [0, 0, 0xde, 1];

  void _reset() {
    final Uri wsUrl =
      Uri(scheme: "wss", host: "www-bd.fnal.gov", port:443,
          path:"acnet-ws-test");

    Completer<String> cHandle = Completer();

    this.handle = cHandle.future;

    // Free up resources to a subscription that may still exist.

    this.sub?.cancel();
    this.sub = null;

    this.socket =
        WebSocket.connect(wsUrl.toString(), protocols: ['acnet-client']).then((s) {
      const reqConPkt = [0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

      this.sub =
          s.listen(this.onData, onError: this.onError, onDone: this.onDone);
      return this._xact(s, reqConPkt).then((ack) {
        final h = (ack[7] << 24) + (ack[8] << 16) + (ack[9] << 8) + ack[10];

        cHandle.complete(toString(h));
        return s;
      });
    });

    this.requests = [];
  }

  Connection() {
    this._reset();
  }

  void onDone() {
    // Hold onto the list of pending transactions and clear the "public"
    // list. As we send errors to clients, we don't want them adding new
    // entries to the list.

    var tmp = this.requests;

    this._reset();
    tmp.forEach((e) => e.complete(NACK_DISCONNECT));
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
        requests.first.complete(pkt);
        requests.removeAt(0);
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
    this.requests.add(c);
    return c.future;
  }
}
