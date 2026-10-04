import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/constants.dart';
import '../core/errors.dart';

// Deriv returns balance as a STRING in the accounts list (e.g. "9978.59"), so accept both.
double _toD(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);

class Account {
  final String id, type, currency, status;
  final double balance;
  Account(this.id, this.type, this.currency, this.status, this.balance);
  bool get isReal => type == 'real';
  bool get active => status == 'active';
  factory Account.fromJson(Map j) => Account(
        j['account_id'] as String, j['account_type'] as String? ?? 'demo', j['currency'] as String? ?? 'USD',
        j['status'] as String? ?? 'active', _toD(j['balance']));
  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'currency': currency, 'status': status, 'balance': balance};
}

/// REST layer for the CURRENT Deriv Options API (https://api.derivws.com). PAT apps send
/// "Authorization: Bearer <PAT>" + "Deriv-App-ID". The PAT is never logged or put in exceptions.
class DerivRest {
  final String appId;
  DerivRest(this.appId);

  Future<List<Account>> accounts(String pat) async {
    final j = await _call('GET', '/trading/v1/options/accounts', pat);
    final data = (j is Map ? j['data'] : null);
    if (data is! List) throw DerivException(Err.accountNotFound, 'Unexpected accounts response shape');
    return data.whereType<Map>().where((m) => m['account_id'] is String).map(Account.fromJson).toList();
  }

  /// Returns the ready-to-use wss URL with a fresh one-time password embedded.
  Future<String> otpUrl(String pat, String accountId) async {
    final j = await _call('POST', '/trading/v1/options/accounts/${Uri.encodeComponent(accountId)}/otp', pat, otp: true);
    final url = (j is Map && j['data'] is Map) ? (j['data'] as Map)['url'] : null;
    if (url is! String || !url.startsWith('wss://')) throw DerivException(Err.otpFailed, 'OTP response had no wss url', retryable: true);
    return url;
  }

  Future<dynamic> _call(String method, String path, String pat, {bool otp = false}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse('$kRestBase$path');
      final req = await (method == 'GET' ? client.getUrl(uri) : client.postUrl(uri));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $pat');
      req.headers.set('Deriv-App-ID', appId);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (method == 'POST') req.contentLength = 0;
      final res = await req.close().timeout(const Duration(seconds: 12));
      final body = await res.transform(utf8.decoder).join();
      dynamic j;
      try { j = jsonDecode(body); } catch (_) {}
      if (res.statusCode >= 200 && res.statusCode < 300) return j;
      throw _map(res.statusCode, j, otp, body);
    } on TimeoutException {
      throw DerivException(Err.network, 'Request timed out', retryable: true);
    } on IOException catch (e) {
      throw DerivException(Err.network, '${e.runtimeType}: $e', retryable: true);
    } finally {
      client.close(force: true);
    }
  }

  DerivException _map(int status, dynamic j, bool otp, String body) {
    String code = '', msg = '';
    if (j is Map && j['errors'] is List && (j['errors'] as List).isNotEmpty) {
      final e = (j['errors'] as List).first;
      if (e is Map) { code = '${e['code'] ?? ''}'; msg = '${e['message'] ?? ''}'; }
    }
    var raw = '';
    if (code.isEmpty && msg.isEmpty && body.isNotEmpty) {
      raw = ': ${body.replaceAll(RegExp(r'\s+'), ' ')}';
      if (raw.length > 180) raw = '${raw.substring(0, 180)}...';
    }
    final tech = 'HTTP $status${code.isEmpty ? '' : ' $code'}${msg.isEmpty ? '' : ': $msg'}$raw [AppID ${appId.length > 6 ? '${appId.substring(0, 4)}...' : appId}]';
    final lower = '$code $msg'.toLowerCase();
    if (status == 401) {
      return DerivException(lower.contains('expired') ? Err.patExpired : Err.patInvalid, '$tech (also check Deriv-App-ID)');
    }
    if (status == 403) return DerivException(Err.patScopeMissing, tech);
    if (status == 404) return DerivException(Err.accountNotFound, tech);
    if (status == 429) return DerivException(Err.network, '$tech (rate limited)', retryable: true);
    if (status == 400) return DerivException(otp ? Err.accountNotFound : Err.patInvalid, tech);
    return DerivException(otp ? Err.otpFailed : Err.network, tech, retryable: true);
  }
}
