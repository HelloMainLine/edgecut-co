-- ============================================================================
-- 02-database-schema.sql — Edgecut & Co. Complete Database Schema
-- ============================================================================
-- Multi-tenant barbershop marketplace (3 tenants: Brooklyn, LA, Madrid)
-- Postgres 16+ with RLS, EXCLUDE constraints for atomic slot booking,
-- webhook idempotency ledger, and append-only audit log.
-- ============================================================================

BEGIN;

-- ============================================================================
-- EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";       -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "btree_gist";      -- GiST exclusion support
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements"; -- query performance (optional)

-- ============================================================================
-- 1. TENANTS
-- ============================================================================
CREATE TABLE tenants (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug         text NOT NULL UNIQUE CHECK (slug ~ '^[a-z][a-z0-9-]{2,31}$'),
  name         text NOT NULL,
  currency     text NOT NULL CHECK (currency IN ('USD', 'EUR')),
  locale       text NOT NULL,                 -- 'en-US', 'es-ES'
  language     text NOT NULL,                 -- 'en', 'es'
  timezone     text NOT NULL,                 -- IANA tz: 'America/New_York', 'America/Los_Angeles', 'Europe/Madrid'
  compliance   text[] NOT NULL DEFAULT '{}',  -- array: 'CCPA', 'GDPR'
  stripe_connect_app_id text,
  plan         text NOT NULL DEFAULT 'starter' CHECK (plan IN ('starter', 'pro', 'enterprise')),
  billing_cycle_start date,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_tenants_slug ON tenants (slug);

-- Seed tenants
INSERT INTO tenants (slug, name, currency, locale, language, timezone, compliance) VALUES
  ('brooklyn', 'Brooklyn — Bedford-Stuy', 'USD', 'en-US', 'en', 'America/New_York', '{CCPA}'),
  ('la',       'Los Angeles — Silver Lake', 'USD', 'en-US', 'en', 'America/Los_Angeles', '{CCPA}'),
  ('madrid',   'Madrid — Malasaña', 'EUR', 'es-ES', 'es', 'Europe/Madrid', '{GDPR}');

-- ============================================================================
-- 2. USERS (customers — multi-tenant, each tenant gets its own customer base)
-- ============================================================================
CREATE TABLE users (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id),
  email           text NOT NULL,
  phone           text,
  password_hash   text,
  auth_provider   text,          -- 'email', 'google', 'apple'
  auth_provider_id text,         -- provider-specific user ID
  name            text NOT NULL,
  preferred_language text NOT NULL DEFAULT 'en',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, email)
);

CREATE INDEX idx_users_tenant ON users (tenant_id);
CREATE INDEX idx_users_email ON users (tenant_id, email);

-- ============================================================================
-- 3. BARBERS (providers)
-- ============================================================================
CREATE TABLE barbers (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id),
  stripe_account_id   text,                  -- Stripe Connect Express account ID
  name                text NOT NULL,
  bio                 text,
  photo_url           text,
  specialties         text[] NOT NULL DEFAULT '{}',
  languages           text[] NOT NULL DEFAULT '{}',
  years_experience    smallint,
  is_active           boolean NOT NULL DEFAULT true,
  is_featured         boolean NOT NULL DEFAULT false,
  max_buffer_minutes  smallint NOT NULL DEFAULT 15,  -- between appointments
  deposit_policy      text NOT NULL DEFAULT 'default', -- references biz-policies
  recut_guarantee_days smallint NOT NULL DEFAULT 7,
  slug                text NOT NULL,
  location_name       text NOT NULL,
  address             text,
  lat                 numeric(10,7),
  lng                 numeric(10,7),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, slug),
  CHECK (max_buffer_minutes >= 0 AND max_buffer_minutes <= 60)
);

CREATE INDEX idx_barbers_tenant ON barbers (tenant_id);
CREATE INDEX idx_barbers_active ON barbers (tenant_id, is_active) WHERE is_active = true;
CREATE INDEX idx_barbers_featured ON barbers (tenant_id, is_featured) WHERE is_featured = true;
CREATE INDEX idx_barbers_geo ON barbers USING GIST (ll_to_earth(lat, lng));

-- Seed 6 sample barbers (2 per tenant)
INSERT INTO barbers (tenant_id, name, slug, specialties, languages, years_experience, location_name, lat, lng)
SELECT t.id, b.name, b.slug, b.specialties, b.languages, b.years_experience, b.location_name, b.lat, b.lng
FROM tenants t
CROSS JOIN LATERAL (VALUES
  ('Jordan Medina',   'jordan-medina',   ARRAY['fade', 'beard-trim', 'hot-towel'], ARRAY['en', 'es'], 8,  'Bedford-Stuy, Brooklyn',      40.6872, -73.9419),
  ('Keisha Okafor',   'keisha-okafor',   ARRAY['braids', 'taper', 'color'],        ARRAY['en'],        12, 'Bedford-Stuy, Brooklyn',      40.6881, -73.9402),
  ('Luca Romano',     'luca-romano',     ARRAY['classic-cut', 'straight-razor', 'designs'], ARRAY['en', 'it'], 15, 'Silver Lake, Los Angeles',     34.0866, -118.2716),
  ('Marta de la Vega','marta-de-la-vega', ARRAY['precision-cut', 'balayage', 'blowout'], ARRAY['es', 'en'], 10, 'Silver Lake, Los Angeles',     34.0872, -118.2720),
  ('Sam Park',        'sam-park',        ARRAY['taper', 'fade', 'texture-cut'],    ARRAY['en', 'ko'],   6,  'Malasaña, Madrid',             40.4255, -3.7038),
  ('Yusuf Osman',     'yusuf-osman',     ARRAY['traditional', 'designs', 'hot-towel'], ARRAY['en', 'ar', 'es'], 20, 'Malasaña, Madrid',            40.4260, -3.7030)
) AS b(name, slug, specialties, languages, years_experience, location_name, lat, lng)
WHERE t.slug = CASE
  WHEN b.location_name LIKE '%Brooklyn%' THEN 'brooklyn'
  WHEN b.location_name LIKE '%Los Angeles%' THEN 'la'
  ELSE 'madrid'
END;

-- ============================================================================
-- 4. SERVICES (per tenant, per barber)
-- ============================================================================
CREATE TABLE services (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id),
  barber_id     uuid NOT NULL REFERENCES barbers(id),
  name          text NOT NULL,
  description   text,
  duration_min  smallint NOT NULL CHECK (duration_min >= 15 AND duration_min <= 240),
  price_cents   integer NOT NULL CHECK (price_cents >= 0),
  category      text NOT NULL DEFAULT 'cut' CHECK (category IN ('cut', 'color', 'shave', 'styling', 'treatment', 'package')),
  is_active     boolean NOT NULL DEFAULT true,
  sort_order    smallint NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_services_tenant ON services (tenant_id);
CREATE INDEX idx_services_barber ON services (barber_id);
CREATE INDEX idx_services_active ON services (barber_id, is_active) WHERE is_active = true;

-- ============================================================================
-- 5. RECURRING RULES (barber availability templates)
-- ============================================================================
CREATE TABLE recurring_rules (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id),
  barber_id     uuid NOT NULL REFERENCES barbers(id),
  day_of_week   smallint NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),  -- 0=Sun
  start_time    time NOT NULL,          -- e.g. '09:00'
  end_time      time NOT NULL,          -- e.g. '17:00'
  interval_weeks smallint NOT NULL DEFAULT 1 CHECK (interval_weeks >= 1),
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),

  CHECK (end_time > start_time),
  CHECK (interval_weeks <= 12)
);

CREATE INDEX idx_recurring_rules_barber ON recurring_rules (barber_id, is_active) WHERE is_active = true;

-- ============================================================================
-- 6. TIME OFF (barber unavailable blocks — overrides recurring rules)
-- ============================================================================
CREATE TABLE time_off (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id),
  barber_id     uuid NOT NULL REFERENCES barbers(id),
  starts_at     timestamptz NOT NULL,
  ends_at       timestamptz NOT NULL,
  reason        text,
  created_at    timestamptz NOT NULL DEFAULT now(),

  CHECK (ends_at > starts_at),
  -- No overlapping time-off blocks for the same barber
  EXCLUDE USING gist (barber_id WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&)
);

CREATE INDEX idx_time_off_barber ON time_off (barber_id, starts_at);

-- ============================================================================
-- 7. SLOTS / APPOINTMENTS
-- ============================================================================
-- The EXCLUDE constraint guarantees atomic booking: no two appointments
-- for the same barber can overlap in time. The WHERE clause excludes
-- cancelled and no-show states so those don't block rebooking the slot.
CREATE TYPE appointment_state AS ENUM (
  'held',                 -- reserved, awaiting payment (TTL 7 min)
  'booked',               -- confirmed via payment
  'checked-in',           -- customer arrived
  'in-progress',          -- barber started the service
  'completed',            -- service done
  'cancelled-by-client',  -- customer cancelled
  'cancelled-by-provider',-- barber cancelled
  'cancelled-by-system',  -- hold TTL expired or system auto-cancel
  'no-show'               -- customer didn't arrive
);

CREATE TABLE appointments (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id),
  barber_id       uuid NOT NULL REFERENCES barbers(id),
  customer_id     uuid NOT NULL REFERENCES users(id),
  service_id      uuid NOT NULL REFERENCES services(id),
  party_size      smallint NOT NULL DEFAULT 1 CHECK (party_size >= 1 AND party_size <= 10),
  starts_at       timestamptz NOT NULL,
  ends_at         timestamptz NOT NULL,
  state           appointment_state NOT NULL DEFAULT 'held',
  held_until      timestamptz,              -- cleared on booking, used for hold TTL
  cancel_reason   text,
  source          text NOT NULL DEFAULT 'web' CHECK (source IN ('web', 'mobile', 'sms', 'kiosk', 'admin')),
  notes           text,
  idempotency_key text,                     -- client-generated Idempotency-Key for POST /book
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  -- ATOMIC BOOKING: the EXCLUDE constraint prevents overlapping appointments
  -- for the same barber. Only non-cancelled, non-no-show states conflict.
  EXCLUDE USING gist (
    barber_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  ) WHERE (state NOT IN ('cancelled-by-client', 'cancelled-by-provider', 'cancelled-by-system', 'no-show')),

  CHECK (ends_at > starts_at),
  CHECK (held_until IS NULL OR held_until > created_at),
  UNIQUE (barber_id, starts_at, customer_id)  -- prevent double-book by same customer
);

CREATE INDEX idx_appointments_barber_date ON appointments (barber_id, starts_at);
CREATE INDEX idx_appointments_customer ON appointments (customer_id);
CREATE INDEX idx_appointments_tenant ON appointments (tenant_id);
CREATE INDEX idx_appointments_state_held ON appointments (state, held_until)
  WHERE state = 'held';
CREATE INDEX idx_appointments_idempotency ON appointments (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- ============================================================================
-- 8. PAYMENTS
-- ============================================================================
CREATE TYPE payment_status AS ENUM (
  'pending', 'processing', 'succeeded', 'failed', 'refunded', 'partially_refunded'
);

CREATE TYPE payment_type AS ENUM (
  'deposit',    -- deposit hold for >$50 or party bookings
  'full',       -- full service payment
  'partial',    -- split payment (e.g., deposit + remainder)
  'refund'      -- money returned
);

CREATE TABLE payments (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id),
  appointment_id      uuid NOT NULL REFERENCES appointments(id),
  stripe_payment_intent_id text,
  stripe_charge_id    text,
  amount_cents        integer NOT NULL CHECK (amount_cents >= 0),
  currency            text NOT NULL,
  status              payment_status NOT NULL DEFAULT 'pending',
  payment_type        payment_type NOT NULL DEFAULT 'full',
  platform_fee_cents  integer NOT NULL DEFAULT 0 CHECK (platform_fee_cents >= 0),
  transfer_id         text,                -- Stripe transfer ID to barber
  refunded_amount_cents integer NOT NULL DEFAULT 0 CHECK (refunded_amount_cents >= 0),
  metadata            jsonb,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_payments_appointment ON payments (appointment_id);
CREATE INDEX idx_payments_tenant ON payments (tenant_id);
CREATE INDEX idx_payments_stripe ON payments (stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

-- ============================================================================
-- 9. REVIEWS
-- ============================================================================
CREATE TABLE reviews (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id),
  appointment_id  uuid NOT NULL REFERENCES appointments(id),
  barber_id       uuid NOT NULL REFERENCES barbers(id),
  customer_id     uuid NOT NULL REFERENCES users(id),
  rating          smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  title           text,
  body            text,
  is_verified     boolean NOT NULL DEFAULT false,  -- verified purchase
  is_public       boolean NOT NULL DEFAULT true,
  helpful_count   integer NOT NULL DEFAULT 0 CHECK (helpful_count >= 0),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  -- One review per appointment
  UNIQUE (appointment_id),
  -- One review per customer per barber (prevent review spam)
  UNIQUE (barber_id, customer_id)
);

CREATE INDEX idx_reviews_barber ON reviews (barber_id, is_public) WHERE is_public = true;
CREATE INDEX idx_reviews_customer ON reviews (customer_id);
CREATE INDEX idx_reviews_tenant ON reviews (tenant_id);

-- ============================================================================
-- 10. REVIEW HELPFULNESS VOTES
-- ============================================================================
CREATE TABLE review_helpfulness (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id   uuid NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id),
  is_helpful  boolean NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),

  UNIQUE (review_id, user_id)
);

CREATE INDEX idx_review_helpfulness_review ON review_helpfulness (review_id);

-- ============================================================================
-- 11. LOOKS (barber portfolio gallery items)
-- ============================================================================
CREATE TABLE looks (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id),
  barber_id   uuid NOT NULL REFERENCES barbers(id),
  image_url   text NOT NULL,
  title       text,
  description text,
  tags        text[] NOT NULL DEFAULT '{}',
  sort_order  smallint NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),

  UNIQUE (barber_id, image_url)
);

CREATE INDEX idx_looks_barber ON looks (barber_id, is_active) WHERE is_active = true;

-- ============================================================================
-- 12. GIFT CARDS
-- ============================================================================
CREATE TABLE gift_cards (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id),
  issuer_id       uuid REFERENCES users(id),
  recipient_email text,
  code            text NOT NULL UNIQUE,
  amount_cents    integer NOT NULL CHECK (amount_cents > 0),
  remaining_cents integer NOT NULL CHECK (remaining_cents >= 0),
  currency        text NOT NULL,
  expires_at      date,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  CHECK (remaining_cents <= amount_cents)
);

CREATE INDEX idx_gift_cards_tenant ON gift_cards (tenant_id);
CREATE INDEX idx_gift_cards_code ON gift_cards (code) WHERE is_active = true;

-- ============================================================================
-- 13. LOYALTY POINTS
-- ============================================================================
CREATE TABLE loyalty_points (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id),
  user_id         uuid NOT NULL REFERENCES users(id),
  points          integer NOT NULL DEFAULT 0 CHECK (points >= 0),
  lifetime_points integer NOT NULL DEFAULT 0 CHECK (lifetime_points >= 0),
  tier            text NOT NULL DEFAULT 'standard' CHECK (tier IN ('standard', 'silver', 'gold')),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, user_id)
);

CREATE INDEX idx_loyalty_user ON loyalty_points (user_id);

-- ============================================================================
-- 14. LOYALTY TRANSACTIONS
-- ============================================================================
CREATE TABLE loyalty_transactions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id),
  points      integer NOT NULL,             -- positive for earn, negative for redeem
  reason      text NOT NULL,                -- 'booking', 'referral', 'review', 'redemption'
  reference_id uuid,                         -- appointment_id or referral_id
  created_at  timestamptz NOT NULL DEFAULT now(),

  CHECK (points != 0)  -- no zero-point transactions
);

CREATE INDEX idx_loyalty_tx_user ON loyalty_transactions (user_id);

-- ============================================================================
-- 15. REFERRALS
-- ============================================================================
CREATE TABLE referrals (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id),
  referrer_id     uuid NOT NULL REFERENCES users(id),
  referee_email   text NOT NULL,
  referee_id      uuid REFERENCES users(id),  -- set when referee signs up
  code            text NOT NULL,
  reward_cents    integer NOT NULL DEFAULT 1000,  -- default $10
  status          text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'expired')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  completed_at    timestamptz,

  UNIQUE (code)
);

CREATE INDEX idx_referrals_referrer ON referrals (referrer_id);
CREATE INDEX idx_referrals_code ON referrals (code);

-- ============================================================================
-- 16. WEBHOOK LEDGER (idempotency)
-- ============================================================================
-- Every incoming webhook is recorded here. The UNIQUE (provider, event_id)
-- constraint guarantees exactly-once processing: the second arrival hits a
-- unique violation and is silently acknowledged with 200 OK.
CREATE TABLE webhook_ledger (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id),
  provider      text NOT NULL,        -- 'stripe', 'twilio', 'resend'
  event_id      text NOT NULL,        -- Stripe: evt_xxx, Twilio: SMxxx, Resend: re_xxx
  event_type    text NOT NULL,
  status        text NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'completed', 'failed')),
  request_body  jsonb,
  response_code smallint,
  error_message text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  processed_at  timestamptz,

  -- IDEMPOTENCY: same provider + same event = duplicate, reject with 200
  UNIQUE (provider, event_id)
);

CREATE INDEX idx_webhook_ledger_provider ON webhook_ledger (provider);
CREATE INDEX idx_webhook_ledger_status ON webhook_ledger (status) WHERE status = 'processing';
CREATE INDEX idx_webhook_ledger_tenant ON webhook_ledger (tenant_id);

-- ============================================================================
-- 17. AUDIT LOG (append-only)
-- ============================================================================
-- Every administrative action is logged here. The table is append-only:
-- no UPDATE or DELETE is allowed except by super-admin bypass.
CREATE TABLE audit_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid REFERENCES tenants(id),   -- NULL for platform-level actions
  actor_id        uuid NOT NULL,                  -- user who performed the action
  actor_role      text NOT NULL CHECK (actor_role IN ('customer', 'barber', 'admin', 'super_admin', 'system')),
  action          text NOT NULL,                  -- e.g. 'booking.created', 'user.impersonated'
  target_type     text,                           -- 'appointment', 'user', 'barber', 'tenant'
  target_id       uuid,
  details         jsonb,                          -- arbitrary structured data
  ip_address      inet,
  user_agent      text,
  request_id      text,                           -- correlation ID
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Append-only enforcement: these are applied AFTER table creation
-- via separate ALTER statements (see end of file).

CREATE INDEX idx_audit_log_tenant ON audit_log (tenant_id);
CREATE INDEX idx_audit_log_actor ON audit_log (actor_id, created_at DESC);
CREATE INDEX idx_audit_log_action ON audit_log (action, created_at DESC);
CREATE INDEX idx_audit_log_created ON audit_log (created_at DESC);
CREATE INDEX idx_audit_log_target ON audit_log (target_type, target_id)
  WHERE target_type IS NOT NULL;

-- ============================================================================
-- 18. TENANT SETTINGS (feature flags, config per tenant)
-- ============================================================================
CREATE TABLE tenant_settings (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  key         text NOT NULL,
  value       jsonb NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, key)
);

CREATE INDEX idx_tenant_settings_tenant ON tenant_settings (tenant_id);

-- ============================================================================
-- 19. SESSIONS (for admin/super-admin impersonation tracking)
-- ============================================================================
CREATE TABLE sessions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id),
  user_id         uuid NOT NULL REFERENCES users(id),
  role            text NOT NULL CHECK (role IN ('customer', 'barber', 'admin', 'super_admin')),
  impersonated_by uuid,                   -- set when super_admin views as tenant
  token_hash      text NOT NULL UNIQUE,
  expires_at      timestamptz NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  last_used_at    timestamptz NOT NULL DEFAULT now(),

  CHECK (expires_at > created_at)
);

CREATE INDEX idx_sessions_user ON sessions (user_id, expires_at DESC);
CREATE INDEX idx_sessions_token ON sessions (token_hash);
CREATE INDEX idx_sessions_tenant ON sessions (tenant_id);
CREATE INDEX idx_sessions_impersonation ON sessions (impersonated_by)
  WHERE impersonated_by IS NOT NULL;

-- ============================================================================
-- 20. BOOKING LOG (for analytics — lightweight event stream)
-- ============================================================================
CREATE TABLE booking_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id),
  appointment_id  uuid REFERENCES appointments(id),
  event           text NOT NULL,  -- 'viewed_slots', 'clicked_slot', 'started_booking', 'completed', 'cancelled', 'no_show'
  barber_id       uuid REFERENCES barbers(id),
  customer_id     uuid REFERENCES users(id),
  metadata        jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_booking_log_tenant ON booking_log (tenant_id, created_at DESC);
CREATE INDEX idx_booking_log_event ON booking_log (event, created_at DESC);

-- ============================================================================
-- 21. CANCELLATION POLICY DOCUMENT (SSoT for deposit/cancel rules)
-- ============================================================================
CREATE TABLE policies (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  slug        text NOT NULL,             -- 'cancellation', 'deposit', 'recut-guarantee'
  title       text NOT NULL,
  body_md     text NOT NULL,             -- Markdown body
  version     integer NOT NULL DEFAULT 1,
  is_active   boolean NOT NULL DEFAULT true,
  published_at timestamptz NOT NULL DEFAULT now(),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, slug, version)
);

CREATE INDEX idx_policies_tenant ON policies (tenant_id, slug, is_active)
  WHERE is_active = true;

-- ============================================================================
-- ROW-LEVEL SECURITY (RLS)
-- ============================================================================

-- Enable RLS on all tenant-scoped tables
ALTER TABLE users              ENABLE ROW LEVEL SECURITY;
ALTER TABLE barbers            ENABLE ROW LEVEL SECURITY;
ALTER TABLE services           ENABLE ROW LEVEL SECURITY;
ALTER TABLE recurring_rules    ENABLE ROW LEVEL SECURITY;
ALTER TABLE time_off           ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments       ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments           ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews            ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_helpfulness ENABLE ROW LEVEL SECURITY;
ALTER TABLE looks              ENABLE ROW LEVEL SECURITY;
ALTER TABLE gift_cards         ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_points     ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE referrals          ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_ledger     ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log          ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_settings    ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions           ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_log        ENABLE ROW LEVEL SECURITY;
ALTER TABLE policies           ENABLE ROW LEVEL SECURITY;

-- Tenant isolation policy: each role can only see rows for its own tenant.
-- The current tenant_id is set via `SET LOCAL app.tenant_id` at connection
-- time by the API gateway after JWT verification.

-- Generic tenant isolation — applies to every tenant-scoped table
CREATE POLICY tenant_isolation_select ON users
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON users
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON users
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Repeat for barbers
CREATE POLICY tenant_isolation_select ON barbers
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON barbers
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON barbers
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Services
CREATE POLICY tenant_isolation_select ON services
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON services
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON services
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Appointments
CREATE POLICY tenant_isolation_select ON appointments
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON appointments
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON appointments
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Payments
CREATE POLICY tenant_isolation_select ON payments
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON payments
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON payments
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Reviews
CREATE POLICY tenant_isolation_select ON reviews
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON reviews
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON reviews
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Looks
CREATE POLICY tenant_isolation_select ON looks
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON looks
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON looks
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Recurring rules
CREATE POLICY tenant_isolation_select ON recurring_rules
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON recurring_rules
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON recurring_rules
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Time off
CREATE POLICY tenant_isolation_select ON time_off
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON time_off
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON time_off
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Gift cards
CREATE POLICY tenant_isolation_select ON gift_cards
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON gift_cards
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON gift_cards
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Loyalty points
CREATE POLICY tenant_isolation_select ON loyalty_points
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON loyalty_points
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON loyalty_points
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Referrals
CREATE POLICY tenant_isolation_select ON referrals
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON referrals
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON referrals
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Webhook ledger (select only — inserts happen via system)
CREATE POLICY tenant_isolation_select ON webhook_ledger
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Audit log (select only by tenant)
CREATE POLICY tenant_isolation_select ON audit_log
  FOR SELECT USING (
    tenant_id = current_setting('app.tenant_id')::uuid
    OR current_setting('app.role') = 'super_admin'
  );

-- Tenant settings
CREATE POLICY tenant_isolation_select ON tenant_settings
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON tenant_settings
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Sessions
CREATE POLICY tenant_isolation_select ON sessions
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON sessions
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);

-- Booking log
CREATE POLICY tenant_isolation_select ON booking_log
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Policies
CREATE POLICY tenant_isolation_select ON policies
  FOR SELECT USING (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_insert ON policies
  FOR INSERT WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);
CREATE POLICY tenant_isolation_update ON policies
  FOR UPDATE USING (tenant_id = current_setting('app.tenant_id')::uuid);

-- Super-admin bypass: allow super_admin role to read all tenants
-- (applied at connection time by setting app.role = 'super_admin')
CREATE POLICY super_admin_bypass ON barbers
  FOR ALL USING (
    current_setting('app.role') = 'super_admin'
    OR tenant_id = current_setting('app.tenant_id')::uuid
  );

-- ============================================================================
-- APPEND-ONLY AUDIT LOG ENFORCEMENT
-- ============================================================================
-- The audit_log is immutable after INSERT. Only super_admin can UPDATE/DELETE.
REVOKE UPDATE, DELETE ON audit_log FROM public;
REVOKE UPDATE, DELETE ON audit_log FROM authenticated;

-- Create a specific role for super-admin if needed
-- GRANT UPDATE, DELETE ON audit_log TO super_admin_role;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Generate slot grid for a barber on a given date
CREATE OR REPLACE FUNCTION get_slots_for_date(
  p_barber_id uuid,
  p_date date,
  p_tenant_id uuid
)
RETURNS TABLE (
  slot_start   timestamptz,
  slot_end     timestamptz,
  is_available boolean
)
LANGUAGE sql STABLE
AS $$
  WITH time_slots AS (
    -- Generate 30-min slots from active recurring rules
    SELECT
      (p_date + r.start_time::time)::timestamptz AT TIME ZONE t.timezone AS slot_start,
      (p_date + r.start_time::time + interval '30 minutes')::timestamptz AT TIME ZONE t.timezone AS slot_end
    FROM barbers b
    JOIN tenants t ON t.id = b.tenant_id
    JOIN recurring_rules r ON r.barber_id = b.id
    WHERE b.id = p_barber_id
      AND b.tenant_id = p_tenant_id
      AND r.is_active = true
      AND EXTRACT(DOW FROM p_date) = r.day_of_week
      AND p_date >= CURRENT_DATE
  ),
  booked_slots AS (
    SELECT a.starts_at, a.ends_at
    FROM appointments a
    WHERE a.barber_id = p_barber_id
      AND a.state NOT IN ('cancelled-by-client', 'cancelled-by-provider', 'cancelled-by-system', 'no-show')
      AND a.starts_at::date = p_date
  ),
  time_off_blocks AS (
    SELECT toff.starts_at, toff.ends_at
    FROM time_off toff
    WHERE toff.barber_id = p_barber_id
      AND toff.starts_at::date <= p_date
      AND toff.ends_at::date >= p_date
  )
  SELECT
    ts.slot_start,
    ts.slot_end,
    NOT EXISTS (
      SELECT 1 FROM booked_slots bs
      WHERE tstzrange(ts.slot_start, ts.slot_end, '[)') && tstzrange(bs.starts_at, bs.ends_at, '[)')
    )
    AND NOT EXISTS (
      SELECT 1 FROM time_off_blocks tb
      WHERE tstzrange(ts.slot_start, ts.slot_end, '[)') && tstzrange(tb.starts_at, tb.ends_at, '[)')
    ) AS is_available
  FROM time_slots ts
  JOIN tenants t ON t.id = p_tenant_id
  WHERE ts.slot_start > NOW()  -- don't show past slots
  ORDER BY ts.slot_start;
$$;

-- Reserve a slot (atomic — relies on EXCLUDE constraint for race safety)
CREATE OR REPLACE FUNCTION reserve_slot(
  p_tenant_id       uuid,
  p_barber_id       uuid,
  p_customer_id     uuid,
  p_service_id      uuid,
  p_starts_at       timestamptz,
  p_party_size      smallint DEFAULT 1,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_service_duration smallint;
  v_ends_at timestamptz;
  v_appointment_id uuid;
BEGIN
  -- Get service duration
  SELECT duration_min INTO v_service_duration
  FROM services
  WHERE id = p_service_id AND tenant_id = p_tenant_id;

  IF v_service_duration IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'service-not-found');
  END IF;

  v_ends_at := p_starts_at + (v_service_duration || ' minutes')::interval;

  -- Check idempotency
  IF p_idempotency_key IS NOT NULL THEN
    SELECT id INTO v_appointment_id
    FROM appointments
    WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object('ok', true, 'appointment_id', v_appointment_id, 'idempotent', true);
    END IF;
  END IF;

  -- INSERT — the EXCLUDE constraint guards against overlapping slots
  INSERT INTO appointments (
    tenant_id, barber_id, customer_id, service_id,
    starts_at, ends_at, state, held_until, party_size, idempotency_key
  ) VALUES (
    p_tenant_id, p_barber_id, p_customer_id, p_service_id,
    p_starts_at, v_ends_at, 'held', NOW() + interval '7 minutes',
    p_party_size, p_idempotency_key
  )
  RETURNING id INTO v_appointment_id;

  RETURN jsonb_build_object(
    'ok', true,
    'appointment_id', v_appointment_id,
    'held_until', (NOW() + interval '7 minutes')::text
  );

EXCEPTION
  WHEN SQLSTATE '23P01' THEN  -- exclusion_violation
    RETURN jsonb_build_object('ok', false, 'error', 'slot-taken');
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'error', 'duplicate-booking');
END;
$$;

-- Confirm booking after payment
CREATE OR REPLACE FUNCTION confirm_booking(
  p_appointment_id uuid,
  p_tenant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_state appointment_state;
BEGIN
  SELECT state INTO v_state
  FROM appointments
  WHERE id = p_appointment_id AND tenant_id = p_tenant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'appointment-not-found');
  END IF;

  IF v_state != 'held' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid-state', 'current', v_state);
  END IF;

  UPDATE appointments
  SET state = 'booked', held_until = NULL, updated_at = NOW()
  WHERE id = p_appointment_id AND tenant_id = p_tenant_id;

  RETURN jsonb_build_object('ok', true, 'appointment_id', p_appointment_id);
END;
$$;

-- ============================================================================
-- INDEXES SUMMARY
-- ============================================================================
-- Primary indexes defined inline with each table. Additional indexes below.

-- Full-text search on barber names and bios
CREATE INDEX idx_barbers_search ON barbers USING GIN (
  to_tsvector('english', coalesce(name, '') || ' ' || coalesce(bio, ''))
);

-- Composite lookup for slot grid queries
CREATE INDEX idx_appointments_lookup ON appointments (barber_id, starts_at, state)
  WHERE state NOT IN ('cancelled-by-client', 'cancelled-by-provider', 'cancelled-by-system', 'no-show');

-- Booking log time-range queries
CREATE INDEX idx_booking_log_barber_date ON booking_log (barber_id, created_at DESC);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-update updated_at on key tables
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER set_updated_at_tenants
  BEFORE UPDATE ON tenants FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_users
  BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_barbers
  BEFORE UPDATE ON barbers FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_services
  BEFORE UPDATE ON services FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_appointments
  BEFORE UPDATE ON appointments FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_payments
  BEFORE UPDATE ON payments FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_reviews
  BEFORE UPDATE ON reviews FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_gift_cards
  BEFORE UPDATE ON gift_cards FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_loyalty_points
  BEFORE UPDATE ON loyalty_points FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_recurring_rules
  BEFORE UPDATE ON recurring_rules FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_policies
  BEFORE UPDATE ON policies FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_tenant_settings
  BEFORE UPDATE ON tenant_settings FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at_sessions
  BEFORE UPDATE ON sessions FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMIT;
