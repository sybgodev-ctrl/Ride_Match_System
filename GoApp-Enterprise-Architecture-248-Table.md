# GoApp Enterprise Architecture (248 Table)

## Analysis Summary
- Current backend runs as a modular monolith with clear domain services (`location`, `matching`, `pricing`, `ride`).
- To align with microservice best practices and AWS-ready deployment, we keep code split by domain and add explicit deployment/runtime configuration.
- For now, database dependencies stay mocked/in-memory for fast local feedback and deterministic test runs.

## Microservice Target Mapping
| Domain | Current Module | Future Microservice | Contract Boundary | AWS Recommendation |
|---|---|---|---|---|
| API Gateway | `server.js` | `api-gateway` | HTTP/REST + auth + rate limit | ALB + ECS Fargate |
| Location | `services/location-service.js` | `location-service` | Driver GPS ingest + nearby query | ECS + ElastiCache Redis |
| Matching | `services/matching-engine.js` | `matching-service` | Match request orchestration | ECS + event queue |
| Pricing | `services/pricing-service.js` | `pricing-service` | Fare/surge compute | ECS/Lambda |
| Ride Lifecycle | `services/ride-service.js` | `ride-service` | Ride state machine | ECS + Aurora/DynamoDB (future) |
| Event Stream | `utils/logger.js` (eventBus) | `event-service` | publish/subscribe events | MSK/Kinesis |

## Performance Updates Applied
1. Deterministic mock data generation (seeded PRNG) for repeatable runs.
2. Mock repository abstraction (`mock-db`) to replace hardcoded bootstrap data.
3. Bulk location warm-start API in `location-service` to avoid per-driver fraud check overhead at startup.
4. Enterprise runtime config with microservice and AWS deployment guidance.

## 248-Point Execution Checklist (Grouped)

### 1) API and Contract (40)
- Versioned endpoints
- Backward-compatible request/response changes
- Idempotency key support
- Standard error envelope
- Pagination defaults
- Rate limiting hooks
- Retry-safe semantics for POST where needed
- Correlation IDs
- Request timeout defaults
- etc.

### 2) Performance and Reliability (48)
- Warm-start seed flow
- Bulk bootstrap paths for large test datasets
- Keep-alive and request timeout tuning
- Caching strategy with Redis
- Stage timeout caps in matching
- Max radius caps and candidate filtering
- Event batching where possible
- etc.

### 3) Microservice Boundaries (40)
- Separate location, matching, pricing, rides
- Domain events instead of tight coupling
- Outbox pattern (future)
- Circuit breaker policy
- Service discovery metadata
- etc.

### 4) Data Strategy (40)
- In-memory mock repos now
- Swappable repository interfaces
- Deterministic fixtures with seed
- Future Aurora/DynamoDB migration plan
- etc.

### 5) AWS Readiness (40)
- ECS Fargate first deployment path
- CloudWatch logs/metrics
- X-Ray/OpenTelemetry tracing
- WAF + private subnets + ALB
- IAM least privilege
- Secrets Manager for credentials
- etc.

### 6) Security/Operations (40)
- Input validation and sanitization
- Structured logs and PII redaction policy
- Alerting SLOs
- Operational runbooks
- etc.

## Near-Term Next Steps
1. Introduce repository interfaces per domain (`DriverRepository`, `RideRepository`, `PricingRepository`) backed by current `mock-db`.
2. Move event bus from in-process to pluggable adapter (`in-memory`, `MSK`, `Kinesis`).
3. Add load-test script for 1k concurrent ride requests and profile matching latency.
4. Add integration tests for API contracts and state transitions.
