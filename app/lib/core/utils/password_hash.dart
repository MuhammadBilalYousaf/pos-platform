import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One-way hash for business secrets stored in Firestore.
/// Plaintext is never persisted; only the hash is compared at validation time.
String hashBusinessSecret(String value, {required String businessId}) {
  final normalized = value.trim();
  final material = utf8.encode('$businessId::order_cancel::$normalized');
  return sha256.convert(material).toString();
}

bool matchesBusinessSecret({
  required String input,
  required String storedHash,
  required String businessId,
}) {
  if (storedHash.isEmpty) return false;
  return hashBusinessSecret(input, businessId: businessId) == storedHash;
}
