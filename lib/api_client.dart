import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({String? baseUrl})
    : baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://10.0.2.2:8787',
          );

  final String baseUrl;
  String? token;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> demoAuth({
    String role = 'user',
    String name = 'Demo Reader',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/demo'),
      headers: _headers,
      body: jsonEncode({'role': role, 'name': name}),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> me() async => _get('/api/auth/me');
  Future<Map<String, dynamic>> catalog() async => _get('/api/books');

  Future<Map<String, dynamic>> fullBookAccess(int bookId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/books/$bookId/access'),
      headers: _headers,
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> activateDemoPremium() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/premium/demo-activate'),
      headers: _headers,
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> verifyPurchase({
    required String platform,
    required String productId,
    required String purchaseToken,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/premium/verify'),
      headers: _headers,
      body: jsonEncode({
        'platform': platform,
        'productId': productId,
        'purchaseToken': purchaseToken,
      }),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> getProgress(int bookId) async =>
      _get('/api/reader/progress/$bookId');

  Future<Map<String, dynamic>> saveProgress({
    required int bookId,
    required int pageNumber,
    required int percent,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/reader/progress/$bookId'),
      headers: _headers,
      body: jsonEncode({'pageNumber': pageNumber, 'percent': percent}),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> uploadBook({
    required int bookId,
    required String filename,
    required List<int> bytes,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/admin/books/$bookId/upload'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final response = await http.Response.fromStream(await request.send());
    return _decode(response);
  }

  Future<Map<String, dynamic>> _get(String path) async =>
      _decode(await http.get(Uri.parse('$baseUrl$path'), headers: _headers));

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        body['error']?.toString() ?? 'Request failed',
      );
    }
    if (body['token'] is String) token = body['token'] as String;
    return body;
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'ApiException($statusCode): $message';
}
