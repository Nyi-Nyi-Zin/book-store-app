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

  bool get hasSession => token != null && token!.isNotEmpty;

  void setToken(String? value) => token = value;

  void clearSession() => token = null;

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

  Future<Map<String, dynamic>> subscriptionStatus() async =>
      _get('/api/account/subscription');

  Future<Map<String, dynamic>> requestAccountDeletion() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/account/delete-request'),
      headers: _headers,
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> requestSignUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/signup'),
      headers: _headers,
      body: jsonEncode({'name': name, 'email': email, 'password': password}),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/password-reset'),
      headers: _headers,
      body: jsonEncode({'email': email}),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> catalog() async => _get('/api/books');

  Future<Map<String, dynamic>> fullBookAccess(int bookId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/books/$bookId/access'),
      headers: _headers,
    );
    return _decode(response);
  }

  Future<List<int>> downloadProtectedBook(int bookId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/books/$bookId/file'),
      headers: _headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decode(response);
    }
    return response.bodyBytes;
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

  Future<Map<String, dynamic>> getBookmarks(int bookId) async =>
      _get('/api/reader/bookmarks/$bookId');

  Future<Map<String, dynamic>> addBookmark({
    required int bookId,
    required int pageNumber,
    String? note,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/reader/bookmarks/$bookId'),
      headers: _headers,
      body: jsonEncode({'pageNumber': pageNumber, 'note': note}),
    );
    return _decode(response);
  }

  Future<void> deleteBookmark({
    required int bookId,
    required String bookmarkId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/reader/bookmarks/$bookId/$bookmarkId'),
      headers: _headers,
    );
    if (response.statusCode != 204) _decode(response);
  }

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

  Future<Map<String, dynamic>> publishBook(int bookId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/books/$bookId/publish'),
      headers: _headers,
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> unpublishBook(int bookId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/books/$bookId/unpublish'),
      headers: _headers,
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> adminJobs() async => _get('/api/admin/jobs');
  Future<Map<String, dynamic>> adminAudit() async => _get('/api/admin/audit');

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
