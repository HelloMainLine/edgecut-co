# Deploy Checklist — Edgecut & Co.

> **Version:** 1.0  
> **Last updated:** 2026-05-13  
> **Stack:** Vanilla HTML/CSS/JS · Postgres 16 · Stripe Connect Express  
> **Deploy targets:** Staging → Canary → Production (3-region)

---

## 1. Pre-Deploy Readiness

### 1.1 Code Freeze & Approval

- [ ] All PRs targeting the release branch are merged and reviewed
- [ ] No unresolved `BLOCKER` or `CRITICAL` severity issues in the backlog
- [ ] Release candidate tag created: `vX.Y.Z-rc1`
- [ ] Release notes drafted and shared with team (#releases channel)
- [ ] Stakeholder sign-off obtained (Product + Engineering lead)

### 1.2 Test Gates

| Check                    | Status | Tool                     |
|--------------------------|--------|--------------------------|
| Unit tests pass          | ☐      | `npm run test:unit`      |
| Integration tests pass   | ☐      | `npm run test:integration` |
| E2E tests pass           | ☐      | `npm run test:e2e`       |
| a11y (axe) — 0 violations| ☐      | `npm run test:a11y`      |
| Lighthouse ≥ 95 all cats | ☐      | `lhci autorun`           |
| Visual regression ≤ 0.5% | ☐      | `npm run test:visual`    |
| Adversarial catalog (10) | ☐      | `npm run test:adversarial` |

### 1.3 Security Checks

- [ ] `npm audit` — zero critical/high vulnerabilities
- [ ] CSP headers validated (see Section 5)
- [ ] RLS policies reviewed for all new queries
- [ ] Stripe webhook signature verification confirmed
- [ ] Idempotency keys implemented for all payment endpoints
- [ ] Input sanitization verified for all user-facing forms
- [ ] No secrets or API keys committed to repository
- [ ] Dependency scan (Snyk / Dependabot) — all clear

### 1.4 Infrastructure Checks

- [ ] Postgres 16 connection pool sized correctly (default: 25 connections × 3 tenants)
- [ ] Read replica available for calendar/dashboard queries
- [ ] CDN origins configured for static assets (`cdn1.edgecut.co`, `cdn2.edgecut.co`)
- [ ] Stripe Connect Express OAuth redirect URI registered
- [ ] Webhook endpoints registered in Stripe Dashboard (production)
- [ ] Map tile API key rotated and scoped to production domain
- [ ] DNS records created or updated (see Section 7)

---

## 2. Feature Flag Configuration

### 2.1 Flag Inventory

| Flag                    | Default | Purpose                               |
|-------------------------|---------|---------------------------------------|
| `booking-v2`            | off     | New slot allocation algorithm         |
| `stripe-connect-onboard`| on      | Self-serve Stripe onboarding for barbers |
| `map-tile-animations`   | off     | Map marker animations (perf risk)     |
| `madrid-eur-pricing`    | on      | EUR currency for Madrid tenant        |
| `cdn-fallback-v2`       | off     | New CDN fallback chain                |
| `calendar-ical-export`  | on      | iCal export button                    |

### 2.2 Canary Gates

```yaml
# config/feature-flags.yaml
features:
  booking-v2:
    rule: "tenant_slug in ['brooklyn-ny'] AND user_id % 100 < 10"
    description: "10% Brooklyn users get v2 slot allocation"
  stripe-connect-onboard:
    rule: "true"
  madrid-eur-pricing:
    rule: "tenant_slug == 'madrid-es'"
```

### 2.3 Pre-Deploy Flag Checks

- [ ] All new features are behind a feature flag (default: off)
- [ ] Kill switch exists for each flag (env var override)
- [ ] Flag evaluation is logged (tenant, user, flag, value)
- [ ] Canary percentage validated (10 % → 25 % → 50 % → 100 %)
- [ ] Rollback plan documented for each flag

---

## 3. Database Migration Plan (Expand-Contract Pattern)

### 3.1 Phase 1 — Expand (Additive)

Applied at least 1 week before Phase 2. No breaking changes.

```sql
-- 001_expand_booking_tracking.sql
BEGIN;
  ALTER TABLE bookings ADD COLUMN idempotency_key UUID;
  ALTER TABLE bookings ADD COLUMN stripe_payment_intent_id TEXT;
  CREATE INDEX idx_bookings_idempotency ON bookings (idempotency_key);
  CREATE INDEX idx_bookings_payment_intent ON bookings (stripe_payment_intent_id);
COMMIT;
```

- [ ] Migration dry-run on staging database
- [ ] Migration applied to production (read-only replica first)
- [ ] Application deployed — writes to both old and new columns
- [ ] Backfill script runs for existing rows
- [ ] Monitoring confirms no performance regression on new indexes

### 3.2 Phase 2 — Contract (Remove Old)

Applied during maintenance window after Phase 1 validation.

```sql
-- 002_contract_legacy_columns.sql
BEGIN;
  ALTER TABLE bookings DROP COLUMN legacy_status CASCADE;
  ALTER TABLE bookings DROP COLUMN legacy_payment_ref CASCADE;
COMMIT;
```

- [ ] Confirm no code references legacy columns (search: `legacy_status`, `legacy_payment_ref`)
- [ ] Run migration during low-traffic window (02:00–04:00 UTC)
- [ ] Monitor error rates for 15 minutes post-migration
- [ ] Keep rollback script ready: `003_rollback_contract.sql`

### 3.3 Migration Order

```
Expand (additive)            → Deploy app (dual-write) → Validate (1 week)
Backfill (existing rows)     → Deploy app (read-new)   → Validate (1 week)
Contract (remove old)        → Deploy app (clean)      → Validate (1 hour)
```

---

## 4. Rollback Triggers

### 4.1 Automatic Rollback (Spinnaker / ArgoCD)

| Metric                     | Threshold         | Action                |
|----------------------------|-------------------|-----------------------|
| HTTP 5xx rate              | > 1 % over 5 min | Rollback immediately   |
| P95 API latency            | > 2000 ms         | Rollback immediately   |
| Booking failure rate       | > 5 %             | Rollback + page on-call |
| Stripe payment error rate  | > 3 %             | Rollback + page on-call |
| DB connection pool exhaustion| > 80 % usage    | Rollback               |

### 4.2 Manual Rollback Triggers

- [ ] Cross-tenant data leak reported
- [ ] Double-booking confirmed in production
- [ ] CSP violation rate exceeds baseline by 10×
- [ ] CDN origin returns 5xx for > 2 % of requests
- [ ] Map tile layer completely fails (affects all tenants)

### 4.3 Rollback Procedure

```bash
# Step 1: Revert deployment
kubectl rollout undo deployment/edgecut-web -n production

# Step 2: Revert database (if contract migration ran)
psql $DATABASE_URL -f migrations/003_rollback_contract.sql

# Step 3: Disable feature flags
export FEATURE_BOOKING_V2=false

# Step 4: Verify rollback
curl -f https://edgecut.co/health && echo "OK"

# Step 5: Notify
./scripts/notify-slack.sh "Rollback vX.Y.Z completed at $(date)"
```

---

## 5. CSP Header Configuration

### 5.1 Production CSP

```nginx
# /etc/nginx/conf.d/edgecut-csp.conf
add_header Content-Security-Policy "
  default-src 'self';
  script-src 'self' 'strict-dynamic' 'nonce-${request_id}' https://js.stripe.com;
  style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;
  img-src 'self' https://cdn1.edgecut.co https://cdn2.edgecut.co data: blob:;
  font-src 'self' https://fonts.gstatic.com;
  connect-src 'self' https://api.stripe.com https://maps.googleapis.com https://browser.sentry.io;
  frame-src 'self' https://js.stripe.com https://connect.stripe.com;
  object-src 'none';
  base-uri 'self';
  form-action 'self' https://connect.stripe.com;
  report-uri https://edgecut.report-uri.com/r/d/csp/enforce;
" always;

add_header Content-Security-Policy-Report-Only "
  default-src 'self';
  script-src 'self' 'nonce-${request_id}';
  img-src 'self' https://cdn3.edgecut.co;  # future CDN candidate
  report-uri https://edgecut.report-uri.com/r/d/csp/report;
" always;
```

### 5.2 CSP Verification

- [ ] CSP headers present on all HTML responses
- [ ] Nonce values unique per request (validated in CI: `test/csp-nonce.test.js`)
- [ ] Stripe.js loads without CSP violation (test in Playwright E2E)
- [ ] Map tiles load without CSP violation
- [ ] Report-Only policy active for 1 week before enforcing
- [ ] Violation rate < 0.05 % before switching to enforce

---

## 6. CDN Cache Purge

### 6.1 Purge Scope

| Resource Type         | Path Pattern                         | TTL    | Purge Strategy     |
|-----------------------|--------------------------------------|--------|--------------------|
| Static JS/CSS         | `/assets/*.js`, `/assets/*.css`      | 1 year | Purge on each deploy |
| Barber photos         | `/images/barbers/*.webp`             | 7 days | Purge on image update |
| Service icons         | `/images/services/*.svg`             | 1 year | Purge on deploy    |
| Tenant config JSON    | `/api/tenant/*/config.json`          | 5 min  | No purge (short TTL) |
| Sitemap               | `/sitemap.xml`                       | 1 hour | Purge on content change |

### 6.2 Purge Commands

```bash
# Purge entire CDN (for asset version bumps)
curl -X POST https://api.fastly.com/service/SERVICE_ID/purge_all \
  -H "Fastly-Key: $FASTLY_API_KEY"

# Purge specific paths (targeted)
curl -X POST https://api.fastly.com/service/SERVICE_ID/purge \
  -H "Fastly-Key: $FASTLY_API_KEY" \
  -H "Surrogate-Key: assets images" \
  -d '{"paths": ["/assets/", "/images/"]}'

# Verify purge
curl -s -o /dev/null -w "%{http_code}" -H "Cache-Control: no-cache" \
  https://cdn1.edgecut.co/assets/app.fb12a3.css
# Expected: 200 (not 304 or HIT)
```

- [ ] CDN purge triggered after deploy
- [ ] Cache-busted asset URLs confirmed (`app.${hash}.css`)
- [ ] Stale CDN node check: `curl -H "Fastly-Debug:1"` returns correct version

---

## 7. DNS Propagation Check

### 7.1 DNS Records

| Record    | Name                          | Value                        | TTL   |
|-----------|-------------------------------|------------------------------|-------|
| A         | edgecut.co                    | 203.0.113.10 (production LB) | 60    |
| AAAA      | edgecut.co                    | 2001:db8::10                 | 60    |
| CNAME     | www.edgecut.co                | edgecut.co                   | 60    |
| CNAME     | cdn1.edgecut.co               | dualstack.cdn1.fastly.net    | 300   |
| CNAME     | cdn2.edgecut.co               | dualstack.cdn2.fastly.net    | 300   |
| CNAME     | api.edgecut.co                | edgecut.co                   | 60    |
| TXT       | _stripe.edgecut.co            | stripe-verification=...      | 3600  |
| TXT       | _dmarc.edgecut.co             | v=DMARC1; p=quarantine       | 3600  |
| CNAME     | _domainkey.edgecut.co         | dkim.edgecut.co              | 3600  |

### 7.2 Propagation Verification

```bash
# Check DNS across global resolvers
dig +short edgecut.co @1.1.1.1
dig +short edgecut.co @8.8.8.8
dig +short edgecut.co @9.9.9.9

# Check CDN CNAME resolution
dig +short cdn1.edgecut.co

# Verify DKIM + SPF
dig +short _domainkey.edgecut.co TXT
dig +short edgecut.co TXT | grep "v=spf1"

# Propagation checker (external)
curl "https://dnschecker.org/#A/edgecut.co"
```

- [ ] TTL lowered to 60 s, 24 h before deploy
- [ ] All global resolvers return same IP
- [ ] Stripe DNS verification record resolves
- [ ] SSL/TLS certificate issued (LetsEncrypt or ACME)
- [ ] `curl -I https://edgecut.co` returns 200 with correct certificate

---

## 8. Monitoring Dashboard Validation

### 8.1 Pre-Deploy Baseline

Capture screenshots of every dashboard panel before deploy for comparison.

| Dashboard                 | Panels to Check                        |
|---------------------------|----------------------------------------|
| Edgecut Overview          | Request rate, P50/P95/P99 latency, 5xx rate |
| Booking Funnel            | Page views → Barber select → Pay → Confirmed conversion |
| Payment Pipeline          | Stripe intent created → succeeded → failed rate |
| Database                 | Connection count, active queries, replication lag |
| CDN                      | Cache hit ratio, origin load, bandwidth |
| Error Tracking (Sentry)   | Error rate, top 5 errors, unhandled rejections |

### 8.2 Post-Deploy Validation

```json
{
  "checks": [
    {"name": "p95_latency", "metric": "http.server.request.duration", "op": "lt", "threshold": 500},
    {"name": "error_rate", "metric": "http.server.errors", "op": "lt", "threshold": 0.01},
    {"name": "booking_success_rate", "metric": "booking.funnel.confirmed", "op": "gt", "threshold": 0.85},
    {"name": "db_connections", "metric": "pg.connections.active", "op": "lt", "threshold": 20}
  ]
}
```

- [ ] All dashboard panels show expected data within baseline ± 10 %
- [ ] No new error types in Sentry
- [ ] DB connection count steady (no leak)
- [ ] CDN cache hit ratio > 85 %
- [ ] Alert silence window configured for deploy noise (15 min)

---

## 9. Post-Deploy Verification

### 9.1 Smoke Tests

```bash
# Run smoke test suite against production
npm run test:smoke -- --url https://edgecut.co

# Expected output:
# ✓ GET /health → 200 (0.12s)
# ✓ GET /brooklyn-ny → 200 (0.34s)
# ✓ GET /madrid-es → 200 (0.31s)
# ✓ GET /los-angeles-ca/map → 200 (0.42s)
# ✓ POST /api/bookings (valid) → 201 (0.89s)
# ✓ POST /api/bookings (double) → 409 (0.45s)
# ✓ GET /api/slots/brooklyn-ny → 200 (0.28s)
# ✓ Stripe webhook ping → 200 (0.11s)
# ✓ CDN asset → 200 (HIT) (0.02s)
```

### 9.2 Manual Verification

- [ ] Homepage loads for each tenant (Brooklyn, LA, Madrid)
- [ ] Booking flow completes end-to-end (use Stripe test card: `4242 4242 4242 4242`)
- [ ] Admin dashboard shows correct metrics for all 3 tenants
- [ ] Calendar navigation works (prev/next week)
- [ ] Map+list view loads and tiles render
- [ ] Mobile shell renders correctly at 375×667 viewport
- [ ] Language toggle (en-US / es-ES) switches content
- [ ] EUR pricing shows `45,50 €` format in Madrid tenant
- [ ] iCal export generates valid `.ics` file
- [ ] Screen reader announces page landmarks correctly

### 9.3 Feature Flag Validation

```bash
# Enable booking-v2 for 10 % Brooklyn users
export FEATURE_BOOKING_V2_RULE="tenant_slug in ['brooklyn-ny'] AND user_id % 100 < 10"
curl -X POST https://edgecut.co/admin/flags/booking-v2 \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -d "{\"rule\": \"$FEATURE_BOOKING_V2_RULE\"}"

# Verify flag evaluation in logs
grep "booking-v2" /var/log/edgecut/feature-flags.log | tail -5
```

- [ ] All flags evaluated correctly per tenant context
- [ ] Kill switch works: `export FEATURE_BOOKING_V2=false` disables immediately

### 9.4 Log & Trace Verification

- [ ] Structured logs flowing to log aggregation (Datadog / Grafana Loki)
- [ ] Trace IDs present in all request-response cycles
- [ ] No `[WARN]` or `[ERROR]` level logs above baseline
- [ ] Stripe webhook processing logged with idempotency key

### 9.5 Communication

- [ ] Deploy announced in #releases with version + changelog
- [ ] Monitoring rotation notified
- [ ] Status page updated (if applicable)
- [ ] Deploy tag pushed to repository: `git tag vX.Y.Z && git push --tags`

---

## 10. Final Sign-Off

| Role            | Name | Signed Off | Date       |
|-----------------|------|------------|------------|
| Engineering     |      | ☐          |            |
| Product         |      | ☐          |            |
| QA              |      | ☐          |            |
| SRE / Ops       |      | ☐          |            |
| Security        |      | ☐          |            |

---

## Appendix A: Rollback Quick Reference

```bash
# Revert deployment
kubectl rollout undo deployment/edgecut-web -n production

# Revert DB (contract phase only)
psql $DATABASE_URL -f migrations/003_rollback_contract.sql

# Disable all new feature flags
kubectl set env deployment/edgecut-web FEATURE_BOOKING_V2=false FEATURE_CDN_FALLBACK_V2=false

# Verify health
curl -f https://edgecut.co/health && echo "HEALTHY"
```

## Appendix B: Timing

| Phase                     | Expected Duration | Window                |
|---------------------------|-------------------|-----------------------|
| Pre-deploy checks         | 30 min            | Anytime               |
| DB migration (expand)     | 5 min             | 02:00–04:00 UTC       |
| Application deploy        | 10 min            | 02:00–04:00 UTC       |
| Smoke tests               | 5 min             | Immediately after     |
| Canary observation        | 30 min            | 02:00–05:00 UTC       |
| Full rollout              | 10 min            | After canary OK       |
| Post-deploy validation    | 15 min            | After full rollout    |
| DB migration (contract)   | 5 min             | 1 week later          |
