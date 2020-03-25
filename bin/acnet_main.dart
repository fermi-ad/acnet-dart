import '../lib/acnet.dart';
import '../lib/level2.dart';

void main() async {
  final c = Connection();
  try {
    final h = await c.handle;
    final ln = await c.getLocalNode();

    print("Handle '$h' on local node '$ln'");

    final tn = await c.getNodeAddress("CLX73");
    final nm = await c.getNodeName(tn);

    print("CLX73: tn = $tn, nm = $nm");

    final node = "CLX39";
    final answering = await c.ping(node: node);

    if (answering) {
      final v = await c.getVersions(node: node);

      print("${v[0]}, ${v[1]}, ${v[2]}");
    } else
      print("$node did not answer.");

    final Map<int, TaskInfo> tasks = await c.getTasks(node: node);

    for (var k in tasks.keys)
      print(tasks[k].toString());
  }
  catch (e) {
    print("Caught exception: $e");
  }
}
