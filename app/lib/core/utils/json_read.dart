Map<String, dynamic> asStringKeyMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return {};
}

Object? pick(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null) {
      return value;
    }
  }
  return null;
}

String readString(Map<String, dynamic> json, List<String> keys, [String fallback = '']) {
  final value = pick(json, keys);
  if (value == null) {
    return fallback;
  }
  return value.toString();
}

int readInt(Map<String, dynamic> json, List<String> keys, [int fallback = 0]) {
  final value = pick(json, keys);
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool readBool(Map<String, dynamic> json, List<String> keys) {
  final value = pick(json, keys);
  return value == true || value == 1 || value == 'true';
}

List<dynamic> readList(Map<String, dynamic> json, List<String> keys) {
  final value = pick(json, keys);
  if (value is List) {
    return value;
  }
  return const [];
}
