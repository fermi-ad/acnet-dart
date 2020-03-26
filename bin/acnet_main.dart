import '../lib/acnet.dart';
import '../lib/level2.dart';

void main() async {
  final c = Connection();
  try {
    final h = await c.handle;
    final ln = await c.getLocalNode();

    print("Handle '$h' on local node '$ln'");

    {
      final tn = await c.getNodeAddress("CLX73");
      final nm = await c.getNodeName(tn);

      print("CLX73: tn = $tn, nm = $nm");
    }

    final answering = await c.ping(node: ln);

    if (answering) {
      final v = await c.getVersions(node: ln);

      print("${v[0]}, ${v[1]}, ${v[2]}");

      final id = await c.getTaskId(task: h, node: ln);
      final name = await c.getTaskName(taskId: id, node: ln);
      final ip = await c.getTaskIp(taskId: id, node: ln);

      print("Look-up ACNET: id = $id, name = $name, ip = $ip");

      final Map<int, TaskInfo> tasks = await c.getTaskInfo(node: ln);

      for (var k in tasks.keys)
        print(tasks[k].toString());
    } else
      print("$ln did not answer.");
  }
  catch (e) {
    print("Caught exception: $e");
  }
}
