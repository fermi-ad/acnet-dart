import 'dart:typed_data';

import '../lib/acnet.dart';

final Uint8List pingReq = Uint8List.fromList([0, 0]);

void main() async {
  final c = Connection();
  final h = await c.handle;
  final ln = await c.getLocalNode();

  print("Handle '$h' on local node '$ln'");

  final tn = await c.getNodeAddress("CLX73");
  final nm = await c.getNodeName(tn);

  print("CLX73: tn = $tn, nm = $nm");

  final rpy = await c.rpc(task: "ACNET@CLX39", message: pingReq);

  print("reply: Reply(sender: ${await c.getNodeName(rpy.sender)}, "
        "status: ${rpy.status}, "
        "data: ${rpy.message})");
}
