/// Extension module for the [Connection] class to provide Level-II diagnostics.

import 'dart:collection';
import 'dart:typed_data';
import 'src/rad50.dart';
import 'src/status.dart';
import 'src/connection.dart';

enum TaskType { Client, Server }

class TaskInfo {
  TaskType type;
  String handle;
  int pid;

  TaskInfo(this.type, this.handle, this.pid);

  @override
  String toString() {
    return "task info: { "
        "type: ${this.type == TaskType.Client ? "client" : "service"}, "
        "handle: ${this.handle}, pid: ${this.pid} }";
  }
}

/// Adds methods to the [Connection] class to provide "Level-II" diagnostics.
/// These are methods that retrieve internal information from an ACNET node
/// or perform diagnostic functions (like "ping"ing an ACNET node.) Normal
///
/// If your application needs these methods, you don't have to import both the
/// ACNET and Level-2 modules. The Level-2 extension will pull in the ACNET
/// module for you:
///
/// ```
/// import 'package:acnet/level2.dart';
/// ```

extension Level2 on Connection {

  /// Returns the task ID of a remote task.
  Future<int> getTaskId({String task, String node}) async {

    // Request format for task ID info:
    //
    // +----+----+
    // | 01 | 00 |
    // +----+----+----+----+
    // | 32-bit RAD50 name |
    // +----+----+----+----+

    final pkt = Uint8List.fromList([1, 0, 0, 0, 0, 0]);
    {
      final bd = ByteData.view(pkt.buffer);

      bd.setUint32(2, toRad50(task), Endian.little);
    }

    final result = await this.requestReply(
        task: "ACNET@" + node,
        data: pkt,
        timeout: 200);

    if (result.status.isGood) {
      final v = Uint8List.fromList(result.message);
      final bd = ByteData.view(v.buffer);

      // Result is simply a 16-bit value.

      if (bd.lengthInBytes == 2)
        return bd.getUint16(0, Endian.little);
      else
        throw ACNET_TRUNC_REPLY;
    } else
      throw result.status;
  }

  /// Retrieves a snapshot of the tasks connected to an ACNET node.
  Future<Map<int, TaskInfo>> getTaskInfo({String node}) async {
    final result = await this.requestReply(
        task: "ACNET@" + node,
        data: Uint8List.fromList(const [4, 3]),
        timeout: 500);

    if (result.status.isGood) {
      final v = Uint8List.fromList(result.message);
      final bd = ByteData.view(v.buffer);
      final total = bd.getUint16(0, Endian.little);
      var m = HashMap<int, TaskInfo>();

      if (bd.buffer.lengthInBytes >= 2 + total * 11) {
        for (var ii = 0; ii < total; ++ii) {
          final offset = 2 + ii * 11;

          m[bd.getUint16(offset, Endian.little)] = TaskInfo(
              (bd.getUint8(offset + 2) & 1) != 0
                  ? TaskType.Server
                  : TaskType.Client,
              toString(bd.getUint32(offset + 3, Endian.little)),
              bd.getUint32(offset + 7, Endian.little));
        }
        return m;
      } else
        throw ACNET_TRUNC_REPLY;
    } else
      throw result.status;
  }

  /// Get the versions associated with the specified ACNET node.
  ///
  /// The return value is a list of 3 strings representing the three version
  /// numbers used to identify aspect of ACNET. The first version represents
  /// the version of the network layout. ACNET nodes with the same, first
  /// version should be able to communicate. The second version is associated
  /// with internals of the local ACNET process/library. The third version
  /// represent the local API that clients use to communicate with their ACNET
  /// process/library.
  Future<List<String>> getVersions({String node}) async {
    final result = await this.requestReply(
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

  /// Pings the specified ACNET node. If this method returns [true], the remote
  /// node responded.
  Future<bool> ping({String node}) async {
    final result = await this.requestReply(
        task: "ACNET@" + node,
        data: Uint8List.fromList(const [0, 0]),
        timeout: 100);

    return result.status.isGood && result.message.length == 2;
  }
}
