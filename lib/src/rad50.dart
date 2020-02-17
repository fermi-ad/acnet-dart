import 'dart:core';

int _charToIndex(String c) {
  if (c.compareTo("A") >= 0 && c.compareTo("Z") <= 0)
    return c.codeUnitAt(0) - 64;
  else if (c.compareTo("a") >= 0 && c.compareTo("z") <= 0)
    return c.codeUnitAt(0) - 96;
  else if (c.compareTo("0") >= 0 && c.compareTo("9") <= 0)
    return c.codeUnitAt(0) - 18;
  else if (c == "\$")
    return 27;
  else if (c == "\.")
    return 28;
  else if (c == "%")
    return 29;
  return 0;
}

// Converts a string into a RAD50 value. The RAD50 character set is limited
// so characters not in the set are mapped to the 'space' character.

int to_rad50(String s) {
  var v1 = 0;
  var v2 = 0;

  for (var ii = 0; ii < 6; ++ii) {
    final c = ii < s.length ? s[ii] : " ";

    if (ii < 3)
      v1 = v1 * 40 + _charToIndex(c);
    else
      v2 = v2 * 40 + _charToIndex(c);
  }
  return (v2 << 16) | v1;
}

// Converts a RAD50 value into a string containing the RAD50
// translation.

String toString(int r50) {
  const chars = " ABCDEFGHIJKLMNOPQRSTUVWXYZ\$.%0123456789";
  var s = [" ", " ", " ", " ", " ", " "];
  var v1 = r50 & 0xffff;
  var v2 = (r50 >> 16) & 0xffff;

  for (var ii = 0; ii < 3; ii++) {
    s[2 - ii] = chars[v1 % 40];
    v1 ~/= 40;
    s[5 - ii] = chars[v2 % 40];
    v2 ~/= 40;
  }
  return s.join("").trim();
}
