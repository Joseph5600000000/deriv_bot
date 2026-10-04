import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// PAT lives only in Android Keystore-backed encrypted storage. Never in SharedPreferences, logs or source.
class SecureStore {
  static const _k = 'deriv_pat_v1';
  static const _s = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  Future<String?> readPat() async { try { return await _s.read(key: _k); } catch (_) { return null; } }
  Future<void> writePat(String pat) => _s.write(key: _k, value: pat);
  Future<void> clearPat() async { try { await _s.delete(key: _k); } catch (_) {} }
}
