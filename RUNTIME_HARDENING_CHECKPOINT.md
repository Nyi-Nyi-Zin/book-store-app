# Runtime Hardening Checkpoint

The backend runtime hardening pass added request IDs, security headers, strict production CORS requirements, configurable API/auth rate limits, and structured validation/error responses.

The first smoke test exposed an important issue: Zod validation thrown inside an `async` Express route was not reaching the Express 4 error middleware and terminated the Node process. The demo-auth and health routes are now wrapped with an async error-propagation helper so invalid requests return HTTP 400 with a request ID instead of crashing the service.

Validation evidence:

| Check | Result |
|---|---|
| TypeScript check | Passed |
| Backend build | Passed |
| Health response | Passed |
| Request ID header | Passed in initial hardening check |
| Invalid demo-auth request | HTTP 400 after async-wrapper fix |
| Production missing CORS origins | Startup rejected |
| API rate limit | HTTP 429 after configured threshold |
| Security headers | `nosniff`, `DENY`, `no-referrer`, and restrictive permissions policy added |

The local validation servers were stopped after testing. The rate limiter remains in-memory and is suitable only for a single-instance deployment; a multi-instance production deployment should use a shared Redis or equivalent limiter store.
