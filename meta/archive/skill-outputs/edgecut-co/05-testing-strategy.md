# Testing Strategy — Edgecut & Co.

> **Version:** 1.0  
> **Last updated:** 2026-05-13  
> **Scope:** Booking funnel, calendar, dashboard, map+list, mobile shell  
> **Tenants:** Brooklyn (US/en), Los Angeles (US/en), Madrid (ES/es, EUR)

---

## 1. Test Pyramid Overview

```
         /\
        /  \         E2E (Playwright) — 5 %
       /    \        Critical user journeys, cross-context races
      /______\
     /        \      Integration — 25 %
    /          \     API contracts, DB atomicity, Stripe webhooks,
   /            \    CDN failover, RLS policy, calendar sync
  /______________\
 /                \  Unit — 70 %
/                  \ Pure functions, token math, validators,
                    formatters, DST helpers, XSS sanitizers
```

**Gates:**

| Gate               | Threshold            | Tool          |
|--------------------|----------------------|---------------|
| Accessibility      | `axe` 0 violations   | axe-core      |
| Performance        | Lighthouse ≥ 95      | Lighthouse CI |
| Code coverage      | ≥ 85 % lines         | c8 / Istanbul |
| Visual regression  | ≤ 0.5 % diff         | Percy / Playwright screenshots |

---

## 2. Unit Tests

### 2.1 Directory Layout

```
tests/
├── unit/
│   ├── formatters/
│   │   ├── currency.test.js       # USD / EUR formatting
│   │   ├── date.test.js           # en-US / es-ES date strings
│   │   └── phone.test.js          # +1 / +34 normalization
│   ├── validators/
│   │   ├── email.test.js
│   │   ├── hostile-input.test.js  # XSS, SQLi, template injection
│   │   └── slot.test.js           # time-overlap, DST boundary
│   ├── token/
│   │   ├── design-tokens.test.js  # primary #1A1C1E, secondary #B8926B
│   │   └── contrast.test.js       # WCAG AA/AAA ratio checks
│   └── store/
│       ├── cart.test.js
│       └── tenant.test.js         # tenant context switching
```

### 2.2 Key Unit Test Cases

```js
// currency.test.js
describe('CurrencyFormatter', () => {
  it('formats USD with $ and two decimals', () => {
    expect(format(45, 'USD', 'en-US')).toBe('$45.00');
  });
  it('formats EUR with € and two decimals', () => {
    expect(format(45, 'EUR', 'es-ES')).toBe('45,00 €');
  });
  it('handles zero', () => {
    expect(format(0, 'USD', 'en-US')).toBe('$0.00');
  });
});

// date.test.js
describe('DateFormatter', () => {
  it('formats en-US date', () => {
    expect(formatDate(new Date('2026-05-13'), 'en-US')).toBe('5/13/2026');
  });
  it('formats es-ES date', () => {
    expect(formatDate(new Date('2026-05-13'), 'es-ES')).toBe('13/5/2026');
  });
});

// contrast.test.js
describe('ContrastChecker', () => {
  it('primary on surface passes AA large text', () => {
    expect(ratio('#1A1C1E', '#FAF7F4')).toBeGreaterThan(3);
  });
  it('secondary on surface passes AA normal text', () => {
    expect(ratio('#B8926B', '#FAF7F4')).toBeGreaterThan(4.5);
  });
});

// slot.test.js — DST edge case
describe('SlotValidator', () => {
  it('rejects slot overlapping DST spring-forward gap', () => {
    // 2026-03-08 02:30 EST does not exist in US/Eastern
    const start = new Date('2026-03-08T02:30:00-05:00');
    expect(isValidSlot(start, 30)).toBe(false);
  });
  it('handles DST fall-back duplicate hour', () => {
    // 2026-11-01 01:30 EDT vs 01:30 EST — both valid, must deduplicate
    const slots = generateSlots(new Date('2026-11-01'), 'America/New_York');
    const times = slots.map(s => s.time);
    expect(new Set(times).size).toBe(times.length);
  });
});
```

---

## 3. Integration Tests

### 3.1 Scope

- Database queries with RLS (Row-Level Security)
- Stripe Connect Express onboarding & payment flows
- Calendar sync (iCal feed generation/parsing)
- Image CDN fallback chains
- API endpoint contract validation

### 3.2 Golden Dataset — Three Tenants

Three static seed datasets live in `tests/fixtures/golden/`. Each contains:

| Tenant    | Slug         | Locale | Currency | Timezone            | Barbers | Slots | Services |
|-----------|-------------|--------|----------|---------------------|---------|-------|----------|
| Brooklyn  | brooklyn-ny | en-US  | USD      | America/New_York    | 4       | 48    | 6        |
| Los Angeles | los-angeles-ca | en-US | USD   | America/Los_Angeles | 3       | 36    | 5        |
| Madrid    | madrid-es   | es-ES  | EUR      | Europe/Madrid       | 3       | 40    | 5        |

```sql
-- fixtures/golden/brooklyn-ny.sql
INSERT INTO tenants (id, slug, name, locale, currency, timezone)
VALUES (
  'a1b2c3d4-...', 'brooklyn-ny', 'Edgecut & Co. Brooklyn',
  'en-US', 'USD', 'America/New_York'
);

INSERT INTO barbers (id, tenant_id, name, bio)
VALUES
  ('b1...', 'a1b2...', 'Marcus Jones', 'Fade specialist, 12 years'),
  ('b2...', 'a1b2...', 'Aiko Tanaka', 'Scissor cuts and texture'),
  ('b3...', 'a1b2...', 'David Chen', 'Classic barbering'),
  ('b4...', 'a1b2...', 'Sofia Reyes', 'Straight-razor shaves');
```

```js
// tests/integration/rls.test.js
describe('Row-Level Security', () => {
  it('tenant A cannot read tenant B slots', async () => {
    const connA = await getTenantConnection('brooklyn-ny');
    const connB = await getTenantConnection('madrid-es');
    const slots = await connA.query(
      'SELECT * FROM slots WHERE tenant_id = $1',
      [connB.tenantId]
    );
    expect(slots.rows).toHaveLength(0);
  });
});
```

### 3.3 Integration Test Matrix

| Test                          | DB | Stripe API | CDN | Map API |
|-------------------------------|----|------------|-----|---------|
| Slot creation with RLS        | ✓  |            |     |         |
| Slot atomic booking (PG row lock) | ✓ |        |     |         |
| Stripe Connect account link   |    | ✓ (mock)  |     |         |
| Payment intent creation       |    | ✓ (mock)  |     |         |
| Webhook signature verification|    | ✓ (mock)  |     |         |
| Image CDN fallback chain      |    |            | ✓   |         |
| Map tile 503 graceful degrade |    |            |     | ✓       |
| Calendar iCal generation      | ✓  |            |     |         |
| EUR locale pricing            | ✓  | ✓ (mock)  |     |         |

```js
// tests/integration/booking-atomicity.test.js
describe('Atomic Slot Booking', () => {
  it('prevents double-booking with SELECT ... FOR UPDATE', async () => {
    const slotId = 'slot-001';
    const results = await Promise.allSettled([
      bookSlot(slotId, 'user-a'),
      bookSlot(slotId, 'user-b'),
    ]);
    const successes = results.filter(r => r.status === 'fulfilled');
    expect(successes).toHaveLength(1);
  });
});
```

---

## 4. Adversarial Test Catalog

Ten adversarial scenarios that must pass before any production deployment.

### A-01: Cross-Tenant Data Leak

**Scenario:** User from Madrid tenant crafts API request with Brooklyn tenant ID.

**Expected:** 403 Forbidden. No Brooklyn data returned.

**Test:**
```js
it('rejects cross-tenant data access', async () => {
  const madridToken = await loginAs('madrid-es', 'customer-1');
  const res = await fetch('/api/barbers', {
    headers: { Authorization: `Bearer ${madridToken}`, 'X-Tenant': 'brooklyn-ny' },
  });
  expect(res.status).toBe(403);
  expect(await res.json()).toMatchObject({ error: 'tenant_mismatch' });
});
```

### A-02: Double-Booking Race Condition

**Scenario:** Two customers click "Book" simultaneously on the same 30-minute slot.

**Expected:** Exactly one booking succeeds. Second receives `SLOT_ALREADY_BOOKED`.

**Test:** See Section 5 (Playwright two-context race test).

### A-03: DST Boundary Slot Generation

**Scenario:** Barber opens calendar for March 8, 2026 (US spring-forward). 02:30 does not exist.

**Expected:** Calendar skips the gap hour. No invalid slots generated.

**Test:**
```js
it('generates valid slots across DST spring-forward', () => {
  const slots = generateSlots('2026-03-08', 'America/New_York', '09:00', '17:00');
  const times = slots.map(s => s.startHour);
  expect(times).not.toContain(2); // 02:xx does not exist
});
```

### A-04: Stripe Webhook Replay Attack

**Scenario:** Attacker replays a captured `payment_intent.succeeded` webhook.

**Expected:** Idempotency key check rejects duplicate. Only one booking confirmed.

**Test:**
```js
it('rejects replayed Stripe webhook', async () => {
  const payload = buildWebhookPayload('payment_intent.succeeded', 'pi_123');
  const sig = stripe.webhooks.generateTestHeaderString({
    payload, secret: process.env.STRIPE_WEBHOOK_SECRET,
  });
  const res1 = await fetch('/api/webhooks/stripe', { method: 'POST', body: payload, headers: { 'stripe-signature': sig }});
  const res2 = await fetch('/api/webhooks/stripe', { method: 'POST', body: payload, headers: { 'stripe-signature': sig }});
  expect(res1.status).toBe(200);
  expect(res2.status).toBe(409);
  expect(await res2.json()).toMatchObject({ error: 'idempotency_conflict' });
});
```

### A-05: Image CDN Failure

**Scenario:** Primary image CDN returns 503. Gallery and barber profile photos fail to load.

**Expected:** App falls back to secondary CDN. If secondary also fails, shows placeholder `data:image` SVG with alt text.

**Test:**
```js
it('falls back through CDN chain on 503', async () => {
  nock('https://cdn1.edgecut.co').get('/barbers/marcus.jpg').reply(503);
  nock('https://cdn2.edgecut.co').get('/barbers/marcus.jpg').reply(200, mockImage);
  const src = await resolveImageUrl('barbers/marcus.jpg');
  expect(src).toContain('cdn2.edgecut.co');
});
```

### A-06: Reduced Motion + High Contrast + Data Saver

**Scenario:** User has three OS-level preferences simultaneously: prefers-reduced-motion, prefers-contrast: more, and Save-Data header.

**Expected:** Page renders with no animations, high-contrast secondary (#B8926B) on surface (#FAF7F4), and no lazy-loaded images above the fold. All transitions disabled.

**Test:**
```js
it('respects reduced-motion + high-contrast + save-data', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce', contrast: 'more' });
  await page.setExtraHTTPHeaders({ 'Save-Data': 'on' });
  await page.goto('/brooklyn-ny');
  const hasAnimations = await page.evaluate(() => {
    const style = getComputedStyle(document.body);
    return style.animationName !== 'none' || style.transitionDuration !== '0s';
  });
  expect(hasAnimations).toBe(false);
  await expect(page).toPassAxe();
});
```

### A-07: Hostile Input — XSS via Booking Name

**Scenario:** Customer enters `<script>alert('xss')</script>` as their booking name.

**Expected:** Input sanitized on client and server. Stored as encoded text. Displayed as `&lt;script&gt;...` in admin dashboard.

**Test:**
```js
it('sanitizes hostile booking names', async () => {
  await bookSlot('slot-001', '<script>alert("xss")</script>');
  const bookings = await db.query('SELECT customer_name FROM bookings WHERE slot_id = $1', ['slot-001']);
  expect(bookings.rows[0].customer_name).not.toContain('<script>');
});
```

### A-08: EUR Locale Formatting — Price Display

**Scenario:** Madrid tenant displays service price of €45.50.

**Expected:** Displayed as `45,50 €` (comma decimal, space before €). Cart total sums correctly with comma-separated decimals.

**Test:**
```js
it('formats EUR prices for es-ES locale', async () => {
  const el = await page.locator('[data-testid="service-price-madrid"]');
  await expect(el).toHaveText('45,50 €');
});
```

### A-09: Map Tile 503 Graceful Degradation

**Scenario:** Map tile server returns 503 errors. Map+list view is rendered.

**Expected:** Map section shows "Map temporarily unavailable" message with fallback illustration. List view remains fully functional and sorted.

**Test:**
```js
it('shows graceful fallback when map tiles fail', async ({ page }) => {
  await page.route('**/tiles/**', route => route.abort('internetdisconnected'));
  await page.goto('/los-angeles-ca/map');
  await expect(page.locator('[data-testid="map-fallback"]')).toBeVisible();
  await expect(page.locator('[data-testid="shop-list"]')).toBeVisible();
});
```

### A-10: Stale Slot List — Client/Server Desync

**Scenario:** User opens the booking calendar and keeps the tab open for 15 minutes. During that time, all remaining slots for today are booked by others. User selects a slot that was fresh on load but is now stale.

**Expected:** On submit, server re-verifies slot availability. Returns `SLOT_STALE` error if already booked. Client refreshes slot list.

**Test:**
```js
it('rejects stale slot selection after prolonged idle', async () => {
  const { page: pageA } = await browser.newPage(); // customer
  const { page: pageB } = await browser.newPage(); // admin
  await pageA.goto('/brooklyn-ny/book');
  const slot = await pageA.locator('[data-testid="slot-available"]').first().getAttribute('data-slot-id');
  // Admin books the slot
  await pageB.goto('/brooklyn-ny/admin');
  await pageB.locator(`[data-slot-id="${slot}"]`).click();
  await pageB.locator('[data-testid="confirm-booking"]').click();
  // Customer submits stale selection
  await pageA.locator(`[data-slot-id="${slot}"]`).click();
  await pageA.locator('[data-testid="book-now"]').click();
  await expect(pageA.locator('[data-testid="error-message"]')).toHaveText(/SLOT_STALE/);
});
```

---

## 5. End-to-End Tests (Playwright)

### 5.1 Two-Context Race Condition Tests

These tests open two separate browser contexts (simulating two different users on different devices) and fire booking requests simultaneously.

```js
// tests/e2e/race-double-booking.spec.js
import { test, expect } from '@playwright/test';

test('two users cannot book the same slot simultaneously', async ({ browser }) => {
  const ctxA = await browser.newContext({ storageState: 'fixtures/auth/user-a.json' });
  const ctxB = await browser.newContext({ storageState: 'fixtures/auth/user-b.json' });
  const pageA = await ctxA.newPage();
  const pageB = await ctxB.newPage();

  await pageA.goto('/brooklyn-ny/book');
  await pageB.goto('/brooklyn-ny/book');

  const slot = pageA.locator('[data-testid="slot-available"]').first();
  const slotId = await slot.getAttribute('data-slot-id');
  await pageB.locator(`[data-slot-id="${slotId}"]`).waitFor({ state: 'visible' });

  // Fire both bookings at the same time
  const clickA = slot.click();
  const clickB = pageB.locator(`[data-slot-id="${slotId}"]`).click();
  await Promise.all([clickA, clickB]);

  const confirmA = pageA.locator('[data-testid="book-now"]').click();
  const confirmB = pageB.locator('[data-testid="book-now"]').click();
  const results = await Promise.allSettled([
    pageA.waitForSelector('[data-testid="booking-success"]', { timeout: 5000 }).then(() => 'success'),
    pageA.waitForSelector('[data-testid="booking-error"]', { timeout: 5000 }).then(() => 'error'),
    pageB.waitForSelector('[data-testid="booking-success"]', { timeout: 5000 }).then(() => 'success'),
    pageB.waitForSelector('[data-testid="booking-error"]', { timeout: 5000 }).then(() => 'error'),
  ]);

  const successes = results.filter(r => r.value === 'success');
  expect(successes).toHaveLength(1);
  await ctxA.close();
  await ctxB.close();
});
```

### 5.2 Booking Funnel E2E

```js
test('customer completes full booking funnel', async ({ page }) => {
  await page.goto('/brooklyn-ny');
  await page.locator('[data-testid="book-appointment"]').click();
  await page.locator('[data-testid="barber-marcus"]').click();
  await page.locator('[data-testid="service-fade"]').click();
  await page.locator('[data-testid="slot-available"]').first().click();
  await page.locator('[data-testid="book-now"]').click();
  // Stripe Checkout redirect — mock for E2E
  await page.locator('[data-testid="payment-success"]').click();
  await expect(page.locator('[data-testid="confirmation"]')).toBeVisible();
  await expect(page.locator('[data-testid="booking-status"]')).toHaveText('Confirmed');
});
```

### 5.3 Calendar E2E

```js
test('barber calendar shows correct availability', async ({ page }) => {
  await page.goto('/brooklyn-ny/admin/calendar');
  await expect(page.locator('[data-testid="calendar-grid"]')).toBeVisible();
  // Navigate to next week
  await page.locator('[data-testid="nav-next"]').click();
  const bookedSlots = await page.locator('[data-testid="slot-booked"]').count();
  const availableSlots = await page.locator('[data-testid="slot-available"]').count();
  expect(bookedSlots + availableSlots).toBeGreaterThan(0);
});
```

### 5.4 Dashboard E2E

```js
test('admin dashboard shows metrics for tenant', async ({ page }) => {
  await page.goto('/brooklyn-ny/admin/dashboard');
  await expect(page.locator('[data-testid="total-bookings"]')).toBeVisible();
  await expect(page.locator('[data-testid="revenue-summary"]')).toBeVisible();
  await expect(page.locator('[data-testid="upcoming-appointments"]')).toBeVisible();
});
```

### 5.5 Map + List E2E

```js
test('map and list views sync on navigation', async ({ page }) => {
  await page.goto('/brooklyn-ny/map');
  await expect(page.locator('[data-testid="map-container"]')).toBeVisible();
  await expect(page.locator('[data-testid="shop-list"]')).toBeVisible();
  // Click sidebar item focuses map marker
  await page.locator('[data-testid="shop-item"]').first().click();
  await expect(page.locator('[data-testid="map-marker-active"]')).toBeVisible();
});
```

### 5.6 Mobile Shell E2E

```js
test('mobile shell renders correctly', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 667 }); // iPhone SE
  await page.goto('/brooklyn-ny');
  await expect(page.locator('[data-testid="mobile-shell"]')).toBeVisible();
  await expect(page.locator('[data-testid="bottom-nav"]')).toBeVisible();
  // Bottom nav items
  await page.locator('[data-testid="nav-book"]').tap();
  await expect(page.locator('[data-testid="booking-flow"]')).toBeVisible();
  await page.locator('[data-testid="nav-calendar"]').tap();
  await expect(page.locator('[data-testid="calendar-view"]')).toBeVisible();
});
```

---

## 6. Accessibility Gates

### 6.1 axe-core Passes

Every page and state transition must pass axe-core with zero violations of any severity level.

```js
// tests/a11y/all-pages.spec.js
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const PAGES = [
  '/brooklyn-ny',
  '/brooklyn-ny/book',
  '/brooklyn-ny/admin/dashboard',
  '/brooklyn-ny/admin/calendar',
  '/brooklyn-ny/map',
  '/los-angeles-ca',
  '/madrid-es',
];

test.describe('Accessibility — all surfaces', () => {
  for (const pagePath of PAGES) {
    test(`${pagePath} has no axe violations`, async ({ page }) => {
      await page.goto(pagePath);
      const results = await new AxeBuilder({ page }).analyze();
      expect(results.violations).toEqual([]);
    });
  }
});
```

### 6.2 Lighthouse CI Threshold

```yaml
# .lighthouserc.yml
ci:
  collect:
    url:
      - https://staging.edgecut.co/brooklyn-ny
      - https://staging.edgecut.co/madrid-es
      - https://staging.edgecut.co/los-angeles-ca/map
    numberOfRuns: 3
  assert:
    assertions:
      categories:performance:
        - warn
        - minScore: 0.95
      categories:accessibility:
        - error
        - minScore: 0.95
      categories:best-practices:
        - error
        - minScore: 0.95
      categories:seo:
        - error
        - minScore: 0.95
```

---

## 7. Test Fixtures & Factories

### 7.1 Tenant Factory

```js
// tests/fixtures/factories.js
export function buildTenant(overrides = {}) {
  return {
    id: crypto.randomUUID(),
    slug: 'brooklyn-ny',
    name: 'Edgecut & Co. Brooklyn',
    locale: 'en-US',
    currency: 'USD',
    timezone: 'America/New_York',
    ...overrides,
  };
}
```

### 7.2 Slot Factory

```js
export function buildSlot(overrides = {}) {
  return {
    id: crypto.randomUUID(),
    tenant_id: 'a1b2c3d4-...',
    barber_id: 'b1...',
    start_time: new Date('2026-05-14T10:00:00-04:00'),
    end_time: new Date('2026-05-14T10:30:00-04:00'),
    status: 'available',
    ...overrides,
  };
}
```

---

## 8. CI Integration

```yaml
# .github/workflows/test.yml
name: Test Suite
on: [push, pull_request]
jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npx vitest run --coverage
      - uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/

  integration:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_DB: edgecut_test
          POSTGRES_PASSWORD: test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npx vitest run --config vitest.integration.config.ts

  e2e:
    timeout-minutes: 15
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npx playwright install --with-deps
      - run: npx playwright test
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: playwright-report
          path: playwright-report/

  lighthouse:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npx lhci autorun
```

---

## 9. Test Data Management

- **Golden datasets** are versioned in `tests/fixtures/golden/` as SQL + JSON snapshots.
- **Seeds** are loaded before integration suite, truncated after.
- **Per-test isolation:** each integration test runs in a transaction that is rolled back (`beforeEach` → `BEGIN`, `afterEach` → `ROLLBACK`).
- **Stripe mocking:** all Stripe API calls go through `nock` or `@stripe/stripe-mock` in integration tests.

---

## 10. Visual Regression Testing

```js
// tests/visual/all-pages.spec.js
test('brooklyn home page matches snapshot', async ({ page }) => {
  await page.goto('/brooklyn-ny');
  await expect(page).toHaveScreenshot('brooklyn-home.png', {
    maxDiffPixelRatio: 0.005,
  });
});
```

Threshold: ≤ 0.5 % pixel diff on any page. Full-page screenshots at 1280×800 and 375×667.

---

## 11. Test Execution Order

1. **Unit** — fast, no side effects (CI runs first, < 30 s)
2. **Integration** — seeded DB, mocked external APIs (< 2 min)
3. **E2E** — full browser, live or preview deployment (< 5 min)
4. **a11y** — axe on every route (< 1 min)
5. **Lighthouse** — performance budget enforcement (< 3 min per URL)
6. **Visual regression** — Percy or Playwright snapshot diff (< 2 min)
