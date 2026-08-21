# Production Authentication Provider Decision

The backend now supports a generic **OpenID Connect (OIDC)** resource-server contract. In production, the API validates provider-issued bearer tokens using the provider's discovery metadata, issuer, audience, and JWKS signing keys. It does not trust a mobile-provided role flag. Admin access is derived from a configured signed-token claim and allowlisted values.

OpenID Connect defines the issuer, subject, audience, and expiration claims used to validate identity assertions, while Discovery publishes the provider metadata and `jwks_uri` used to validate signatures.[1] [2]

| Variable | Purpose |
|---|---|
| `AUTH_PROVIDER=oidc` | Enables provider-token verification instead of demo JWTs |
| `OIDC_ISSUER_URL` | Exact HTTPS issuer URL; must match discovery metadata and token `iss` |
| `OIDC_AUDIENCE` | API audience that must be present in the validated token |
| `OIDC_ADMIN_CLAIM` | Signed token claim used to identify administrators; default `roles` |
| `OIDC_ADMIN_VALUES` | Comma-separated allowlist; default `admin` |

The mobile client uses Flutter AppAuth's authorization-code flow and provider discovery. Configure its values through build-time `--dart-define` settings rather than committing client-specific secrets. The API continues to expose demo login only when `DEMO_MODE=true` outside production.

## Release requirements

The identity provider must use HTTPS, publish a stable discovery document and JWKS endpoint, register the Android/iOS redirect URIs, and issue access tokens for the API audience. The deployment must also define a real user provisioning policy, verified-email policy, account deletion behavior, token lifetime and revocation policy, and secure token storage for the selected mobile release configuration.

## References

[1]: https://openid.net/specs/openid-connect-core-1_0.html "OpenID Connect Core 1.0 incorporating errata set 2"
[2]: https://openid.net/specs/openid-connect-discovery-1_0-21.html "OpenID Connect Discovery 1.0"
