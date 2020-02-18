import '../lib/acnet.dart';

void main() async {
  var c = Connection();
  final h = await c.handle;
  final ln = await c.getLocalNode();

  print("Handle '$h' on local node '$ln'\n");

  final tn = await c.getNodeAddress("CLX73");
  final nm = await c.getNodeName(tn);

  print("CLX73: tn = $tn, nm = $nm\n");
}
