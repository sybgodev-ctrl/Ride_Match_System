# GoApp Enterprise Setup (Aligned to Architecture Doc)

This setup operationalizes the core infra from `GoApp-Enterprise-Architecture-248-Tables-OTP-Login.md`:
- PostgreSQL for identity/OTP domain bootstrap
- Redis for cache/geo/lock migration path
- Kafka for event bus migration path

## 1) Start infrastructure

```bash
cd goapp-server/enterprise-setup
docker compose up -d
```

## 2) Verify infrastructure

```bash
docker compose ps
```

You should see healthy containers:
- `goapp-postgres` on `5432`
- `goapp-redis` on `6379`
- `goapp-zookeeper` on `2181`
- `goapp-kafka` on `9092`

## 3) Initialize Kafka topics

```bash
./scripts/init-topics.sh
```

## 4) SQL schema bootstrap

Postgres auto-loads SQL files in `./sql` on first startup.
Included file:
- `001_identity_and_otp.sql` (users, sessions, OTP requests/attempts/rate-limits and supporting tables)

If you already had a volume, recreate postgres volume to re-run init scripts:

```bash
docker compose down -v
docker compose up -d
```

## 5) Run app in current mode (in-memory runtime + enterprise-ready config)

```bash
cd ..
cp .env.example .env
node server.js --api-only
```

## 6) Validate endpoints

```bash
curl http://localhost:3000/api/v1/health
curl http://localhost:3000/api/v1/microservices
curl http://localhost:3000/api/v1/aws/readiness
curl -X POST http://localhost:3000/api/v1/auth/otp/request \
  -H 'Content-Type: application/json' \
  -d '{"phoneNumber":"+919876543210","otpType":"login"}'
```

---

## Coverage vs architecture doc

Implemented here now:
- Identity + OTP persistent schema bootstrap
- External Redis/Kafka local stack for migration
- Topic initialization script for event contracts

Still staged (next phase):
- Replace in-memory repositories with PostgreSQL repositories
- Replace local event bus with Kafka producers/consumers in app code
- Split runtime into separate deployable services by `SERVICE_NAME`
