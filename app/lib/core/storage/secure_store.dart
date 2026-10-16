import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'hive_boxes.dart';

class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _deviceIdKey = 'device_id';

  Future<String?> readDeviceId() async {
    try {
      return await _storage.read(key: _deviceIdKey);
    } catch (error) {
      debugPrint('SecureStore.readDeviceId fallback: $error');
      try {
        final box = Hive.box(HiveBoxes.session);
        final value = box.get(_deviceIdKey);
        return value is String && value.isNotEmpty ? value : null;
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> writeDeviceId(String value) async {
    try {
      await _storage.write(key: _deviceIdKey, value: value);
    } catch (error) {
      debugPrint('SecureStore.writeDeviceId fallback: $error');
      try {
        await Hive.box(HiveBoxes.session).put(_deviceIdKey, value);
      } catch (_) {}
    }
  }
}
