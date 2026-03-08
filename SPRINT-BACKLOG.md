# Ride Match System - Sprint Backlog (18 Weeks)

## Owner Map (Role-Based)
- `PL`: Program Lead
- `INFRA`: Platform/DevOps
- `DBA`: Data Engineer/DBA
- `BE-ID`: Backend Identity Team
- `BE-RIDE`: Backend Core Ride Team
- `BE-DISP`: Backend Dispatch Team
- `BE-PAY`: Backend Payments Team
- `BE-SUP`: Backend Supporting Services Team
- `QA`: QA/Automation
- `SRE`: Reliability/Observability
- `SEC`: Security/Compliance

## Estimation Scale
- `S` = 2-3 days
- `M` = 4-6 days
- `L` = 7-10 days
- `XL` = 11+ days

## Sprint Plan

### Sprint 1 (Weeks 1-2) - Foundation Bootstrap
| Ticket | Cut | Title | Owner | Est | Acceptance Criteria |
|---|---|---|---|---|---|
| SP1-01 | P1 | Provision Postgres, Redis, Kafka for dev/stage | INFRA | L | Environments reachable; secrets managed; health checks passing |
| SP1-02 | P1 | Run all enterprise SQL migrations in CI pipeline | DBA | L | CI migration job green; repeatable from clean DB |
| SP1-03 | P1 | Add schema drift and rollback verification jobs | DBA | M | Drift check fails on unauthorized schema changes; rollback smoke test passes |
| SP1-04 | P1 | Establish service boundary and event ownership doc for C01-C05 | PL | M | Boundary doc approved by BE-ID/BE-RIDE/BE-DISP |
| SP1-05 | P1 | Add feature flag framework for cutover control | BE-RIDE | M | Per-cut flags available and toggleable per environment |
| SP1-06 | P1 | Baseline observability stack (logs/metrics/traces) | SRE | L | Dashboards + alert channels configured; sample telemetry visible |

### Sprint 2 (Weeks 3-4) - C01 Identity Service
| Ticket | Cut | Title | Owner | Est | Acceptance Criteria |
|---|---|---|---|---|---|
| SP2-01 | C01 | Implement DB-backed OTP/session repository | BE-ID | L | OTP/session reads/writes persist in Postgres |
| SP2-02 | C01 | Identity service API contract (OpenAPI) + versioning | BE-ID | M | Contract published; versioning strategy documented |
| SP2-03 | C01 | Rate-limit + abuse protection hardening | BE-ID | M | OTP flood tests blocked; retry windows enforced |
| SP2-04 | C01 | Identity events to Kafka with schema validation | BE-ID | M | `otp_requested`/`otp_verified` topics produced/consumed in stage |
| SP2-05 | C01 | Identity contract tests + integration tests in CI | QA | M | CI contract and integration suites green |
| SP2-06 | C01 | Cutover identity flows behind feature flag | PL | S | Stage traffic can be switched to C01 and rolled back |

### Sprint 3 (Weeks 5-6) - C02 Rider + C03 Driver Foundations
| Ticket | Cut | Title | Owner | Est | Acceptance Criteria |
|---|---|---|---|---|---|
| SP3-01 | C02 | Rider profile + lifecycle DB APIs | BE-RIDE | L | Rider CRUD + status transitions DB-backed |
| SP3-02 | C03 | Driver profile/status APIs + state persistence | BE-RIDE | L | Driver status/reachability persisted and queryable |
| SP3-03 | C02/C03 | Rider/Driver event topics + consumer skeletons | BE-RIDE | M | Topics emitting valid schemas; consumer lag monitored |
| SP3-04 | C03 | Driver document auth controls + storage policy | SEC | M | Document endpoints enforce auth; audit logs present |
| SP3-05 | C02/C03 | Contract/integration test packs | QA | M | Rider/Driver test packs pass in CI |
| SP3-06 | C02/C03 | Stage cutover for profile reads | PL | S | Read traffic switched successfully with rollback |

### Sprint 4 (Weeks 7-8) - C04 Ride Service
| Ticket | Cut | Title | Owner | Est | Acceptance Criteria |
|---|---|---|---|---|---|
| SP4-01 | C04 | Persisted ride state machine with legal transitions | BE-RIDE | XL | Ride transitions enforce rules; invalid transitions return 4xx/422 |
| SP4-02 | C04 | Idempotency repository for ride create/complete | BE-RIDE | M | Duplicate request replay returns same result safely |
| SP4-03 | C04 | Active-ride recovery from persisted state | BE-RIDE | M | Restart/reconnect preserves active ride lookup |
| SP4-04 | C04 | Ride events to Kafka + replay test harness | BE-RIDE | M | Event replay reconstructs ride lifecycle accurately |
| SP4-05 | C04 | End-to-end rider journey tests (request -> complete) | QA | L | E2E suite stable in stage |
| SP4-06 | C04 | Progressive cutover of write traffic | PL | M | >=50% stage writes on C04 path with rollback proven |

### Sprint 5 (Weeks 9-10) - C05 Dispatch/Matching + C06 Pricing
| Ticket | Cut | Title | Owner | Est | Acceptance Criteria |
|---|---|---|---|---|---|
| SP5-01 | C05 | Dispatch attempt persistence + lock semantics | BE-DISP | XL | No double assignment in concurrency test suite |
| SP5-02 | C05 | Redis lock/cache policy and timeout tuning | BE-DISP | M | Lock TTL and fallback behavior documented + validated |
| SP5-03 | C06 | Pricing service extraction and fare API | BE-SUP | L | Fare estimate endpoint served by C06 |
| SP5-04 | C06 | Surge model persistence + recalc scheduler | BE-SUP | M | Surge states persisted and recalculated on schedule |
| SP5-05 | C05/C06 | Dispatch-pricing integration contract tests | QA | M | Dispatch uses C06 contracts with passing tests |
| SP5-06 | C05/C06 | Performance benchmark and SLO baseline | SRE | M | P95, throughput, error rates published |

### Sprint 6 (Weeks 11-12) - C07 Payment/Wallet + C08 Notification
| Ticket | Cut | Title | Owner | Est | Acceptance Criteria |
|---|---|---|---|---|---|
| SP6-01 | C07 | Ledger-based wallet schema + transaction APIs | BE-PAY | XL | Debit/credit invariants hold; reconciliation query available |
| SP6-02 | C07 | Razorpay webhook verification + replay protection | BE-PAY | M | Duplicate webhook replay does not double-credit |
| SP6-03 | C07 | Payment events + settlement status topics | BE-PAY | M | Event schemas validated; settlement status traceable |
| SP6-04 | C08 | Notification service extraction (FCM/SMS abstraction) | BE-SUP | L | Notification dispatch decoupled from monolith |
| SP6-05 | C08 | Delivery telemetry and dead-letter handling | BE-SUP | M | Failure retries + DLQ metrics visible |
| SP6-06 | C07/C08 | Payment + notification E2E tests | QA | L | Payment success/failure paths produce expected notifications |

### Sprint 7 (Weeks 13-14) - C09 Safety/SOS + C10 Fraud/Risk
| Ticket | Cut | Title | Owner | Est | Acceptance Criteria |
|---|---|---|---|---|---|
| SP7-01 | C09 | SOS incident lifecycle APIs + audit timeline | BE-SUP | L | Incident create/update/resolve with immutable audit log |
| SP7-02 | C09 | Escalation workflows and SLA alerts | SRE | M | SLA breach alerts fire in stage simulation |
| SP7-03 | C10 | Fraud rule engine extraction + reason codes | BE-SUP | L | Decisions logged with deterministic reason codes |
| SP7-04 | C10 | Risk scoring stream processor from Kafka | BE-SUP | M | Streaming decisions persisted with idempotency |
| SP7-05 | C09/C10 | Security threat model + abuse test suite | SEC | M | Threat model signed off; abuse cases covered in CI |
| SP7-06 | C09/C10 | Operational runbooks and incident drills | SRE | M | Drill run completed; MTTR documented |

### Sprint 8 (Weeks 15-16) - C11/C12/C13 Enhancements
| Ticket | Cut | Title | Owner | Est | Acceptance Criteria |
|---|---|---|---|---|---|
| SP8-01 | C11 | Promotions/referrals service extraction | BE-SUP | L | Promo validation and redemption APIs live |
| SP8-02 | C12 | Driver incentives service extraction | BE-SUP | L | Incentive earn/claim and leaderboard APIs live |
| SP8-03 | C13 | Support/ticket service extraction + assignment flow | BE-SUP | L | Ticket open/respond/assign/resolve flows complete |
| SP8-04 | C11/C12/C13 | Cross-service auth and role policies | SEC | M | Role checks pass policy tests |
| SP8-05 | C11/C12/C13 | Contract tests + load tests | QA | L | Contract and load thresholds meet SLO targets |
| SP8-06 | C11/C12/C13 | Stage feature parity sign-off | PL | S | Product and QA sign-off recorded |

### Sprint 9 (Weeks 17-18) - C14/C15/C16/C17 + Launch Readiness
| Ticket | Cut | Title | Owner | Est | Acceptance Criteria |
|---|---|---|---|---|---|
| SP9-01 | C14 | Scheduling service (future/recurring rides) | BE-SUP | L | Scheduled ride create/modify/cancel works with dispatch handoff |
| SP9-02 | C15 | Corporate/B2B account and billing service | BE-SUP | L | Org, policy, and invoicing APIs functional |
| SP9-03 | C16 | Compliance service (audit/export/retention controls) | SEC | L | Audit export + retention jobs verified |
| SP9-04 | C17 | Analytics ingestion + core marts (rides/payments/demand) | DBA | XL | Data completeness >= 99.9% and marts validated |
| SP9-05 | P5 | DR drill + backup restore + chaos test | SRE | M | RTO/RPO targets met in report |
| SP9-06 | P5 | Production readiness review + cutover checklist | PL | M | Go-live checklist complete; rollback and on-call roster approved |

## Backlog Hygiene Rules
- Every ticket must reference one `Cut ID` and one API/event contract artifact.
- No ticket closes without test evidence linked (CI job URL/report).
- Any schema-affecting ticket must include rollback proof.
- Feature flags are required for all traffic-moving tickets.

## Suggested Capacity Split (per sprint)
- 30% core feature implementation
- 25% integration/testing
- 20% data and migration safety
- 15% observability/reliability
- 10% security/compliance hardening

## Optional Next Layer
If you want, next step is generating a Jira-ready CSV (`Ticket`, `Summary`, `Description`, `Owner`, `Story Points`, `Sprint`, `Acceptance Criteria`) from this document.
