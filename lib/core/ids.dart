import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// Deterministic positive 31-bit hash, used for notification ids.
int stableHash(String s) {
  var h = 17;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x3fffffff;
  }
  return h;
}
