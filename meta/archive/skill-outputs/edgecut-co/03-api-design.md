# 03-api-design.md — Edgecut & Co. REST API Design

**Version:** 1.0  
**Base URL:** `https://api.edgecut.co/v1` (tenant-routed via subdomain or `X-Tenant-Id` header)  
**Auth:** Bearer JWT in `Authorization` header  
**Idempotency:** `Idempotency-Key` header on POST/PATCH mutations  
**Rate limiting:** Token bucket — 1000 req/min per tenant, 100 req/s burst  
**Pagination:** Cursor-based (opaque `cursor` query param + `has_more` in response)

---

## 1. Design Decisions

### 1.1 Versioning

URL-path versioning (`/v1/`). Major version bumps require coordinated client migration. Deprecation notice via `Sunset` + `Deprecation` headers with 6-month overlap window.

### 1.2 Multi-Tenant Routing

Two modes supported — client chooses at integration time:

- **Subdomain:** `brooklyn.api.edgecut.co/v1/barbers` (auto-resolves tenant from subdomain)
- **Header:** `X-Tenant-Id: brooklyn` (for custom-domain setups)

The API gateway reads either and sets `app.tenant_id` via `SET LOCAL` for RLS enforcement.

### 1.3 Error Envelope

Every error response follows this shape:

```json
{
  "error": {
    "code": "SLOT_UNAVAILABLE",
    "message": "The requested slot is no longer available.",
    "retryable": false,
    "request_id": "req_abc123def456"
  }
}
```

**Standard error codes:**

| HTTP | Code | Retryable | Meaning |
|---|---|---|---|
| 400 | VALIDATION_ERROR | false | Request body failed validation |
| 401 | UNAUTHORIZED | false | Missing or invalid auth token |
| 403 | FORBIDDEN | false | Authenticated but not authorized |
| 404 | NOT_FOUND | false | Resource doesn't exist |
| 409 | CONFLICT | false | Resource state conflict (e.g., slot taken) |
| 409 | DUPLICATE_REQUEST | false | Idempotency-Key collision on different payload |
| 422 | UNPROCESSABLE_ENTITY | false | Semantic validation failure |
| 429 | RATE_LIMITED | true | Rate limit exceeded |
| 500 | INTERNAL_ERROR | true | Unexpected server error |
| 503 | SERVICE_UNAVAILABLE | true | Temporary outage |

### 1.4 Pagination

Cursor-based pagination with opaque cursor tokens:

**Request:**
```
GET /v1/barbers?cursor=eyJpZCI6IjEyMyIsIl9wb2ludHMiOiIifQ==&limit=20
```

**Response:**
```json
{
  "data": [...],
  "pagination": {
    "cursor": "eyJpZCI6IjEyMyIsIl9wb2ludHMiOiIifQ==",
    "has_more": true,
    "limit": 20,
    "total": 156
  }
}
```

### 1.5 Rate Limiting Headers

Every response includes:

```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 984
X-RateLimit-Reset: 1713173400
```

429 responses additionally include:

```
Retry-After: 12
```

---

## 2. Authentication & Authorization

### 2.1 Endpoints

```
POST   /v1/auth/login          # Email/password login
POST   /v1/auth/register        # Create customer account
POST   /v1/auth/oauth/{provider} # Google/Apple OAuth
POST   /v1/auth/refresh         # Refresh access token
POST   /v1/auth/logout          # Invalidate session
```

### 2.2 Token Format

JWT with claims:

```json
{
  "sub": "user_abc123",
  "tenant_id": "tenant_brooklyn",
  "role": "customer",
  "iat": 1713173000,
  "exp": 1713176600
}
```

Access token TTL: 1 hour. Refresh token TTL: 30 days.

### 2.3 Roles

| Role | Scope |
|---|---|
| `customer` | Book appointments, view own history, review |
| `barber` | Manage own availability, view own dashboard, manage own clients |
| `admin` | Tenant-level management (barbers, services, policies) |
| `super_admin` | Cross-tenant (impersonate, audit, billing) |

---

## 3. Barber Search & Discovery

### 3.1 Search Barbers

```
GET /v1/barbers
```

**Query Parameters:**

| Param | Type | Default | Description |
|---|---|---|---|
| `search` | string | — | Full-text search on name + bio |
| `location` | string | — | City or neighborhood name |
| `lat` | float | — | Latitude for geo-radius search |
| `lng` | float | — | Longitude for geo-radius search |
| `radius_km` | int | 10 | Search radius (1–100) |
| `specialty` | string | — | Filter by specialty (e.g., 'fade', 'braids') |
| `language` | string | — | Filter by spoken language ('en', 'es') |
| `min_price` | int | — | Minimum price in cents |
| `max_price` | int | — | Maximum price in cents |
| `available_now` | bool | false | Only barbers with slots in next 2 hours |
| `featured` | bool | — | Filter featured barbers |
| `sort` | enum | `relevance` | `relevance`, `distance`, `price_asc`, `price_desc`, `rating` |
| `cursor` | string | — | Pagination cursor |
| `limit` | int | 20 | Results per page (1–100) |

**Response:**

```json
{
  "data": [
    {
      "id": "bar_abc123",
      "tenant_id": "tenant_brooklyn",
      "name": "Jordan Medina",
      "slug": "jordan-medina",
      "photo_url": "https://cdn.edgecut.co/barbers/jordan-medina.jpg",
      "bio": "Specializing in fades, beard trims, and hot towel shaves...",
      "specialties": ["fade", "beard-trim", "hot-towel"],
      "languages": ["en", "es"],
      "years_experience": 8,
      "rating": 4.8,
      "review_count": 134,
      "price_range": { "min_cents": 3500, "max_cents": 7500 },
      "currency": "USD",
      "location_name": "Bedford-Stuy, Brooklyn",
      "distance_km": 2.3,
      "available_now": true,
      "realtime_state": "fresh",
      "is_featured": false
    }
  ],
  "pagination": {
    "cursor": "eyJpZCI6IjEyMyJ9",
    "has_more": true,
    "limit": 20,
    "total": 156
  }
}
```

### 3.2 Get Single Barber

```
GET /v1/barbers/{slug}
```

**Response:** Single barber object (as above) + extended fields:

```json
{
  "id": "bar_abc123",
  "name": "Jordan Medina",
  "slug": "jordan-medina",
  "bio": "...",
  "specialties": ["fade", "beard-trim", "hot-towel"],
  "languages": ["en", "es"],
  "years_experience": 8,
  "photo_url": "https://cdn.edgecut.co/barbers/jordan-medina.jpg",
  "location_name": "Bedford-Stuy, Brooklyn",
  "address": "123 Nostrand Ave, Brooklyn, NY 11216",
  "lat": 40.6872,
  "lng": -73.9419,
  "rating": 4.8,
  "review_count": 134,
  "price_range": { "min_cents": 3500, "max_cents": 7500 },
  "currency": "USD",
  "available_now": true,
  "realtime_state": "fresh",
  "is_featured": false,
  "deposit_policy_slug": "deposit-standard",
  "recut_guarantee_days": 7,
  "services": [
    {
      "id": "svc_abc",
      "name": "Classic Fade",
      "description": "Precision fade with clipper-over-comb finish",
      "duration_min": 30,
      "price_cents": 4500,
      "category": "cut",
      "currency": "USD"
    }
  ],
  "looks": [
    {
      "id": "look_abc",
      "image_url": "https://cdn.edgecut.co/looks/jordan-1.jpg",
      "title": "Summer Fade",
      "tags": ["fade", "short"]
    }
  ],
  "reviews": [
    {
      "id": "rev_abc",
      "customer_name": "Alex R.",
      "rating": 5,
      "title": "Best fade in Bed-Stuy",
      "body": "Jordan is meticulous. Been coming here for 2 years.",
      "is_verified": true,
      "created_at": "2026-05-10T14:30:00Z"
    }
  ],
  "cancellation_policy": {
    "free_cancel_hours": 4,
    "deposit_forfeit_inside_hours": 4,
    "description": "Free cancellation up to 4 hours before your appointment. Deposits are forfeited inside the 4-hour window."
  },
  "deposit_policy": {
    "requires_deposit": true,
    "deposit_cents": 2500,
    "deposit_threshold_cents": 5000,
    "party_deposit_threshold": 3,
    "description": "$25.00 deposit required for services over $50.00 or party bookings of 3+ people."
  }
}
```

### 3.3 Get Barber Availability (Slot Grid)

```
GET /v1/barbers/{slug}/slots?date=2026-05-20
```

**Query Parameters:**

| Param | Type | Default | Description |
|---|---|---|---|
| `date` | date | today | Date to fetch slots for |
| `duration_min` | int | — | Filter by service duration (filters to slots matching that block) |

**Response:**

```json
{
  "barber_id": "bar_abc123",
  "date": "2026-05-20",
  "timezone": "America/New_York",
  "timezone_label": "Times shown in ET",
  "slots": [
    {
      "starts_at": "2026-05-20T09:00:00-04:00",
      "ends_at": "2026-05-20T09:30:00-04:00",
      "is_available": true
    },
    {
      "starts_at": "2026-05-20T09:30:00-04:00",
      "ends_at": "2026-05-20T10:00:00-04:00",
      "is_available": false
    }
  ]
}
```

**Staleness handling:** If slots were generated more than 30s ago, the endpoint includes:
```json
{
  "generated_at": "2026-05-20T08:59:15Z",
  "stale": true,
  "stale_seconds": 45
}
```

---

## 4. Booking Flow

### 4.1 Hold Slot (Atomic Reserve)

```
POST /v1/bookings/hold
Idempotency-Key: ik_abc123
```

**Request:**

```json
{
  "barber_id": "bar_abc123",
  "service_id": "svc_abc",
  "starts_at": "2026-05-20T09:00:00-04:00",
  "party_size": 1,
  "notes": "First visit!"
}
```

**Response (201 Created):**

```json
{
  "appointment_id": "apt_def456",
  "state": "held",
  "held_until": "2026-05-20T09:07:00Z",
  "price_cents": 4500,
  "currency": "USD",
  "deposit_required": true,
  "deposit_cents": 2500
}
```

**Race condition (slot taken):**
```json
{
  "error": {
    "code": "SLOT_UNAVAILABLE",
    "message": "This slot was just booked by another customer. Please select a different time.",
    "retryable": true,
    "request_id": "req_abc"
  }
}
```

**Duplicate idempotency:**
```json
{
  "appointment_id": "apt_def456",
  "state": "held",
  "idempotent": true,
  "price_cents": 4500,
  "currency": "USD"
}
```

### 4.2 Create Deposit Payment Intent

```
POST /v1/payments/deposit-intent
Idempotency-Key: ik_def456
```

**Request:**

```json
{
  "appointment_id": "apt_def456"
}
```

**Response:**

```json
{
  "payment_intent_id": "pi_xyz789",
  "client_secret": "pi_xyz789_secret_abc",
  "amount_cents": 2500,
  "currency": "USD",
  "description": "$25.00 deposit hold — remaining $45.00 due at checkout"
}
```

### 4.3 Confirm Booking (After Payment)

```
POST /v1/bookings/confirm
Idempotency-Key: ik_ghi789
```

**Request:**

```json
{
  "appointment_id": "apt_def456",
  "payment_intent_id": "pi_xyz789"
}
```

**Response:**

```json
{
  "appointment_id": "apt_def456",
  "state": "booked",
  "starts_at": "2026-05-20T09:00:00-04:00",
  "barber_name": "Jordan Medina",
  "service_name": "Classic Fade",
  "total_cents": 4500,
  "deposit_cents": 2500,
  "remaining_cents": 2000,
  "currency": "USD"
}
```

### 4.4 Cancel Booking

```
POST /v1/bookings/{appointment_id}/cancel
Idempotency-Key: ik_jkl012
```

**Request:**

```json
{
  "reason": "Scheduling conflict"
}
```

**Response:**

```json
{
  "appointment_id": "apt_def456",
  "state": "cancelled-by-client",
  "refund_cents": 2500,
  "refund_status": "processing",
  "cancellation_note": "Cancelled 6 hours before — deposit refunded. Free cancellation window is 4 hours."
}
```

**Cancellation within 4 hours:**
```json
{
  "appointment_id": "apt_def456",
  "state": "cancelled-by-client",
  "refund_cents": 0,
  "refund_status": "none",
  "cancellation_note": "Cancelled 2 hours before — deposit forfeited. Cancellations inside the 4-hour window lose the deposit."
}
```

### 4.5 Get Booking History

```
GET /v1/bookings?status=upcoming&cursor=...&limit=20
```

**Query Parameters:**

| Param | Type | Default | Description |
|---|---|---|---|
| `status` | enum | `all` | `upcoming`, `past`, `cancelled`, `all` |
| `cursor` | string | — | Pagination cursor |
| `limit` | int | 20 | Results per page |

**Response:**

```json
{
  "data": [
    {
      "id": "apt_def456",
      "barber_name": "Jordan Medina",
      "barber_slug": "jordan-medina",
      "service_name": "Classic Fade",
      "starts_at": "2026-05-20T09:00:00-04:00",
      "ends_at": "2026-05-20T09:30:00-04:00",
      "state": "booked",
      "total_cents": 4500,
      "deposit_cents": 2500,
      "currency": "USD",
      "location_name": "Bedford-Stuy, Brooklyn",
      "rebook_link": "/barbers/jordan-medina"
    }
  ],
  "pagination": { "cursor": "...", "has_more": false, "limit": 20, "total": 8 }
}
```

---

## 5. Reviews

### 5.1 Create Review

```
POST /v1/reviews
Idempotency-Key: ik_mno345
```

**Request:**

```json
{
  "appointment_id": "apt_def456",
  "rating": 5,
  "title": "Best fade in Bed-Stuy",
  "body": "Jordan is incredibly precise. Been coming for 2 years."
}
```

**Response (201 Created):**

```json
{
  "id": "rev_abc",
  "is_verified": true,
  "rating": 5,
  "created_at": "2026-05-20T10:15:00Z"
}
```

Verification is automatic: `is_verified = true` iff `appointment_id` points to a completed booking for this customer.

### 5.2 List Reviews for Barber

```
GET /v1/barbers/{slug}/reviews?sort=newest&cursor=...&limit=20
```

**Query Parameters:**

| Param | Type | Default | Description |
|---|---|---|---|
| `sort` | enum | `newest` | `newest`, `highest`, `lowest`, `most_helpful` |
| `cursor` | string | — | Pagination cursor |
| `limit` | int | 20 | Results per page |

**Response:**

```json
{
  "data": [
    {
      "id": "rev_abc",
      "customer_name": "Alex R.",
      "rating": 5,
      "title": "Best fade in Bed-Stuy",
      "body": "Jordan is incredibly precise...",
      "is_verified": true,
      "helpful_count": 12,
      "created_at": "2026-05-10T14:30:00Z"
    }
  ],
  "aggregate": {
    "average_rating": 4.8,
    "total_reviews": 134,
    "distribution": {
      "5": 98,
      "4": 28,
      "3": 6,
      "2": 1,
      "1": 1
    }
  },
  "pagination": { "cursor": "...", "has_more": true, "limit": 20, "total": 134 }
}
```

### 5.3 Mark Review Helpful

```
POST /v1/reviews/{review_id}/helpful
```

**Response:**

```json
{
  "review_id": "rev_abc",
  "helpful_count": 13,
  "user_voted": true
}
```

---

## 6. Barber Business Endpoints (Provider Dashboard)

### 6.1 Get Dashboard KPIs

```
GET /v1/barbers/{slug}/dashboard?period=today
```

**Query Parameters:**

| Param | Type | Default | Description |
|---|---|---|---|
| `period` | enum | `today` | `today`, `week`, `month`, `quarter`, `custom` |
| `start_date` | date | — | Custom start (for `custom` period) |
| `end_date` | date | — | Custom end (for `custom` period) |

**Response:**

```json
{
  "barber_id": "bar_abc123",
  "period": "today",
  "period_label": "Wednesday, May 13, 2026",
  "timezone": "America/New_York",
  "realtime": { "generated_at": "2026-05-13T14:30:00Z" },
  "kpis": {
    "revenue_cents": 22500,
    "bookings": 5,
    "no_shows": 0,
    "cancellations": 1,
    "nps": 4.8,
    "churn_risk_pct": 3.2
  },
  "comparison": {
    "revenue_change_pct": 12.5,
    "bookings_change_pct": 8.3,
    "no_shows_change_pct": -2.1
  },
  "top_services": [
    { "name": "Classic Fade", "count": 3, "revenue_cents": 13500 },
    { "name": "Beard Trim", "count": 2, "revenue_cents": 6000 }
  ],
  "recent_bookings": [
    {
      "id": "apt_def456",
      "customer_name": "Alex R.",
      "service_name": "Classic Fade",
      "starts_at": "2026-05-13T09:00:00-04:00",
      "state": "completed",
      "amount_cents": 4500
    }
  ]
}
```

### 6.2 Get Analytics Timeseries

```
GET /v1/barbers/{slug}/analytics?metric=revenue&granularity=day&start=2026-04-13&end=2026-05-13
```

**Query Parameters:**

| Param | Type | Default | Description |
|---|---|---|---|
| `metric` | enum | `revenue` | `revenue`, `bookings`, `no_shows`, `nps`, `ratings` |
| `granularity` | enum | `day` | `hour`, `day`, `week`, `month` |
| `start` | date | 30 days ago | Start date |
| `end` | date | today | End date |

**Response:**

```json
{
  "metric": "revenue",
  "granularity": "day",
  "currency": "USD",
  "data_points": [
    { "date": "2026-04-13", "value": 22500 },
    { "date": "2026-04-14", "value": 18000 }
  ],
  "totals": {
    "sum_cents": 675000,
    "avg_daily_cents": 22500,
    "max_daily_cents": 45000,
    "min_daily_cents": 0
  }
}
```

### 6.3 Get Clients (CRM)

```
GET /v1/barbers/{slug}/clients?search=Alex&win_back=true&cursor=...&limit=20
```

**Query Parameters:**

| Param | Type | Default | Description |
|---|---|---|---|
| `search` | string | — | Search by customer name or phone |
| `win_back` | bool | false | Only clients with last visit > 60 days ago |
| `sort` | enum | `last_visit` | `last_visit`, `lifetime_value`, `name`, `bookings` |
| `cursor` | string | — | Pagination cursor |
| `limit` | int | 20 | Results per page |

**Response:**

```json
{
  "data": [
    {
      "customer_id": "usr_abc",
      "customer_name": "Alex R.",
      "customer_phone": "+1-555-0123",
      "total_visits": 24,
      "lifetime_value_cents": 108000,
      "last_visit": "2026-04-20T10:00:00-04:00",
      "days_since_last_visit": 23,
      "favorite_service": "Classic Fade",
      "tags": ["vip", "referral-source:google"],
      "notes": "Prefers morning appointments. Allergic to lavender."
    }
  ],
  "pagination": { "cursor": "...", "has_more": true, "limit": 20, "total": 89 }
}
```

### 6.4 Update Client Notes

```
PATCH /v1/barbers/{slug}/clients/{customer_id}
```

**Request:**
```json
{
  "notes": "Prefers morning appointments. Allergic to lavender. Birthday: June 15.",
  "tags": ["vip", "birthday-june"]
}
```

---

## 7. Provider Availability Management

### 7.1 Get Recurring Rules

```
GET /v1/barbers/{slug}/availability
```

**Response:**

```json
{
  "data": [
    {
      "id": "rr_abc",
      "day_of_week": 1,
      "day_name": "Monday",
      "start_time": "09:00",
      "end_time": "17:00",
      "interval_weeks": 1,
      "is_active": true
    }
  ]
}
```

### 7.2 Set/Update Recurring Rule

```
PUT /v1/barbers/{slug}/availability/rules/{rule_id}
```

**Request:**
```json
{
  "day_of_week": 1,
  "start_time": "10:00",
  "end_time": "18:00",
  "interval_weeks": 1
}
```

### 7.3 Create Time-Off Block

```
POST /v1/barbers/{slug}/time-off
Idempotency-Key: ik_pqr678
```

**Request:**

```json
{
  "starts_at": "2026-06-01T00:00:00-04:00",
  "ends_at": "2026-06-07T23:59:00-04:00",
  "reason": "Vacation"
}
```

**Response (201 Created):**

```json
{
  "id": "tof_abc",
  "starts_at": "2026-06-01T00:00:00-04:00",
  "ends_at": "2026-06-07T23:59:00-04:00",
  "reason": "Vacation"
}
```

### 7.4 Delete Time-Off Block

```
DELETE /v1/barbers/{slug}/time-off/{id}
```

---

## 8. Stripe Connect Express (Payouts)

### 8.1 Create Connect Account

```
POST /v1/barbers/{slug}/payouts/connect
Idempotency-Key: ik_stu901
```

**Response:**

```json
{
  "stripe_account_id": "acct_xyz",
  "onboarding_url": "https://connect.stripe.com/express/onboarding/abc",
  "status": "pending"
}
```

### 8.2 Get Payout Status

```
GET /v1/barbers/{slug}/payouts/status
```

**Response:**

```json
{
  "stripe_account_id": "acct_xyz",
  "charges_enabled": true,
  "payouts_enabled": true,
  "payouts_interval": "daily",
  "pending_balance_cents": 45000,
  "currency": "USD",
  "last_payout": {
    "amount_cents": 42000,
    "date": "2026-05-12",
    "status": "paid"
  }
}
```

---

## 9. Gift Cards

### 9.1 Purchase Gift Card

```
POST /v1/gift-cards
Idempotency-Key: ik_vwx234
```

**Request:**

```json
{
  "amount_cents": 5000,
  "recipient_email": "friend@example.com",
  "message": "Happy birthday!"
}
```

**Response (201 Created):**

```json
{
  "id": "gc_abc",
  "code": "EDGE-HBD-ABCD",
  "amount_cents": 5000,
  "currency": "USD",
  "expires_at": "2027-05-13"
}
```

### 9.2 Redeem Gift Card

```
POST /v1/gift-cards/redeem
```

**Request:**

```json
{
  "code": "EDGE-HBD-ABCD",
  "appointment_id": "apt_def456"
}
```

**Response:**

```json
{
  "code": "EDGE-HBD-ABCD",
  "remaining_cents": 500,
  "applied_cents": 4500,
  "currency": "USD"
}
```

---

## 10. Loyalty

### 10.1 Get Points

```
GET /v1/loyalty
```

**Response:**

```json
{
  "points": 450,
  "lifetime_points": 1200,
  "tier": "silver",
  "next_tier": "gold",
  "points_to_next_tier": 550,
  "tier_benefits": {
    "silver": "10% off every 5th cut, priority booking"
  }
}
```

### 10.2 Transaction History

```
GET /v1/loyalty/transactions?cursor=...&limit=20
```

**Response:**

```json
{
  "data": [
    {
      "points": 50,
      "reason": "booking",
      "reference_id": "apt_def456",
      "created_at": "2026-05-13T09:30:00Z"
    }
  ]
}
```

---

## 11. Policies (SSoT)

### 11.1 Get Active Policies

```
GET /v1/policies
```

**Response:**

```json
{
  "data": [
    {
      "slug": "cancellation",
      "title": "Cancellation Policy",
      "body_md": "## Cancellation Policy\n\nFree cancellation up to 4 hours...",
      "version": 3,
      "published_at": "2026-05-01T00:00:00Z"
    },
    {
      "slug": "deposit",
      "title": "Deposit Policy",
      "body_md": "...",
      "version": 2,
      "published_at": "2026-05-01T00:00:00Z"
    },
    {
      "slug": "recut-guarantee",
      "title": "7-Day Re-Cut Guarantee",
      "body_md": "...",
      "version": 1,
      "published_at": "2026-04-15T00:00:00Z"
    }
  ]
}
```

---

## 12. Admin / Super-Admin Endpoints

### 12.1 List Tenants

```
GET /v1/admin/tenants
```

**Response:**

```json
{
  "data": [
    {
      "id": "tenant_brooklyn",
      "slug": "brooklyn",
      "name": "Brooklyn — Bedford-Stuy",
      "currency": "USD",
      "locale": "en-US",
      "timezone": "America/New_York",
      "plan": "pro",
      "barber_count": 2,
      "customer_count": 156,
      "revenue_mtd_cents": 4500000,
      "is_active": true,
      "created_at": "2026-01-15T00:00:00Z"
    }
  ]
}
```

### 12.2 Impersonate Tenant

```
POST /v1/admin/impersonate
```

**Request:**

```json
{
  "target_tenant_id": "tenant_la"
}
```

**Response:**

```json
{
  "session_token": "jwt_impersonation_token...",
  "expires_at": "2026-05-13T15:00:00Z",
  "warning": "You are viewing as LA tenant. All actions are logged."
}
```

This action is logged in the audit_log with `action = 'impersonation.start'`, including the super-admin's ID, target tenant, and timestamp.

### 12.3 View Audit Log

```
GET /v1/admin/audit-log?actor=super_admin&target_tenant=tenant_la&action=impersonation&start=2026-05-01&end=2026-05-13&cursor=...&limit=50
```

**Query Parameters:**

| Param | Type | Default | Description |
|---|---|---|---|
| `actor` | string | — | Filter by actor ID |
| `target_tenant` | string | — | Filter by target tenant ID |
| `action` | string | — | Filter by action type (prefix search) |
| `start` | datetime | — | Start date filter |
| `end` | datetime | — | End date filter |
| `cursor` | string | — | Pagination cursor |
| `limit` | int | 50 | Results per page (max 100) |

**Response:**

```json
{
  "data": [
    {
      "id": "al_abc123",
      "actor_id": "usr_super_admin",
      "actor_role": "super_admin",
      "action": "impersonation.start",
      "target_type": "tenant",
      "target_id": "tenant_la",
      "details": {
        "impersonated_tenant_slug": "la",
        "impersonation_session_id": "sess_abc"
      },
      "ip_address": "203.0.113.42",
      "request_id": "req_def456",
      "created_at": "2026-05-13T14:00:00Z"
    }
  ],
  "pagination": { "cursor": "...", "has_more": false, "limit": 50, "total": 3 }
}
```

### 12.4 Update Tenant Plan

```
PATCH /v1/admin/tenants/{tenant_id}
```

**Request:**

```json
{
  "plan": "enterprise",
  "billing_cycle_start": "2026-06-01"
}
```

### 12.5 Get Tenant Billing Summary

```
GET /v1/admin/tenants/{tenant_id}/billing
```

**Response:**

```json
{
  "tenant_id": "tenant_brooklyn",
  "plan": "pro",
  "monthly_fee_cents": 9900,
  "transaction_fee_pct": 2.9,
  "mtd_transaction_volume_cents": 4500000,
  "mtd_platform_fees_cents": 130500,
  "mtd_subtotal_cents": 140400,
  "currency": "USD",
  "next_billing_date": "2026-06-01"
}
```

---

## 13. Webhooks (Inbound — Stripe, Twilio, Resend)

```
POST /v1/webhooks/stripe
```

Receives Stripe events. Each event is recorded in `webhook_ledger` with `UNIQUE(provider, event_id)` for idempotent processing. Returns `200 OK` for all events (including duplicates). Processing errors are logged but the webhook always returns 200.

**Event handling mapping:**

| Stripe Event | Action |
|---|---|
| `checkout.session.completed` | Confirm booking, create payment record |
| `payment_intent.succeeded` | Update payment status |
| `payment_intent.payment_failed` | Notify customer, release slot hold |
| `charge.refunded` | Update refund status |
| `account.updated` | Update barber Connect account status |

```
POST /v1/webhooks/twilio
```

Inbound SMS messages — parses booking commands and routes to booking flow.

```
POST /v1/webhooks/resend
```

Email delivery events (bounced, delivered, clicked) — updates email campaign tracking.

**Webhook security:**

- All webhooks verify signature via provider-specific mechanism (Stripe: `stripe-signature`, Twilio: `X-Twilio-Signature`, Resend: `svix-signature`)
- Signature verification failure → `401 Unauthorized`
- Idempotency key (provider event ID) → duplicate detection via `webhook_ledger` table

---

## 14. Tenant Context Endpoint

```
GET /v1/tenant
```

Returns the current tenant's configuration (no auth required — derived from subdomain/header):

```json
{
  "tenant_id": "tenant_madrid",
  "slug": "madrid",
  "name": "Madrid — Malasaña",
  "currency": "EUR",
  "locale": "es-ES",
  "language": "es",
  "timezone": "Europe/Madrid",
  "compliance": ["GDPR"],
  "plan": "pro"
}
```

---

## 15. Error Scenarios — Full Response Catalog

### 15.1 Validation Error (400)

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Request validation failed",
    "retryable": false,
    "request_id": "req_abc",
    "details": {
      "fields": [
        {
          "field": "starts_at",
          "message": "Must be a future timestamp",
          "code": "INVALID_VALUE"
        },
        {
          "field": "party_size",
          "message": "Must be between 1 and 10",
          "code": "OUT_OF_RANGE"
        }
      ]
    }
  }
}
```

### 15.2 Rate Limited (429)

```json
{
  "error": {
    "code": "RATE_LIMITED",
    "message": "Too many requests. Retry after 12 seconds.",
    "retryable": true,
    "request_id": "req_abc"
  }
}
```

### 15.3 Not Found (404)

```json
{
  "error": {
    "code": "NOT_FOUND",
    "message": "Barber with slug 'jordan-medina' not found in this tenant.",
    "retryable": false,
    "request_id": "req_abc"
  }
}
```

### 15.4 Conflict — Slot Taken (409)

```json
{
  "error": {
    "code": "SLOT_UNAVAILABLE",
    "message": "This slot was just booked by another customer. Please select a different time.",
    "retryable": true,
    "request_id": "req_abc"
  }
}
```

### 15.5 Conflict — Duplicate Idempotency (409)

```json
{
  "error": {
    "code": "DUPLICATE_REQUEST",
    "message": "This Idempotency-Key was already used with different request body.",
    "retryable": false,
    "request_id": "req_abc"
  }
}
```

### 15.6 Forbidden — Cross-Tenant Access (403)

```json
{
  "error": {
    "code": "FORBIDDEN",
    "message": "You do not have access to this tenant's data.",
    "retryable": false,
    "request_id": "req_abc"
  }
}
```

---

## 16. OpenAPI 3.0 Fragment

```yaml
openapi: "3.0.3"
info:
  title: Edgecut & Co. API
  version: "1.0.0"
  description: "Multi-tenant barbershop booking and management API"
servers:
  - url: https://api.edgecut.co/v1
    description: Production
  - url: https://api.staging.edgecut.co/v1
    description: Staging
security:
  - bearerAuth: []
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
  headers:
    X-RateLimit-Limit:
      schema: { type: integer }
      description: Maximum requests per minute
    X-RateLimit-Remaining:
      schema: { type: integer }
      description: Remaining requests in current window
    X-RateLimit-Reset:
      schema: { type: integer, format: unix-timestamp }
      description: When the limit resets
    Idempotency-Key:
      schema: { type: string, format: uuid }
      description: Client-generated idempotency key for mutations
paths:
  /barbers:
    get:
      summary: Search barbers
      parameters:
        - name: search
          in: query
          schema: { type: string }
        - name: location
          in: query
          schema: { type: string }
        - name: lat
          in: query
          schema: { type: number, format: float }
        - name: lng
          in: query
          schema: { type: number, format: float }
        - name: radius_km
          in: query
          schema: { type: integer, default: 10 }
        - name: specialty
          in: query
          schema: { type: string }
        - name: language
          in: query
          schema: { type: string }
        - name: available_now
          in: query
          schema: { type: boolean, default: false }
        - name: sort
          in: query
          schema: { type: string, enum: [relevance, distance, price_asc, price_desc, rating] }
        - name: cursor
          in: query
          schema: { type: string }
        - name: limit
          in: query
          schema: { type: integer, default: 20, maximum: 100 }
      responses:
        "200":
          description: Barbers list
          headers:
            X-RateLimit-Limit: { $ref: '#/components/headers/X-RateLimit-Limit' }
            X-RateLimit-Remaining: { $ref: '#/components/headers/X-RateLimit-Remaining' }
            X-RateLimit-Reset: { $ref: '#/components/headers/X-RateLimit-Reset' }
  /bookings/hold:
    post:
      summary: Reserve a slot atomically
      parameters:
        - name: Idempotency-Key
          in: header
          required: true
          schema: { type: string, format: uuid }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [barber_id, service_id, starts_at]
              properties:
                barber_id: { type: string, format: uuid }
                service_id: { type: string, format: uuid }
                starts_at: { type: string, format: date-time }
                party_size: { type: integer, default: 1, minimum: 1, maximum: 10 }
                notes: { type: string, maxLength: 500 }
      responses:
        "201":
          description: Slot held successfully
        "409":
          description: Slot taken or duplicate request
  /admin/audit-log:
    get:
      summary: View audit log (super_admin only)
      parameters:
        - name: actor
          in: query
          schema: { type: string }
        - name: target_tenant
          in: query
          schema: { type: string }
        - name: action
          in: query
          schema: { type: string }
        - name: start
          in: query
          schema: { type: string, format: date-time }
        - name: end
          in: query
          schema: { type: string, format: date-time }
        - name: cursor
          in: query
          schema: { type: string }
        - name: limit
          in: query
          schema: { type: integer, default: 50, maximum: 100 }
      responses:
        "200":
          description: Audit log entries
        "403":
          description: Not authorized (super_admin only)
```

---

## 17. Rate Limit & Throttle Configuration

| Tier | Requests/min | Burst | Scope |
|---|---|---|---|
| Customer (unauthenticated) | 60 | 10 | IP-based |
| Customer (authenticated) | 300 | 30 | User-based |
| Barber | 600 | 60 | User-based |
| Admin | 1000 | 100 | User-based |
| Super-admin | 2000 | 200 | User-based |
| Webhook (Stripe) | Unlimited | — | IP whitelist |
| Webhook (Twilio) | Unlimited | — | IP whitelist |

---

## 18. Caching Strategy

| Endpoint | Cache | TTL | Invalidation |
|---|---|---|---|
| `GET /v1/barbers` | CDN + Redis | 30s | Slot change, barber update |
| `GET /v1/barbers/{slug}` | CDN + Redis | 60s | Barber profile update |
| `GET /v1/barbers/{slug}/slots` | Redis | 15s | Booking, time-off change |
| `GET /v1/policies` | CDN + Browser | 5min | Policy version bump |
| `GET /v1/tenant` | CDN + Browser | 1h | Tenant config change |

---

## 19. Sunset & Deprecation Headers

When an endpoint version is deprecated:

```
Deprecation: true
Sunset: Sat, 15 Nov 2026 00:00:00 GMT
Link: </v2/barbers>; rel="successor-version"
```

Clients MUST check for `Deprecation: true` and migrate before the `Sunset` date. After sunset, the endpoint returns 410 Gone.

---

*End of 03-api-design.md — Edgecut & Co. REST API specification.*
