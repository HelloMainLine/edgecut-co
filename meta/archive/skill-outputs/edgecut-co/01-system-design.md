# 01 — System Design: Edgecut & Co.

**Barbershop marketplace chain** — 3 tenants (Brooklyn, Los Angeles, Madrid), multi-currency, multi-timezone, multi-language.

> This document is the authoritative architecture reference. All downstream artifacts (schema, API, deploy checklist, runbook) derive from this design.

---

## Table of Contents

1. [Context & Scope](#1-context--scope)
2. [Service Boundaries](#2-service-boundaries)
3. [Multi-Tenant Isolation Strategy](#3-multi-tenant-isolation-strategy)
4. [Slot Booking Atomicity](#4-slot-booking-atomicity)
5. [Stripe Connect Express Flow](#5-stripe-connect-express-flow)
6. [Webhook Idempotency Ledger](#6-webhook-idempotency-ledger)
7. [Payment & Proration Math](#7-payment--proration-math)
8. [Caching Layers](#8-caching-layers)
9. [Data Flow Diagrams](#9-data-flow-diagrams)
10. [Failure Modes & Degradation Paths](#10-failure-modes--degradation-paths)
11. [Cross-Cutting Concerns](#11-cross-cutting-concerns)

---

## 1. Context & Scope

### 1.1 What we're building

A multi-tenant barbershop booking marketplace with:
- **3 locations**: Brooklyn (Bedford-Stuy), Los Angeles (Silver Lake), Madrid (Malasaña)
- **~60% mobile** traffic, 30% repeat clients
- **$35–$95/service**, deposits required for cuts >$50 or parties >3 people
- **7-day re-cut guarantee**, verified reviews, barber micro-portfolios
- **PWA-first customer experience** with responsive web, no native app

### 1.2 Key numbers

| Metric | Value | Source |
|--------|-------|--------|
| Tenants | 3 (grows to ~10 in year 2) | Business plan |
| Barbers per tenant | 6–20 | Staffing model |
| Bookings per tenant/day | 40–80 | Industry avg for 6 barbers |
| Deposit hold period | 4 hours before auto-release | Cancellation policy |
| Slot search peak | 3 concurrent clicks on same slot | Adversarial test |
| Cache TTL (slot grid) | 15 seconds | Realtime freshness SLA |
| Webhook arrival envelope | Idempotency-Key: stripe_event_id | Stripe API doc |
| EUR/USD rate update | Daily (stale rate acceptable ±2%) | Non-trading currency |

### 1.3 Tenant properties

| Property | Brooklyn | Los Angeles | Madrid |
|----------|----------|-------------|--------|
| Tenant ID | `brooklyn` | `la` | `madrid` |
| Currency | USD | USD | EUR |
| Locale | en-US | en-US | es-ES |
| Timezone | America/New_York | America/Los_Angeles | Europe/Madrid |
| Language | English, Spanish | English, Spanish | Spanish (primary), English |
| Compliance | CCPA | CCPA | GDPR |
| Address | Bedford-Stuy, NY | Silver Lake, CA | Malasaña, Madrid |
| Price range | $35–$95 | $35–$95 | €35–€95 |

---

## 2. Service Boundaries

### 2.1 Service topology

```
┌──────────────────────────────────────────────────────────────┐
│                        CDN (Vercel Edge)                      │
│  Static assets: HTML, CSS, JS, images, fonts                │
│  Edge cache: slot-grid responses (15s TTL)                  │
│  Geo routing: map closest tenant by IP (optional)           │
└──────────────────────┬───────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────┐
│                    API Gateway (Next.js)                       │
│  Auth: JWT verification, tenant_id claim extraction          │
│  Rate limit: per (tenant_id, endpoint) token bucket          │
│  Versioning: /v1/ prefix                                    │
│  Idempotency: Idempotency-Key header → Redis check + write  │
└──┬───────────┬───────────┬───────────┬───────────┬───────────┘
   │           │           │           │           │
   ▼           ▼           ▼           ▼           ▼
┌─────┐  ┌─────────┐  ┌────────┐  ┌──────┐  ┌──────────┐
│Auth │  │ Booking │  │Catalog │  │Biz   │  │ Super-   │
│Svc  │  │ Svc     │  │Svc     │  │Ops   │  │ Admin    │
│     │  │         │  │        │  │Svc   │  │ Svc      │
│JWT  │  │Slot gen │  │Barbers │  │KPI   │  │Impersonate│
│verify│  │Reserve  │  │Services│  │agg   │  │Audit log │
│SAML │  │Checkout │  │Reviews │  │CSV   │  │Plan mgmt  │
└──┬───┘  └────┬────┘  └───┬────┘  └──┬───┘  └─────┬─────┘
   │           │           │         │             │
   └───────────┴───────────┴─────────┴─────────────┘
                       │
              ┌────────▼─────────┐
              │  Shared Postgres  │
              │  (RLS per tenant) │
              └────────┬─────────┘
                       │
              ┌────────▼─────────┐
              │  Redis (cache +   │
              │  job queue)       │
              └──────────────────┘
```

### 2.2 Service descriptions

#### 2.2.1 Auth Service
- **Responsibility**: User authentication, JWT issuance, tenant selection
- **Owns**: `users`, `tenant_members` tables
- **Contracts**: Issues JWT with `{ sub, tenantId, role }` claims
- **Degradation**: Read-only mode during DB replica lag (can't switch tenant)
- **Tenant isolation**: Tenant ID comes from JWT claim, never from URL or body

#### 2.2.2 Booking Service
- **Responsibility**: Slot generation, reservation, checkout, cancellation
- **Owns**: `slots`, `appointments`, `payments`, `webhook_ledger` tables
- **Contracts**: 
  - `GET /v1/slots?barber_id=&date=` — generate available slots
  - `POST /v1/book` — atomically reserve slot (Idempotency-Key required)
  - `POST /v1/checkout` — create Stripe PaymentIntent for deposit
  - `POST /v1/cancel` — cancel booking, release deposit per policy
- **Critical behavior**: Slot atomicity via EXCLUDE constraint. This is the service that cannot tolerate double-booking.
- **Degradation**: Cache stale slot grid → serve from cache with "may be outdated" banner. Block bookings entirely if Postgres is degraded.

#### 2.2.3 Catalog Service
- **Responsibility**: Barber profiles, service listings, reviews
- **Owns**: `barbers`, `services`, `reviews`, `service_categories`, `barber_portfolio` tables (read-heavy)
- **Contracts**:
  - `GET /v1/barbers` — search/filter barbers
  - `GET /v1/barbers/:id` — barber profile with portfolio
  - `GET /v1/services` — service catalog per tenant
  - `GET /v1/reviews` — reviews with verified-purchase badges
- **Caching**: Read-replica Postgres or Redis cache with 60s TTL for barber grids. CDN cache for static profile assets (portfolio images).

#### 2.2.4 Biz Ops Service
- **Responsibility**: Provider dashboards, CRM, calendar management
- **Owns**: Aggregation queries over `appointments`, `payments`, `reviews` tables
- **Contracts**:
  - `GET /v1/biz/kpis` — today's revenue, bookings, no-shows, NPS
  - `GET /v1/biz/clients` — client CRM with LTV, last visit
  - `POST /v1/biz/availability` — manage recurring rules + time-off
- **Caching**: Materialized views refreshed every 15 minutes for dashboard KPIs. Real-time counts from Redis counters.

#### 2.2.5 Super-Admin Service
- **Responsibility**: Multi-tenant management, impersonation, billing, audit log
- **Owns**: `tenants`, `audit_log`, `tenant_plans` tables
- **Contracts**:
  - `GET /v1/admin/tenants` — list all tenants with plan info
  - `POST /v1/admin/impersonate` — switch view to target tenant (writes audit_log)
  - `GET /v1/admin/audit-log` — filtered audit log
  - `POST /v1/admin/plans` — change tenant plan
- **Critical behavior**: Every impersonation MUST write an audit log row with `{ admin_user_id, target_tenant_id, action: 'impersonate', timestamp, ip_address }`. Never silently bypass RLS.

### 2.3 Service communication patterns

| Pattern | Where | Why |
|---------|-------|-----|
| **Synchronous REST** | Client → API Gateway → Service | User-facing requests need immediate response |
| **Database-level atomicity** | Booking Service → Postgres | EXCLUDE constraint for double-booking prevention |
| **Webhook (async)** | Stripe → Booking Service | Payment confirmation arrives asynchronously |
| **Redis pub/sub** | Slot reservation → stale cache invalidation | Near-real-time invalidation of cached slot grids |
| **Cron job** | Stale hold release, win-back triggers | Regular maintenance tasks |

---

## 3. Multi-Tenant Isolation Strategy

### 3.1 Model: Shared database, RLS-enforced isolation

**Chosen model**: Shared PostgreSQL database with `tenant_id` column on every tenant-scoped table, `ROW LEVEL SECURITY` enabled and forced.

**Rationale**: 3 tenants today, ~10 in year 2. Schema is identical across tenants. No per-tenant compliance requirement that mandates database-level separation. RLS gives us defense-in-depth against cross-tenant data leaks.

### 3.2 Every tenant-scoped table

All tables except `tenants`, `users`, `tenant_members`, and global reference tables carry a `tenant_id` column:

| Table | Tenant-scoped? | Notes |
|-------|---------------|-------|
| `tenants` | — | Global. Parent table. |
| `users` | — | Global. Cross-tenant login via `tenant_members`. |
| `tenant_members` | tenant_id | Maps users to tenants. |
| `barbers` | Yes | Each barber belongs to exactly one tenant. |
| `services` | Yes | Per-tenant service catalog. |
| `slots` | Yes | Tenant-scoped for RLS. |
| `appointments` | Yes | Tenant-scoped for RLS. |
| `payments` | Yes | Tenant-scoped for RLS. |
| `reviews` | Yes | Tenant-scoped for RLS. |
| `schedule_rules` | Yes | Tenant-scoped for RLS. |
| `schedule_exceptions` | Yes | Tenant-scoped for RLS. |
| `audit_log` | Yes | Tenant-scoped + global admin entries. |
| `webhook_ledger` | Yes | Tenant-scoped for RLS. |

### 3.3 RLS policy pattern

```sql
-- Every table follows this pattern
ALTER TABLE barbers ENABLE ROW LEVEL SECURITY;
ALTER TABLE barbers FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON barbers
  USING (tenant_id = current_setting('app.tenant_id')::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
```

**Critically**: `FORCE ROW LEVEL SECURITY` ensures even the table owner (application user) cannot bypass RLS. This is non-negotiable.

### 3.4 Session variable injection

Every API request does:

```typescript
// Middleware: runs after JWT verification
const tenantId = claims.tenantId; // from JWT, NEVER from URL or body
await db.query("SELECT set_config('app.tenant_id', $1, true)", [tenantId]);
// true = session-local, auto-cleaned when connection returns to pool
```

This ensures every subsequent query on that connection is implicitly tenant-scoped regardless of whether the developer remembered to add `WHERE tenant_id = ?`.

### 3.5 Tenant switching (multi-tenant user)

A user who belongs to multiple tenants (e.g., a barber who works at both Brooklyn and LA, or a super-admin) switches via:

```typescript
POST /api/session/switch-tenant { targetTenantId: "la" }
// 1. Verify membership: SELECT 1 FROM tenant_members WHERE user_id = ? AND tenant_id = ?
// 2. Re-issue JWT with new tenantId claim
// 3. Client stores new token, reloads page
```

### 3.6 Cross-tenant queries (admin only)

```sql
-- Dedicated role with BYPASSRLS, locked behind SSO
CREATE ROLE super_admin BYPASSRLS;

-- Every cross-tenant query is audit-logged
INSERT INTO audit_log (admin_id, action, target_tenant_id, query_detail)
VALUES ($1, 'cross-tenant-query', $2, $3);
```

**Rule**: Never use `BYPASSRLS` from the main application pool. Super-admin uses a completely separate connection pool with its own credentials.

### 3.7 Cross-tenant attack prevention

| Attack vector | Mitigation |
|--------------|------------|
| URL parameter injection (`?tenantId=la` while logged into Brooklyn) | Tenant ID from JWT claim, not URL. Backend ignores URL param. |
| API body tampering (`{ tenant_id: "la" }`) | Backend always overrides with JWT `tenantId`. |
| API header tampering (`X-Tenant-Id: la`) | Headers are ignored. Tenant ID from JWT only. |
| Connection pool reuse (pgBouncer transaction mode + Prisma) | `SET LOCAL app.tenant_id = ...` on every request, not per-pool. |
| Direct DB query via migration tool | Migration runs as table owner, RLS would NOT apply — but migrations never touch tenant data directly. |

### 3.8 Tenant-specific overrides

Tokens in `DESIGN.md` and `tokens.css` use `[data-tenant="madrid"]` selectors for:

- Currency symbol (USD vs EUR)
- Locale formatting (Intl.NumberFormat with es-ES vs en-US)
- GDPR cookie banner (madrid only)
- Language toggle position and content
- Timezone label formatting

---

## 4. Slot Booking Atomicity

### 4.1 The core problem

When two customers click the same 3:00 PM slot for the same barber within milliseconds, both must not succeed. Application-level checks ("SELECT count(*) WHERE slot = X AND state = 'available'") lose the race on every concurrent access.

### 4.2 Solution: EXCLUDE constraint with GiST index

```sql
CREATE TABLE appointments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id),
  barber_id   uuid NOT NULL REFERENCES barbers(id),
  customer_id uuid NOT NULL REFERENCES users(id),
  service_id  uuid NOT NULL REFERENCES services(id),
  starts_at   timestamptz NOT NULL,
  ends_at     timestamptz NOT NULL,
  state       text NOT NULL DEFAULT 'held'
    CHECK (state IN ('held','booked','confirmed','checked-in','completed',
                     'no-show','cancelled-by-client','cancelled-by-provider')),

  -- The atomicity constraint:
  EXCLUDE USING gist (
    barber_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  ) WHERE (state NOT IN ('cancelled-by-client','cancelled-by-provider','no-show'))
);
```

**How it works**:
- `EXCLUDE USING gist` creates a GiST index that checks for overlapping ranges
- `barber_id WITH =` — only conflicts for the same barber
- `tstzrange(starts_at, ends_at, '[)') WITH &&` — ranges that overlap in time
- `WHERE (state NOT IN (...))` — cancelled/no-show appointments don't block rebooking that slot
- When a conflicting row is inserted, Postgres throws `SQLSTATE 23P01` (exclusion_violation)

### 4.3 Application-level handling

```typescript
async function reserveSlot(barberId, startsAt, durationMin, customerId, serviceId, tenantId) {
  try {
    const result = await db.query(`
      INSERT INTO appointments (tenant_id, barber_id, customer_id, service_id,
                                starts_at, ends_at, state)
      VALUES ($1, $2, $3, $4, $5, $5 + interval '1 minute' * $6, 'held')
      RETURNING id
    `, [tenantId, barberId, customerId, serviceId, startsAt, durationMin]);

    return { ok: true, appointmentId: result.rows[0].id };
  } catch (e) {
    if (e.code === '23P01') { // exclusion_violation
      return { ok: false, reason: 'slot-taken' };
    }
    throw e;
  }
}
```

### 4.4 Optimistic UI in the frontend

- **Within 1 frame** of clicking: `aria-pressed="true"` on the slot button, slot visually removed from grid
- **On server response**:
  - Success: gray out permanently, transition to checkout
  - Failure ("slot-taken"): show inline toast "Slot just got taken — here's the updated grid", re-fetch slots, replace grid
- **Race condition handling**: The optimistic UI means two users clicking the same slot both see it "taken" visually. The loser gets the toast. The winner proceeds.

### 4.5 Slot hold TTL

- Held appointments have a TTL of **7 minutes**
- A cron job runs every minute: `UPDATE appointments SET state = 'cancelled-by-system' WHERE state = 'held' AND held_until < NOW()`
- The `held_until` column is set at insert time: `NOW() + interval '7 minutes'`
- If the customer completes checkout within the hold window, `state` transitions from `held` → `booked` on the same row
- If checkout fails or times out, the cron releases the slot

### 4.6 Caching slot grids

- Slot grid response is cached in Redis with **15-second TTL**
- On successful reservation, the cache key for that `(barber_id, date)` is invalidated via Redis pub/sub
- If the cache is stale (no invalidation has happened), the response carries `data-realtime-state="stale"` on the badge
- The frontend polls every 15 seconds via `realtime.js`

---

## 5. Stripe Connect Express Flow

### 5.1 Two-sided marketplace payments

Edgecut & Co. uses **Stripe Connect Express** for the marketplace payment model:
- **Platform** (Edgecut) processes payments
- **Providers** (barbers) receive funds minus platform fee
- **Customers** pay via Stripe Checkout

### 5.2 Provider onboarding (Stripe Connect Express)

```
1. Barber signs up via biz-onboarding.html (Step 4: Payouts)
2. Frontend calls POST /v1/biz/create-connect-account
3. Backend creates Stripe Connect Express account:
   stripe.connectAccounts.create({ type: 'express' })
4. Backend stores the stripe_account_id on the barber's record
5. Backend generates an account onboarding link:
   stripe.accountLinks.create({
     account: stripeAccountId,
     refresh_url: `${APP_URL}/biz-onboarding?step=4&refresh=true`,
     return_url: `${APP_URL}/biz-onboarding?step=4&complete=true`,
     type: 'account_onboarding',
   })
6. Barber is redirected to Stripe to complete verification
7. Stripe redirects back to return_url on completion
8. Platform verifies: stripe.accounts.retrieve(stripeAccountId) → charges_enabled
```

### 5.3 Payment flow

```
1. Customer selects services + barber + slot → POST /v1/checkout
2. Backend calculates:
   - Total service price (in tenant currency)
   - Deposit amount (if applicable: >$50 or party >3 people)
   - Platform fee (e.g., 5% of total)
3. Backend creates Stripe PaymentIntent:
   stripe.paymentIntents.create({
     amount: depositAmountCents,     // or total for deposit-exempt
     currency: tenantCurrency,       // usd or eur
     application_fee_amount: feeCents,
     transfer_data: {
       destination: barberStripeAccountId,
     },
     metadata: {
       appointment_id: appointmentId,
       tenant_id: tenantId,
     },
   })
4. Customer completes payment via Stripe Checkout
5. Stripe sends checkout.session.completed webhook → Booking Service
6. On webhook receipt (with idempotency check):
   - Appointment state set to 'booked'
   - Payment record created in payments table
   - Confirmation email triggered (via async job queue)
```

### 5.4 Deposit handling

| Scenario | Deposit | Notes |
|----------|---------|-------|
| Booking ≤ $50, party ≤ 3 | $0 (no deposit) | Full payment at service |
| Booking > $50 | 25% of total, min $15 | Held, applied to final |
| Party booking > 3 | $50/person deposit | Held, forfeit on cancellation inside 4hrs |
| Recurring first visit | Full booking price | Then shifts to per-session |

### 5.5 Cancellation & refund

```
1. Customer requests cancel via POST /v1/cancel
2. Backend checks cancellation policy:
   - If cancelled > 4 hours before slot: free cancellation, no charge
   - If cancelled ≤ 4 hours before slot: deposit forfeit
3. If forfeit: stripe.paymentIntents.capture (if uncaptured) or charge
4. If not forfeit: stripe.paymentIntents.cancel (uncaptured) or refund
5. Appointment state → 'cancelled-by-client'
```

---

## 6. Webhook Idempotency Ledger

### 6.1 The problem

Stripe webhooks are at-least-once delivery. The same `checkout.session.completed` event can arrive twice (or more). Processing it twice would:
- Double-credit the payment
- Send two confirmation emails
- Create duplicate ledger entries

### 6.2 Solution: webhook LEDGER table with UNIQUE constraint

```sql
CREATE TABLE webhook_ledger (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id),
  provider    text NOT NULL,        -- 'stripe'
  event_id    text NOT NULL,        -- Stripe event ID (evt_xxx)
  event_type  text NOT NULL,        -- 'checkout.session.completed'
  status      text NOT NULL DEFAULT 'processing',
  created_at  timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,

  UNIQUE (provider, event_id)       -- idempotency key
);
```

### 6.3 Processing flow

```
1. Webhook POST arrives at /api/webhooks/stripe
2. Backend verifies signature: stripe.webhooks.constructEvent(rawBody, sig, secret)
3. Extract event_id from verified payload
4. INSERT INTO webhook_ledger (provider, event_id, event_type, status)
   VALUES ('stripe', event_id, event_type, 'processing')
5. If this INSERT fails with unique_violation, return 200 OK immediately
   → This is the second arrival. We already processed it. Silent ack.
6. If INSERT succeeds:
   a. Extract payment data from event payload
   b. Transactionally:
      - INSERT INTO payments (...)
      - UPDATE appointments SET state = 'booked' WHERE id = ?
      - UPDATE webhook_ledger SET status = 'completed', processed_at = now()
   c. Enqueue confirmation email job
7. Return 200 OK to Stripe
```

**Why this works**: The `UNIQUE (provider, event_id)` constraint prevents duplicate processing at the database level. The second arrival's INSERT fails, and we short-circuit to 200 OK. No application-level state checking needed.

### 6.4 Stripe webhook signature verification

```typescript
import Stripe from 'stripe';
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

// In the webhook handler:
const sig = req.headers['stripe-signature'];
let event: Stripe.Event;
try {
  event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET);
} catch (e) {
  return res.status(400).json({ error: 'Invalid signature' });
}

const eventId = event.id; // evt_xxx — used as idempotency key
```

### 6.5 Provider-specific ledger

Each webhook provider gets its own provider slug in the ledger:

| Provider | Slug | ID format |
|----------|------|-----------|
| Stripe | `stripe` | `evt_xxx` |
| Twilio (SMS) | `twilio` | `SMxxx` |
| Resend (email) | `resend` | `re_xxx` |

---

## 7. Payment & Proration Math

### 7.1 Deposit math

```typescript
function calculateDeposit(services: Service[], partySize: number): number {
  const total = services.reduce((sum, s) => sum + s.priceCents, 0);
  const isParty = partySize > 3;
  const isExpensive = total > 5000; // > $50 in cents

  if (isParty) {
    return partySize * 5000; // $50/person deposit in cents
  }

  if (isExpensive) {
    const deposit = Math.round(total * 0.25); // 25%
    return Math.max(deposit, 1500); // min $15
  }

  return 0; // no deposit
}
```

### 7.2 Platform fee math

```typescript
// Platform takes 5% of total booking value
const platformFee = Math.round(totalServiceCents * 0.05);

// Stripe Connect: platform fee is deducted from the transfer to the barber
// PaymentIntent includes application_fee_amount
```

### 7.3 Stripe PaymentIntent construction

```typescript
const paymentIntent = await stripe.paymentIntents.create({
  amount: depositCents,             // or total if no deposit
  currency: tenantCurrency,         // 'usd' or 'eur'
  automatic_payment_methods: { enabled: true },
  application_fee_amount: platformFeeCents,
  transfer_data: {
    destination: barber.stripeAccountId,
  },
  metadata: {
    appointment_id: appointment.id,
    tenant_id: tenantId,
    barber_id: barber.id,
    customer_id: customer.id,
  },
});
```

### 7.4 Multi-currency handling

- **USD tenants** (Brooklyn, LA): amounts in cents (Stripe native), Intl.NumberFormat('en-US', { currency: 'USD' })
- **EUR tenant** (Madrid): amounts in cents (Stripe supports EUR), Intl.NumberFormat('es-ES', { currency: 'EUR' })
  - European formatting: €85,00 (comma decimal, period grouping)
- **Exchange rate**: Not real-time. Daily fetched rate, displayed as informational. Deposit held in tenant's native currency.

### 7.5 Proration for plan upgrades (super-admin billing)

```
If tenant upgrades mid-cycle:
  1. Compute remaining days in the billing period
  2. Credit: unused portion of current plan
  3. Charge: prorated portion of new plan
  4. Net: charge - credit = invoice amount

  Example:
    15 days remaining in 30-day cycle
    Current: $29/mo → remaining value: $14.50
    New: $99/mo → remaining charge: $49.50
    Customer invoice: $49.50 - $14.50 = $35.00 immediately
    Next cycle: $99 full charge
```

---

## 8. Caching Layers

### 8.1 Cache topology

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  CDN Cache   │     │  Redis Cache │     │  App-level   │
│  (Vercel     │     │  (Slot grid, │     │  (In-memory) │
│   Edge)      │     │   KPI agg)   │     │   Session)   │
│              │     │              │     │              │
│  TTL: 15s    │     │  TTL: 15s-5m │     │  TTL: request│
│  Static: 1h  │     │              │     │  scoped      │
└──────────────┘     └──────────────┘     └──────────────┘
```

### 8.2 Cache by data type

| Data | Layer | TTL | Invalidation |
|------|-------|-----|-------------|
| Slot grid (barber, date) | Redis | 15s | On reservation or 15s TTL |
| Barber profiles | Redis | 60s | On profile update |
| Service catalog | Redis | 5min | On service update |
| Static HTML/CSS/JS | CDN | 1h (versioned) | Deploy |
| Portfolio images | CDN | 7d (hash-named) | Never (immutable) |
| KPI aggregates | Redis/MV | 15min | On-demand refresh |
| Client CRM list | None | — | Always fresh (low volume) |
| Available now badges | Redis | 15s | Polled via realtime.js |

### 8.3 Redis key naming

```
slot-grid:{tenant_id}:{barber_id}:{date_iso}
barber:{tenant_id}:{barber_id}
services:{tenant_id}
kpis:{tenant_id}:{barber_id}:{date_iso}
available-now:{tenant_id}
```

### 8.4 Cache degradation policy

| Failure mode | Behavior |
|-------------|----------|
| Redis unavailable | Serve stale slot grid with "Reconnecting — data may be stale" banner. KPI panels: show nothing with "Data unavailable" chip. |
| CDN miss | Fall through to origin (Next.js or static file server). |
| Cache stampede on slot grid | Lock per barber_id per date: first request generates + populates cache, subsequent requests wait on cache fill. |

---

## 9. Data Flow Diagrams

### 9.1 Booking flow (happy path)

```
Customer                    Edgecut Platform               Stripe
   │                             │                            │
   │  ─── search barbers ──────▶ │                            │
   │  ◀── barber list ─────────  │                            │
   │                             │                            │
   │  ─── view barber profile ▶  │                            │
   │  ◀── profile + services ──  │                            │
   │                             │                            │
   │  ─── GET slots (b, d) ───▶  │                            │
   │       ◀── slot grid ──────  │                            │
   │                             │                            │
   │  ─── POST /book ──────────▶ │                            │
   │       (Idempotency-Key)     │                            │
   │       INSERT appointment    │                            │
   │       check: EXCLUDE OK     │                            │
   │  ◀── { appointmentId } ──   │                            │
   │                             │                            │
   │  ─── POST /checkout ───────▶│                            │
   │       create PaymentIntent  │ ──── create PI ──────────▶ │
   │                             │ ◀── PI id ───────────────  │
   │  ◀── { clientSecret } ──    │                            │
   │                             │                            │
   │  ─── Stripe Checkout ────── │ ────────────────────────▶  │
   │                             │                            │
   │                             │ ◀── webhook (completed) ─  │
   │                             │     verify + idempotency   │
   │                             │     INSERT payment +       │
   │                             │     appointment→'booked'   │
   │                             │                            │
   │  ─── redirect to conf ────  │                            │
   │  ◀── confirmation page ──   │                            │
```

### 9.2 Booking flow (slot race — loser)

```
Customer A                     Customer B                   Platform
   │                              │                            │
   │──click slot──▶               │                            │
   │                              │──click slot──▶             │
   │                              │                            │
   │Optimistic: aria-pressed      │Optimistic: aria-pressed    │
   │                              │                            │
   │──POST /book─────────────────▶│                            │
   │                              │──POST /book──────────────▶ │
   │                              │                            │
   │INSERT succeeds               │INSERT fails(23P01)         │
   │◀──{ ok: true }──────────────│                            │
   │                              │◀──{ slot-taken }────────── │
   │                              │                            │
   │                              │Inline toast appears        │
   │                              │Grid refreshes (slot gone)  │
   │                              │                            │
```

### 9.3 Webhook idempotency flow

```
Stripe                              Platform
  │                                    │
  │── POST /webhooks/stripe ──────────▶│
  │   event: checkout.session.completed│
  │   event_id: evt_123               │
  │                                    │
  │   INSERT webhook_ledger            │
  │   (provider='stripe',              │
  │    event_id='evt_123')             │
  │   → OK (new)                       │
  │                                    │
  │   Process payment                  │
  │   ↔ Transactional DB writes        │
  │                                    │
  │◀── 200 OK ─────────────────────────│
  │                                    │
  │── POST /webhooks/stripe (retry) ──▶│
  │   event: checkout.session.completed│
  │   event_id: evt_123 (same!)       │
  │                                    │
  │   INSERT webhook_ledger            │
  │   → UNIQUE violation (duplicate)   │
  │                                    │
  │◀── 200 OK ───(silent ack)─────────│
  │   (no processing, just ack)        │
```

### 9.4 Multi-tenant request flow

```
Browser                         API Gateway                    Postgres
  │                                 │                             │
  │── JWT(tenantId: "brooklyn") ──▶│                             │
  │   GET /v1/barbers             │                             │
  │                                 │                             │
  │   Verify JWT → tenantId        │                             │
  │   SET LOCAL app.tenant_id      │                             │
  │   = brooklyn's uuid            │                             │
  │                                 │                             │
  │                                 │── SELECT * FROM barbers ──▶│
  │                                 │   (RLS filters brooklyn)   │
  │                                 │◀── (6 barbers) ───────────  │
  │                                 │                             │
  │   RESULT: 6 barbers            │                             │
  │◀── JSON response ──────────────│                             │
```

### 9.5 Super-admin impersonation + audit log

```
Admin Browser                  Super-Admin Service           Postgres
  │                                 │                          │
  │── POST /v1/admin/impersonate ──▶│                         │
  │   target: "la"                  │                          │
  │                                 │                          │
  │   INSERT audit_log              │                          │
  │   (admin: tyler@edgecut,        │── INSERT audit_log ────▶│
  │    action: 'impersonate',      │                          │
  │    target: 'la')               │                          │
  │                                 │                          │
  │   Issue new JWT (la scope)      │                          │
  │                                 │                          │
  │◀── { jwt, redirect: '/la/...' }│                          │
```

---

## 10. Failure Modes & Degradation Paths

### 10.1 Payment provider down (Stripe API unavailable)

| Detection | 5xx from Stripe API, webhook timeout |
|-----------|--------------------------------------|
| Severity | Critical — no bookings can complete |
| Mitigation | Block new bookings with "Payment is temporarily unavailable — please try again in a few minutes" |
| Recovery | Once Stripe is reachable, process any queued payments |
| Comms | Status page update, internal Slack to ops |
| Rollback | Feature flag: `payments.enabled` = false in Redis, UI reads flag |

### 10.2 Slot double-booked (EXCLUDE race — should be impossible)

| Detection | Application monitoring: `SELECT count(*) WHERE slot collisions > 0` |
|-----------|--------------------------------------------------------------------|
| Severity | Critical — data integrity violation |
| Mitigation | Last customer to check out gets the slot. Earlier held → cancelled-by-system. Customer notified with apology + rebook link |
| Recovery | Manual reconciliation |
| Root cause | Usually a bug in the hold-release cron or a bypass route |

### 10.3 Tenant data leak (RLS bypass)

| Detection | Monitoring query: `SELECT count(*) WHERE tenant_id != app.tenant_id` on RLS tables |
|-----------|------------------------------------------------------------------------------------|
| Severity | Emergency — regulatory notification may be required |
| Mitigation | Immediately block the connection / role that bypassed RLS. Revoke BYPASSRLS. |
| Recovery | Full audit log review. Determine scope. GDPR/CCPA notification if PII leaked. |
| Postmortem | Review why BYPASSRLS was used. Add additional CI gate. |

### 10.4 PostgreSQL degraded (slow queries, high connections)

| Detection | PgBouncer pool exhaustion, slow query log |
|-----------|------------------------------------------|
| Severity | High — cascading to all services |
| Mitigation | Serve cached slot grids. Block new bookings with read-only message. |
| Recovery | Connection pool drain, query kill, index validation |

### 10.5 Redis unavailable

| Detection | Connection refused, timeout |
|-----------|----------------------------|
| Severity | Medium — degrades UX but doesn't break bookings |
| Mitigation | All slot grids go to DB directly. Cache is cold but functional. |
| Recovery | Redis restart, cache warmup from DB |

### 10.6 Cache stampede (slot grid)

| Detection | Sudden traffic spike to a specific barber's date |
|-----------|-------------------------------------------------|
| Severity | Medium — DB CPU spike (EXCLUDE constraint also hits DB) |
| Mitigation | Lock per cache key: first request generates, subsequent wait on Redis lock |
| Prevention | Cache TTL short enough (15s) that stampede window is small |

### 10.7 CDN failure

| Detection | Static assets returning 5xx |
|-----------|---------------------------|
| Severity | High — pages load but broken (no CSS/images) |
| Mitigation | HTML includes fallback critical CSS inline in `<head>` |
| Recovery | CDN purge, origin health check |

### 10.8 Stripe webhook retry storm

| Detection | Same event_id arriving >5 times in 60s |
|-----------|--------------------------------------|
| Severity | Low — idempotency ledger absorbs all duplicates |
| Mitigation | Ledger UNIQUE constraint silently blocks replays |
| Recovery | N/A — system handles gracefully by design |

---

## 11. Cross-Cutting Concerns

### 11.1 CSP headers

```http
Content-Security-Policy: default-src 'self';
  script-src 'self' https://js.stripe.com;
  frame-src https://js.stripe.com https://hooks.stripe.com;
  connect-src 'self' https://api.stripe.com;
  style-src 'self' 'unsafe-inline';
  img-src 'self' data: https://*.stripe.com;
```

### 11.2 Graceful shutdown

Each service handles `SIGTERM`:
- Stop accepting new requests
- Wait for in-flight requests to complete (max 30s)
- Drain connection pools
- Close Redis connections
- Exit with code 0

### 11.3 Rate limiting

```
Token bucket per (tenant_id, endpoint):
  - Bucket size: 100 tokens
  - Refill rate: 10 tokens/second
  - Headers: X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset

Booking endpoints (/v1/book, /v1/checkout):
  - 5 requests per second per tenant (stricter — booking is expensive)

Catalog endpoints (/v1/barbers, /v1/services):
  - 30 requests per second per tenant
```

### 11.4 Observability

| Metric | Instrument |
|--------|-----------|
| Bookings per minute | Prometheus counter: `bookings_total{tenant_id}` |
| Slot reservation latency | Prometheus histogram: `slot_reserve_duration_ms` |
| Webhook processing latency | Prometheus histogram: `webhook_process_duration_ms` |
| RLS violation count | Prometheus counter: `rls_violation_total` (alert > 0) |
| Cache hit ratio | Prometheus counter: `cache_hit_total` / `cache_miss_total` |
| Error rate by endpoint | Prometheus counter: `http_errors_total{status, endpoint}` |

### 11.5 Feature flags

Runtime flags stored in Redis:

| Flag | Default | Purpose |
|------|---------|---------|
| `payments.enabled` | true | Emergency disable payments |
| `bookings.enabled` | true | Emergency disable new bookings |
| `maintenance_mode` | false | Show maintenance page |
| `slot_cache_enabled` | true | Toggle Redis slot caching |
| `webhook_processing_enabled` | true | Toggle Stripe webhook processing |

### 11.6 Deployment order

```
1. Schema migration (no downtime via expand-contract)
2. Backend services (rolling, 1 per node)
3. Frontend static assets (CDN purge)
4. Cron jobs (hold release, win-back)
5. Feature flags toggled on
```

---

*01-system-design.md — Edgecut & Co. Architecture Document*
*Generated: 2026-05-13*
*Skills fired: system-design, engineering-multi-tenant-saas, engineering-recurring-availability*
