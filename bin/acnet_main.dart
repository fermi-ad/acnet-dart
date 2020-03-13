import '../lib/acnet.dart';
import '../lib/level2.dart';

void main() async {
  final c = Connection();
  final h = await c.handle;
  final ln = await c.getLocalNode();

  print("Handle '$h' on local node '$ln'");

  final tn = await c.getNodeAddress("CLX73");
  final nm = await c.getNodeName(tn);

  print("CLX73: tn = $tn, nm = $nm");

  final node = "CLX39";
  final answering = await c.ping(node: node);

  if (answering) {
    final v = await c.version(node: node);

    print("${v[0]}, ${v[1]}, ${v[2]}");
  } else
    print("$node did not answer.");

  final tasks = await c.getTasks(node: node);

  for (var ii in tasks)
    print(ii.toString());
}
