import '../lib/acnet.dart';

void main() async {
  var c = Connection();
  var h = await c.handle;

  print("handle is $h");
}
