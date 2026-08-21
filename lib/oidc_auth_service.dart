import 'package:flutter_appauth/flutter_appauth.dart';

class OidcAuthConfig {
  const OidcAuthConfig({
    required this.clientId,
    required this.redirectUrl,
    required this.discoveryUrl,
    this.scopes = const ['openid', 'profile', 'email'],
  });

  final String clientId;
  final String redirectUrl;
  final String discoveryUrl;
  final List<String> scopes;

  bool get isConfigured =>
      clientId.isNotEmpty && redirectUrl.isNotEmpty && discoveryUrl.isNotEmpty;

  factory OidcAuthConfig.fromEnvironment() => OidcAuthConfig(
    clientId: const String.fromEnvironment('OIDC_CLIENT_ID'),
    redirectUrl: const String.fromEnvironment(
      'OIDC_REDIRECT_URL',
      defaultValue: 'com.manus.flutterbookapp:/oauthredirect',
    ),
    discoveryUrl: const String.fromEnvironment('OIDC_DISCOVERY_URL'),
  );
}

class OidcAuthResult {
  const OidcAuthResult({required this.accessToken, this.idToken});

  final String accessToken;
  final String? idToken;
}

class OidcAuthService {
  OidcAuthService({OidcAuthConfig? config})
    : config = config ?? OidcAuthConfig.fromEnvironment();

  final OidcAuthConfig config;
  final FlutterAppAuth _appAuth = const FlutterAppAuth();

  Future<OidcAuthResult> signIn() async {
    if (!config.isConfigured) {
      throw StateError(
        'OIDC is not configured. Supply OIDC_CLIENT_ID and OIDC_DISCOVERY_URL with --dart-define.',
      );
    }
    final response = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        config.clientId,
        config.redirectUrl,
        discoveryUrl: config.discoveryUrl,
        scopes: config.scopes,
        externalUserAgent: ExternalUserAgent.asWebAuthenticationSession,
      ),
    );
    final accessToken = response.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('OIDC provider returned no access token');
    }
    return OidcAuthResult(accessToken: accessToken, idToken: response.idToken);
  }
}
