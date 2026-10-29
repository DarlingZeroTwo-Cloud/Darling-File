import 'dart:convert';
import 'package:http/http.dart' as http;

const String kBridge = 'http://127.0.0.1:18924';
const String kVersion = '0.1';

class Api {
  static Future<Map<String, dynamic>> _call(String path,
      {Map<String, dynamic>? body, String method = 'GET'}) async {
    try {
      final uri = Uri.parse('$kBridge$path');
      http.Response resp;
      if (method == 'POST') {
        resp = await http
            .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 30));
      } else {
        resp = await http.get(uri).timeout(const Duration(seconds: 15));
      }
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      return {'ok': false, 'error': '无法连接传输核心: $e'};
    }
  }

  static Future<Map<String, dynamic>> login(String email, String password) =>
      _call('/api/login', body: {'email': email, 'password': password}, method: 'POST');
  static Future<Map<String, dynamic>> register(String email, String password, String securityQ, String securityA) =>
      _call('/api/register', body: {'email': email, 'password': password, 'security_q': securityQ, 'security_a': securityA}, method: 'POST');
  static Future<Map<String, dynamic>> logout() => _call('/api/logout', method: 'POST');
  static Future<Map<String, dynamic>> me() => _call('/api/me');
  static Future<Map<String, dynamic>> peers() => _call('/api/peers');
  static Future<Map<String, dynamic>> incoming() => _call('/api/incoming');
  static Future<Map<String, dynamic>> history() => _call('/api/history');
  static Future<Map<String, dynamic>> status() => _call('/api/status');
  static Future<Map<String, dynamic>> send(String path,
          {String method = 'auto', String? ip}) =>
      _call('/api/send', body: {'path': path, 'method': method, 'ip': ip}, method: 'POST');
  static Future<Map<String, dynamic>> sendMulti(List<String> files) =>
      _call('/api/send-multi', body: {'files': files}, method: 'POST');
  static Future<Map<String, dynamic>> relayQuery(String code) =>
      _call('/api/relay/query', body: {'code': code}, method: 'POST');
  static Future<Map<String, dynamic>> relayRecv(String code) =>
      _call('/api/relay/recv', body: {'code': code}, method: 'POST');
  static Future<Map<String, dynamic>> relayRelease(String code) =>
      _call('/api/relay/release', body: {'code': code}, method: 'POST');
  static Future<Map<String, dynamic>> webShare(List<String> files) =>
      _call('/api/web-share', body: {'files': files}, method: 'POST');
}
