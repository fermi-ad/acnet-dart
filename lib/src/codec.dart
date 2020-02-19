abstract class Codec<T, R> {
  List<int> encode(T msg);
  R decode(List<int> pkt);
}

/// The `RawCodec` is used to send binary packets to and from ACNET. Binary
/// packets implement the `List<int> interface. It is usually better to create
/// a Codec that translates to and from a Dart data type, but this is here for
/// occasionally used protocols in ACNET that are binary.

class RawCodec implements Codec<List<int>, List<int>> {
  List<int> encode(List<int> msg) => msg;
  List<int> decode(List<int> pkt) => pkt;
}