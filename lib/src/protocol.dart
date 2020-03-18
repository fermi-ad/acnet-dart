abstract class Protocol<T, R> {
  const Protocol();

  List<int> encode(T message);
  R decode(List<int> data);
}