# Incident Runbook — Edgecut & Co.

> **Version:** 1.0  
> **Last updated:** 2026-05-13  
> **Severity levels:** SEV-1 (critical), SEV-2 (major), SEV-3 (minor)  
> **On-call rotation:** #edgecut-oncall (PagerDuty schedule)  
> **Escalation path:** Engineer → Engineering Lead → CTO  

---

## Runbook Overview

| Scenario                          | Severity | Typical RTO | Typical RPO |
|-----------------------------------|----------|-------------|-------------|
| Stripe payment provider down      | SEV-1    | 30 min      | N/A         |
| Slot double-booked race condition | SEV-1    | 15 min      | 1 booking   |
| Tenant data leak suspicion        | SEV-1    | Immediate    | N/A         |

Each runbook follows the same structure:
1. Detection signals
2. Triage steps
3. Mitigation actions
4. Communication template
5. Postmortem template

---

## Scenario A: Stripe Payment Provider Down

Users cannot complete bookings because Stripe API returns 5xx or connection timeouts. Revenue stops. Bookings stuck in "payment pending" state.

### Detection Signals

| Signal                          | Source              | Threshold                  |
|---------------------------------|---------------------|----------------------------|
| `stripe.api.error_rate` spike   | Datadog / Grafana   | > 5 % in 1 min             |
| `booking.payment_pending` flood | Application metrics | > 50 pending in 5 min      |
| Stripe webhook delivery failure | Stripe Dashboard    | Any `webhook_endpoint` 4xx |
| Sentry `StripeConnectionError`  | Sentry              | > 10 in 1 min              |
| Customer support tickets        | Zendesk / Intercom  | "Can't pay" mentions spike |

### Triage Steps

```bash
# Step 1: Verify Stripe status
curl -s https://status.stripe.com | grep -i "operational"
# If not "operational", check https://status.stripe.com

# Step 2: Check Stripe API response from our servers
curl -v -X GET https://api.stripe.com/v1/ping \
  -H "Authorization: Bearer $STRIPE_SECRET_KEY" \
  -o /dev/null 2>&1 | grep -E "HTTP/|error|timeout"
# Expected: HTTP/2 200

# Step 3: Check our Stripe API key is valid
stripe login --api-key $STRIPE_SECRET_KEY 2>&1
# If invalid, rotate key immediately

# Step 4: Check Stripe Connect Express sub-merchant accounts
for tenant in "brooklyn-ny" "los-angeles-ca" "madrid-es"; do
  stripe accounts retrieve $(get_connect_account_id $tenant) 2>&1
done
# Look for "charges_enabled": false

# Step 5: Check webhook endpoint health
stripe webhook_endpoints list --limit 5
# Verify url matches production endpoint, last_success_at is recent

# Step 6: Check application logs for Stripe errors
grep "StripeError" /var/log/edgecut/application.log | tail -50
```

### Mitigation Actions

| Priority | Action                              | Owner       | ETA    |
|----------|-------------------------------------|-------------|--------|
| P0       | Enable maintenance mode (graceful)  | On-call eng | 2 min  |
| P0       | Post to #edgecut-status             | On-call eng | 1 min  |
| P1       | Switch to Stripe fallback API key   | On-call eng | 5 min  |
| P1       | Verify payment flow with test card  | QA          | 10 min |
| P2       | Contact Stripe support (if outage)  | Eng lead    | 5 min  |
| P2       | Notify barbers via email/SMS        | Customer ops| 15 min |
| P3       | Update status page                  | On-call eng | 5 min  |

**Graceful degradation mode:**
```js
// When Stripe is down, the booking flow shows:
// "We're experiencing a payment processing delay. Your card won't be charged
//  until the payment provider recovers. We'll email you a confirmation."
// Bookings are queued with status 'payment_deferred' and processed when Stripe recovers.
```

**Manual re-processing (post-recovery):**
```bash
# Reprocess all deferred bookings
./scripts/reprocess-deferred-payments.sh --since "2026-05-13T02:00:00Z"

# Monitor success rate
watch -n 5 'grep "payment_deferred" /var/log/edgecut/application.log | tail -10'
```

### Communication Template

> **INCIDENT:** SEV-1 — Stripe Payment Provider Down  
> **TIMESTAMP:** {{timestamp}} UTC  
> **AFFECTED:** All tenants (Brooklyn, LA, Madrid) — booking payments  
> **STATUS:** Investigating / Mitigating / Resolved  
>  
> We are experiencing errors from the Stripe payment API preventing customers from completing bookings. Bookings in progress are being deferred and will be processed once Stripe recovers.  
>  
> **Current impact:** {{impact_estimate}}  
> **Next update:** {{next_update_time}}  
> **On-call:** {{oncall_name}}  
> #edgecut-oncall

### Postmortem Template

```markdown
## Postmortem: Stripe Payment Provider Down — {{date}}

### Summary
[2–3 sentence overview of what happened, impact, and resolution]

### Timeline
- **{{time}}** — Alert triggered (Stripe error rate > 5 %)
- **{{time}}** — On-call acknowledged
- **{{time}}** — Determined Stripe API returning 503
- **{{time}}** — Maintenance mode enabled
- **{{time}}** — Switched to fallback API key
- **{{time}}** — Payment processing resumed
- **{{time}}** — All deferred bookings processed
- **{{time}}** — Maintenance mode disabled

### Root Cause
[What caused the Stripe API failure — upstream outage, API key rotation, rate limit, etc.]

### Impact
- **Bookings affected:** {{count}}
- **Revenue deferred:** {{amount}}
- **Revenue lost:** {{amount}}
- **Downtime duration:** {{duration}}

### Action Items
| Action                          | Owner       | Priority | Ticket     |
|---------------------------------|-------------|----------|------------|
| Add Stripe status polling       | Eng         | P1       | EC-{{num}} |
| Improve deferred queue alerting | Eng         | P2       | EC-{{num}} |
| Document manual reprocess steps | Ops         | P2       | EC-{{num}} |
| Test fallback key rotation      | QA          | P1       | EC-{{num}} |
```

---

## Scenario B: Slot Double-Booked Race Condition

Two (or more) customers each receive a booking confirmation for the same time slot with the same barber. Trust is damaged, barber schedule is corrupted.

### Detection Signals

| Signal                                | Source                    | Threshold                |
|---------------------------------------|---------------------------|--------------------------|
| Two `booking.confirmed` for same slot | Application logs / DB     | Duplicate slot_id + time |
| Barber reports "two people showed up" | Support tickets / Slack   | Any report               |
| `bookings_per_slot > 1` query result  | Database audit            | Any row                  |
| Race condition in error tracking      | Sentry — `SLOT_STALE`     | > 0                      |
| Customer complaints on social media   | Brand monitoring          | "double booked" mentions |

### Triage Steps

```bash
# Step 1: Find any double-booked slots in the last hour
psql $DATABASE_URL -c "
  SELECT slot_id, COUNT(*) as booking_count
  FROM bookings
  WHERE created_at > NOW() - INTERVAL '1 hour'
  GROUP BY slot_id
  HAVING COUNT(*) > 1;
"

# Step 2: Get details of double-booked slots
psql $DATABASE_URL -c "
  SELECT b.id, b.slot_id, b.customer_name, b.customer_email,
         b.created_at, s.start_time, s.barber_id
  FROM bookings b
  JOIN slots s ON b.slot_id = s.id
  WHERE b.slot_id IN (
    SELECT slot_id FROM bookings
    WHERE created_at > NOW() - INTERVAL '1 hour'
    GROUP BY slot_id HAVING COUNT(*) > 1
  )
  ORDER BY b.slot_id, b.created_at;
"

# Step 3: Check application logs around the double-booking time
grep "booking.confirmed" /var/log/edgecut/application.log \
  | grep "<SLOT_ID>" \
  | tail -20

# Step 4: Check if the database constraint was bypassed
psql $DATABASE_URL -c "
  SELECT conname, contype FROM pg_constraint
  WHERE conrelid = 'bookings'::regclass;
"
# Expected: UNIQUE constraint on (slot_id) — if missing, urgent!

# Step 5: Verify RLS + atomic booking in latest deployment
kubectl logs deployment/edgecut-web -n production --tail 50 | grep "SELECT.*FOR UPDATE"
```

### Mitigation Actions

| Priority | Action                                    | Owner       | ETA    |
|----------|--------------------------------------------|-------------|--------|
| P0       | Add (or re-enable) UNIQUE constraint on slot_id in bookings | On-call eng | 2 min |
| P0       | Contact affected customers                 | Customer ops| 15 min |
| P1       | Fix the race condition — verify `SELECT ... FOR UPDATE` is used | On-call eng | 30 min |
| P1       | Issue refund for the duplicate booking     | Customer ops| 5 min  |
| P2       | Notify affected barber of schedule change  | Customer ops| 10 min |
| P2       | Deploy hotfix with atomic booking          | Eng         | 1 h    |

**Immediate fix — add missing constraint:**
```sql
-- Run this first, before anything else
BEGIN;
  -- Remove duplicate bookings (keep the earliest)
  DELETE FROM bookings
  WHERE id IN (
    SELECT id FROM (
      SELECT id, ROW_NUMBER() OVER (PARTITION BY slot_id ORDER BY created_at) as rn
      FROM bookings
      WHERE slot_id IN (
        SELECT slot_id FROM bookings
        GROUP BY slot_id HAVING COUNT(*) > 1
      )
    ) dupes
    WHERE rn > 1
  );
  -- Add unique constraint to prevent future races
  ALTER TABLE bookings ADD CONSTRAINT uq_bookings_slot UNIQUE (slot_id);
COMMIT;
```

**Code fix — ensure atomic booking:**
```js
// Fix: Use SELECT ... FOR UPDATE to lock the slot row
async function bookSlotAtomic(slotId, customerInfo) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Lock the slot row — blocks concurrent transactions
    const { rows: [slot] } = await client.query(
      'SELECT * FROM slots WHERE id = $1 FOR UPDATE',
      [slotId]
    );
    if (slot.status !== 'available') {
      throw new SlotUnavailableError('SLOT_ALREADY_BOOKED');
    }
    await client.query(
      'UPDATE slots SET status = $1 WHERE id = $2',
      ['booked', slotId]
    );
    const { rows: [booking] } = await client.query(
      `INSERT INTO bookings (slot_id, customer_name, customer_email, status)
       VALUES ($1, $2, $3, 'confirmed')
       ON CONFLICT (slot_id) DO NOTHING
       RETURNING *`,
      [slotId, customerInfo.name, customerInfo.email]
    );
    if (!booking) throw new SlotUnavailableError('SLOT_ALREADY_BOOKED');
    await client.query('COMMIT');
    return booking;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
```

### Communication Template

> **INCIDENT:** SEV-1 — Slot Double-Booked Race Condition  
> **TIMESTAMP:** {{timestamp}} UTC  
> **AFFECTED:** {{tenant}} — {{barber_name}} — {{slot_time}}  
> **STATUS:** Investigating / Mitigating / Resolved  
>  
> Two customers received confirmations for the same {{slot_time}} appointment with {{barber_name}}. The race condition has been patched and a UNIQUE constraint has been applied to prevent recurrence.  
>  
> **Affected customers:** {{customer_names}}  
> **Contacted:** Yes / No  
> **Refund issued:** Yes / No  
> **Next update:** {{next_update_time}}  
> **On-call:** {{oncall_name}}

### Postmortem Template

```markdown
## Postmortem: Slot Double-Booked Race Condition — {{date}}

### Summary
[2–3 sentence overview]

### Timeline
- **{{time}}** — Customer support ticket received
- **{{time}}** — DB query confirmed double-booking
- **{{time}}** — UNIQUE constraint applied
- **{{time}}** — Affected customers contacted
- **{{time}}** — Hotfix deployed (atomic booking with FOR UPDATE)
- **{{time}}** — Monitoring confirmed no further duplicates

### Root Cause
The `SELECT ... FOR UPDATE` row lock was missing from the booking transaction. Two concurrent requests read the slot as "available" before either wrote the booking. A UNIQUE constraint on `bookings.slot_id` also did not exist as a safety net.

### Impact
- **Duplicate bookings:** {{count}}
- **Customers affected:** {{count}}
- **Refunded amount:** {{amount}}
- **Barbers affected:** {{count}}

### Action Items
| Action                                  | Owner       | Priority | Ticket     |
|-----------------------------------------|-------------|----------|------------|
| Add UNIQUE constraint to bookings table | DBA         | P0       | EC-{{num}} |
| Fix atomic booking (FOR UPDATE)         | Eng         | P0       | EC-{{num}} |
| Add integration test for race condition | QA          | P1       | EC-{{num}} |
| Add DB constraint monitoring            | Ops         | P2       | EC-{{num}} |
| Review all write transactions for locks | Eng         | P2       | EC-{{num}} |
```

---

## Scenario C: Tenant Data Leak Suspicion

Suspicion that data from one tenant (e.g., Madrid customers) was exposed to another tenant (e.g., Brooklyn admin). Could be RLS policy gap, API bug, or misconfiguration.

### Detection Signals

| Signal                                | Source                    | Threshold                  |
|---------------------------------------|---------------------------|----------------------------|
| RLS policy audit failure              | Periodic scan             | Any tenant sees other data |
| API returns data for wrong tenant     | Manual test / automated   | Any occurrence             |
| Support: "I see another shop's data"  | Zendesk / Intercom        | Any report                 |
| Access log anomaly                    | WAF / Cloudflare          | Cross-tenant API calls     |
| Security scan flags RLS               | Vapor / SQL audit         | Missing policy on table    |
| Anonymous tip / disclosure            | Security email            | Any                        |

### Triage Steps

```bash
# Step 1: ISOLATE — Take the application offline or enable maintenance mode
# This stops any ongoing data exposure
kubectl scale deployment edgecut-web --replicas=0 -n production

# Step 2: Verify RLS is enabled on all tenant-scoped tables
psql $DATABASE_URL -c "
  SELECT relname, relrowsecurity
  FROM pg_class
  WHERE relname IN ('slots', 'bookings', 'barbers', 'services', 'tenants')
  ORDER BY relname;
"
# Expected: relrowsecurity = true for all

# Step 3: Check RLS policies
psql $DATABASE_URL -c "
  SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
  FROM pg_policies
  WHERE tablename IN ('slots', 'bookings', 'barbers', 'services')
  ORDER BY tablename, policyname;
"

# Step 4: Look for missing WHERE tenant_id clause
psql $DATABASE_URL -c "
  SELECT query, calls, total_time
  FROM pg_stat_statements
  WHERE query ILIKE '%slots%' OR query ILIKE '%bookings%'
  ORDER BY calls DESC
  LIMIT 20;
"
# Manually inspect each query for tenant_id filter

# Step 5: Audit recent API access logs
grep "X-Tenant" /var/log/edgecut/access.log | awk '{print $NF}' | sort | uniq -c
# Look for requests where X-Tenant header does not match the URL path

# Step 6: Check for missing middleware
kubectl logs deployment/edgecut-web -n production --tail 100 | grep "RLS_BYPASS"
# If any bypass detected, this is critical

# Step 7: Check Stripe Connect account isolation
for tenant in "brooklyn-ny" "los-angeles-ca" "madrid-es"; do
  stripe accounts retrieve $(get_connect_account_id $tenant) 2>&1 \
    | grep -E "id|email|charges_enabled"
done
# Ensure each account is isolated
```

### Mitigation Actions

| Priority | Action                                         | Owner         | ETA     |
|----------|------------------------------------------------|---------------|---------|
| P0       | Isolate application (maintenance mode / scale to 0) | On-call eng  | 1 min  |
| P0       | Revoke all active API sessions (force re-auth) | On-call eng   | 2 min   |
| P0       | Notify Security Lead and CTO                   | On-call eng   | 1 min   |
| P1       | Audit full database for cross-tenant data      | DBA + Security| 30 min  |
| P1       | Review access logs for data exfiltration       | Security      | 1 h     |
| P2       | Rotate all API keys / DB credentials           | Security      | 1 h     |
| P2       | Contact affected tenant(s)                     | Legal / Ops   | Per legal |
| P3       | Forensics — reproduce the bug in staging       | Eng           | 2 h     |
| P3       | Apply fix + deploy                             | Eng           | 1 h     |

**Immediate isolation:**
```bash
# Block all user-facing traffic
kubectl scale deployment edgecut-web --replicas=0 -n production

# Block API access at ingress level
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-all-ingress
  namespace: production
spec:
  podSelector: {}
  ingress: []
EOF
```

**Force session invalidation:**
```bash
# Invalidate all JWT tokens by rotating the signing secret
kubectl set env deployment/edgecut-web JWT_SECRET=$(openssl rand -base64 32) -n production
# Note: This logs out all users — notify beforehand
```

### Communication Template

> **SECURITY INCIDENT:** SEV-1 — Potential Tenant Data Leak  
> **TIMESTAMP:** {{timestamp}} UTC  
> **AFFECTED:** {{possible_affected_tenants}}  
> **STATUS:** Isolated / Investigating / Resolved  
>  
> We have detected a potential data leak between tenants. The application has been taken offline as a precaution. An investigation is underway.  
>  
> **Current action:** Application isolated, sessions revoked, investigation in progress  
> **Next update:** {{next_update_time}}  
> **Incident commander:** {{name}}  
> **Security lead:** {{name}}  
> **Legal contact:** {{name}}  
>  
> **INTERNAL ONLY — Do not share externally without legal approval.**

### Postmortem Template

```markdown
## Postmortem: Tenant Data Leak — {{date}}

### Classification
- **Data exposure confirmed:** Yes / No / Partial
- **Data types exposed:** [e.g., customer names, emails, booking history]
- **Tenants affected:** [list]
- **Users affected:** {{count}}
- **Regulatory impact:** [GDPR / CCPA / None]

### Timeline
- **{{time}}** — Detection via {{method}}
- **{{time}}** — Application isolated
- **{{time}}** — Sessions revoked
- **{{time}}** — Security lead notified
- **{{time}}** — Root cause identified
- **{{time}}** — Fix deployed
- **{{time}}** — Application restored

### Root Cause
[Detailed technical explanation — e.g., missing WHERE tenant_id clause in query, missing RLS policy on new table, API endpoint not checking X-Tenant header]

### Impact Assessment
- **Exposed records:** {{count}}
- **Exposure duration:** {{duration}}
- **Regulatory notification required:** Yes / No
- **Customer notification required:** Yes / No

### Action Items
| Action                                    | Owner         | Priority | Ticket     |
|-------------------------------------------|---------------|----------|------------|
| Add RLS policy to {{table}}               | DBA           | P0       | EC-{{num}} |
| Add middleware to validate X-Tenant header | Eng           | P0       | EC-{{num}} |
| Run full RLS audit on all tables          | Security      | P1       | EC-{{num}} |
| Add automated cross-tenant data test      | QA            | P1       | EC-{{num}} |
| Review access logs for exfiltration       | Security      | P1       | EC-{{num}} |
| Update incident response playbook         | Ops           | P2       | EC-{{num}} |
| Conduct security training for team        | Eng lead      | P2       | EC-{{num}} |
| Legal review of data exposure             | Legal         | P1       | EC-{{num}} |

### Lessons Learned
[What went well, what went wrong, what could be improved]
```
