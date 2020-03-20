import 'protocol.dart';

/// The `RawProtocol` is used to send binary packets to and from ACNET. Binary
/// packets implement the `List<int> interface. It is usually better to create
/// a Codec that translates to and from a Dart data type, but this is here for
/// occasionally used protocols in ACNET that are binary.

class RawProtocol extends Protocol<List<int>, List<int>> {
  const RawProtocol() : super();

  @override
  List<int> decode(List<int> data) => data;

  @override
  List<int> encode(List<int> message) => message;
}
