/// Extension module for the [Connection] class to provide Level-II diagnostics.

import 'dart:collection';
import 'dart:typed_data';
import 'src/rad50.dart';
import 'src/status.dart';
import 'src/connection.dart';

enum TaskType { Client, Server }

class TaskInfo {
  final String handle;
  final int id;
  final int elapsed;
  final int usmXmt;
  final int usmRcv;
  final int reqXmt;
  final int reqRcv;
  final int rpyXmt;
  final int rpyRcv;

  const TaskInfo({this.handle, this.id, this.elapsed,
    this.usmXmt, this.usmRcv, this.reqXmt, this.reqRcv, this.rpyXmt,
    this.rpyRcv});

  @override
  String toString() {
    return "task info: { "
        "handle: ${this.handle}, id: ${this.id}, "
        "elapsed: ${this.elapsed}, "
        "usmXmt: ${this.usmXmt}, usmRcv: ${this.usmRcv}, "
        "reqXmt: ${this.reqXmt}, reqRcv: ${this.reqRcv}, "
        "rpyXmt: ${this.rpyXmt}, rpyRcv: ${this.rpyRcv} }";
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
  ///
  /// Asks the ACNET service on [node] for the ID of the named [task]. If
  /// no task has the requested name, this method throws [ACNET_NO_TASK].
  Future<int> getTaskId({String task, String node}) async {

    // Request format for task ID info (in hex):
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

  /// Retrieves a snapshot of the tasks connected to an ACNET [node].
  ///
  /// This returns a map containing information on all the tasks on an
  /// ACNET node. There are 6 fields holding counts of network packet
  /// types. For historical reasons, these counters are 16-bits so they
  /// will saturate at 64K. If the [reset] parameter is true, the counts
  /// will be reset to zero after returning the current count.
  ///
  /// Resetting the counts isn't concurrent-safe; if two apps are constantly
  /// resetting them, they will both see the effects of each other's requests
  /// (maybe they'll both see counts that are half of what's really being
  /// transferred.)
  Future<Map<int, TaskInfo>> getTaskInfo({String node, bool reset: false}) async {
    final result = await this.requestReply(
        task: "ACNET@" + node,
        data: Uint8List.fromList([7, reset ? 1 : 0]),
        timeout: 500);

    if (result.status.isGood) {
      final v = Uint8List.fromList(result.message);
      final bd = ByteData.view(v.buffer);

      if (bd.buffer.lengthInBytes >= 8) {
        final elapsed = 0;
        final total = (bd.buffer.lengthInBytes - 8) ~/ 18;
        final m = HashMap<int, TaskInfo>();

        for (var ii = 0; ii < total; ++ii) {
          final offset = 8 + ii * 18;
          final taskId = bd.getUint16(offset, Endian.little);

          m[taskId] =
              TaskInfo(elapsed: elapsed, id: taskId,
                  handle: toString(bd.getUint32(offset + 2, Endian.little)),
                  usmXmt: bd.getUint16(offset + 6, Endian.little),
                  reqXmt: bd.getUint16(offset + 8, Endian.little),
                  rpyXmt: bd.getUint16(offset + 10, Endian.little),
                  usmRcv: bd.getUint16(offset + 12, Endian.little),
                  reqRcv: bd.getUint16(offset + 14, Endian.little),
                  rpyRcv: bd.getUint16(offset + 16, Endian.little));
        }
        return m;
      } else
        throw ACNET_TRUNC_REPLY;
    } else
      throw result.status;
  }

  /// Gets the IP address for the [task] registered on [node].
  ///
  /// Clients usually run on the same node as their ACNET service. For
  /// those clients, the IP address is the same as if you looked up the
  /// IP address for the [node]. Newer clients (i.e. web apps, Python
  /// scripts, Flutter apps) connect to an ACNET service remotely. This
  /// method returns their actual location.
  ///
  /// This method only works for `acnetd`-based nodes. Other ACNET
  /// implementations cause [ACNET_LEVEL2] to be thrown.
  Future<int> getTaskIp({int taskId, String node}) async {

    // Request format for task IP info (in hex):
    //
    // +----+----+
    // | 13 | 00 |
    // +----+----+
    // | task ID |
    // +----+----+

    final pkt = Uint8List.fromList([19, 0, 0, 0]);
    {
      final bd = ByteData.view(pkt.buffer);

      bd.setUint16(2, taskId, Endian.little);
    }

    final result = await this.requestReply(
        task: "ACNET@" + node,
        data: pkt,
        timeout: 200);

    if (result.status.isGood) {
      final v = Uint8List.fromList(result.message);
      final bd = ByteData.view(v.buffer);

      if (bd.lengthInBytes == 4)
        return bd.getUint32(0, Endian.little);
      else
        throw ACNET_LEVEL2;
    } else
      throw result.status;
  }

  // Historically, ACNET only supported 127 tasks connected per node. The
  // request for this info only reserves an 8-bit field to hold it. When we
  // expanded the number in `acnetd`, a new Level2 request was created. Both
  // requests return the same reply but all non-acnetd nodes still only support
  // the old request. This function looks to see which request should be built
  // based on the value of the taskId. This should work because only
  // acnetd-hosted clients will generate a task ID greater than 255.
  static Uint8List bldTaskNameReq(int taskId) {
    if (taskId < 256)
      return Uint8List.fromList([2, taskId]);
    else
      return Uint8List.fromList([18, 0, taskId ~/ 256, taskId % 256]);
  }

  /// Returns the task name of a remote task with the given ID.
  ///
  /// Asks the ACNET service on [node] for the name of the task with
  /// ID, [taskId]. If there isn't a task with the requested ID, this
  /// method throws [ACNET_NO_TASK].
  Future<String> getTaskName({int taskId, String node}) async {
    final result = await this.requestReply(
        task: "ACNET@" + node,
        data: Level2.bldTaskNameReq(taskId),
        timeout: 500);

    if (result.status.isGood) {
      final v = Uint8List.fromList(result.message);
      final bd = ByteData.view(v.buffer);

      // Result is simply a 16-bit value.

      if (bd.lengthInBytes == 4)
        return toString(bd.getUint32(0, Endian.little));
      else
        throw ACNET_TRUNC_REPLY;
    } else
      throw result.status;
  }

  /// Get the versions associated with the specified ACNET [node].
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

  /// Pings the specified ACNET [node].
  ///
  /// If this method returns [true], the remote node responded.
  Future<bool> ping({String node}) async {
    final result = await this.requestReply(
        task: "ACNET@" + node,
        data: Uint8List.fromList(const [0, 0]),
        timeout: 100);

    return result.status.isGood && result.message.length == 2;
  }
}
