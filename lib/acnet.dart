/// Communication library allowing Dart applications to be ACNET clients.
///
/// This is a low-level communications library which is used to build
/// higher-level ACNET service libraries.
///
/// This module is available through `git`. This library is under active
/// development so expect breaking changes between versions until we reach 1.0.
/// `pubspec.yaml` pulls in ANET support with the following entry:
///
/// ```
/// dependencies:
///  acnet:
///    git:
///      url: https://cdcvs.fnal.gov/projects/acnetd-dart
///      ref: v0.x
/// ```
///
/// The `ref` field, in this example, specifies the 0.x branch so it will
/// automatically sync with the latest developments on that branch. If you
/// want to use a specific version, you can use a `git` tag. Every release
/// will have a tag associated with it.
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
