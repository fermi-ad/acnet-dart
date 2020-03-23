/// Communication library allowing Dart applications to be ACNET clients. This
/// is a low-level communications library which is used to build higher-level
/// ACNET service libraries.
///
/// Connecting to the ACNET control system is easy. To get a connection, create
/// a [Connection] object.
///
/// ```
/// import 'package:acnet.dart';
///
/// final con = Connection();
/// ```
///
/// The [Connection] class defines several utility methods which query the
/// local `acnetd` instance. To communicate with remote tasks, use the
/// `.requestReply()` and `.requestReplyStream()` methods.
library acnet;

export 'src/protocol.dart';
export 'src/rawprotocol.dart';
export 'src/status.dart';
export 'src/connection.dart';
