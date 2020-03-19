import 'dart:typed_data';
import 'src/rad50.dart';
import 'src/status.dart';
import 'src/connection.dart';

enum TaskType { Client, Server }

class TaskInfo {
  final int taskId;
  final TaskType type;
  final String handle;
  final int pid;

  const TaskInfo(this.taskId, this.type, this.handle, this.pid);

  @override
  String toString() {
    return "task info: { id: ${this.taskId}, "
        "type: ${this.type == TaskType.Client ? "client" : "service"}, "
        "handle: ${this.handle}, pid: ${this.pid} }";
  }
}

extension LevelII on Connection {
  /// Pings the specified ACNET node.

  Future<bool> ping({String node}) async {
    final result = await this.rpc(
        task: "ACNET@" + node,
        data: Uint8List.fromList(const [0, 0]),
        timeout: 100);

    return result.status.isGood && result.message.length == 2;
  }

  /// Queries the version of the specified ACNET node. The return value is a
  /// list of 3 strings.

  Future<List<String>> version({String node}) async {
    final result = await this.rpc(
        task: "ACNET@" + node,
        data: Uint8List.fromList(const [3, 0]),
        timeout: 100);

    if (result.status.isGood) {
      final v = Uint8List.fromList(result.message);
      final bd = ByteData.view(v.buffer);

      return [
        bd.getUint16(0, Endian.little),
        bd.getUint16(2, Endian.little),
        bd.getUint16(4, Endian.little)
      ].map((v) => "${v ~/ 256}.${v % 256}").toList();
    } else
      throw result.status;
  }

  Future<List<TaskInfo>> getTasks({String node}) async {
    final result = await this.rpc(
        task: "ACNET@" + node,
        data: Uint8List.fromList(const [4, 3]),
        timeout: 500);

    if (result.status.isGood) {
      final v = Uint8List.fromList(result.message);
      final bd = ByteData.view(v.buffer);
      final total = bd.getUint16(0, Endian.little);
      var l = <TaskInfo>[];

      if (bd.buffer.lengthInBytes >= 2 + total * 11) {
        print(
            "pkt size: ${bd.buffer.lengthInBytes} bytes, total tasks: $total");

        for (var ii = 0; ii < total; ++ii) {
          final offset = 2 + ii * 11;

          l.add(TaskInfo(
              bd.getUint16(offset, Endian.little),
              (bd.getUint8(offset + 2) & 1) != 0
                  ? TaskType.Server
                  : TaskType.Client,
              toString(bd.getUint32(offset + 3, Endian.little)),
              bd.getUint32(offset + 7, Endian.little)));
        }
        return l;
      } else
        throw ACNET_TRUNC_REPLY;
    } else
      throw result.status;
  }
}
