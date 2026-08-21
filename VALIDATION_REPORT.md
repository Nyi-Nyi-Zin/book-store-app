# Validation Report

The current feature-flow pass completed the following checks successfully.

| Area | Check | Result |
|---|---|---|
| Flutter | `dart format lib test` | Passed |
| Flutter | `flutter analyze` | No issues found |
| Flutter | `flutter test` | 2 widget tests passed |
| Backend | `pnpm run check` | Passed |
| Backend | `pnpm run build` | Passed |
| Premium/access | Free access returns `403`; demo verification returns active entitlement; full access returns `200` | Passed |
| Reader | Progress save and bookmark create/list flow | Passed |
| Admin | PDF upload, publish transition, conversion jobs, and audit log | Passed |
| Conversion | EPUB fixture rendered to a one-page PDF | Passed |
| CI | GitHub Actions workflow structural checks | Passed |
| Security | Production startup rejects missing/weak `JWT_SECRET`; demo routes require explicit development mode | Passed |
| PDF reader | `flutter_pdfview` integration, local cache path, protected byte download, and Premium-only file route | Passed |
| Persistence boundary | Optional MySQL adapter compiles, health metadata exposes DB state, and required-DB guard fails closed | Passed |
| Production config | Demo auth/local storage are rejected in production unless explicitly overridden | Passed |
| Account flows | Subscription status, deletion request, provider sign-up contract, and production auth guard | Passed |

The local demo billing path remains available only when `DEMO_MODE=true` and `BILLING_VERIFY_MODE=demo`. The production path now contains Apple App Store Server API lookup with signed JWS certificate-chain verification, Google Play SubscriptionPurchaseV2 lookup with active-subscription acknowledgement, idempotent transaction tracking, and Apple/Google notification route boundaries. Actual provider credentials, product setup, webhook registration, database, storage, and staging verification are still required before launch.

## Final release-candidate checkpoint

| Area | Check | Result |
|---|---|---|
| Android | `flutter build apk --release --no-shrink` | Passed; 67.0 MB APK |
| Android | `flutter build appbundle --release --no-shrink` | Passed; 60.6 MB AAB |
| Android | APK/AAB archive integrity and SHA-256 checksums | Passed |
| Flutter auth | OIDC AppAuth path, secure-storage session persistence, redirect-scheme configuration | Analyzer/tests/build passed |
| Backend auth | OIDC issuer/audience/JWKS contract and production fail-closed guard | Passed |
| Storage | S3-compatible adapter, signed URL boundary, local fallback flow, production storage guard | Passed |
| Operations | Request IDs, structured request logs, `/api/health`, `/api/ready` | Passed |
| Account | Notification preferences, public legal config, account deletion boundary | Passed |
| Deployment | Backend Dockerfile, production Compose template, CI workflow, deployment runbook | Structural validation passed |

Final Android artifacts:

```text
APK SHA-256  27643090633d9440383614b7979198f514515a0e4587deec9b644bf7aa64f02c
AAB SHA-256  b790e5c2e5adfdc3095e0e4ba30d056cbde56b30dce6eedacc2e41bde3553cf9
```
