# 09 — Email Sequences

**Brand:** Edgecut & Co. — *"Sharp lines. Honest cuts. Walk in, walk out fresh."*
**Locations:** Brooklyn (Bedford-Stuy) · LA (Silver Lake) · Madrid (Malasaña)
**Services:** $35–$95 USD/EUR
**Policies:** Deposits for cuts >$50 or parties >3. Free cancellation up to 4hrs. Deposit forfeit inside 4hrs. 7-day re-cut guarantee.

---

## 1. Welcome Sequence

| Field | Detail |
|---|---|
| **Trigger** | New account created via booking widget, walk-in QR scan, or SMS opt-in |
| **Timing** | Instant (1st email), +48h (2nd email) |

### Email 1 — Welcome & First Cut

- **Subject:** Welcome to Edgecut & Co. — your first cut is on us 🧔
- **Body:**

> Hey {{first_name}},
>
> Welcome to Edgecut & Co. You're now part of the sharpest community in {{city}}.
>
> Here's what you get as a member:
>
> • **$10 / €10 off your first cut** — use code `FIRSTCUT` at checkout
> • **Priority booking** at any of our three shops (Bedford-Stuy, Silver Lake, Malasaña)
> • **7-day re-cut guarantee** — if it's not right, we fix it free
>
> Walk in, walk out fresh.
>
> — The Edgecut team

- **CTA:** [Book Your First Cut →]() *(link to booking page)*

### Email 2 — The Edgecut Difference

- **Subject:** The honest guide to a great haircut
- **Body:**

> Hey {{first_name}},
>
> A great cut starts before the clippers come out. Here's what makes Edgecut different:
>
> **Sharp lines.** Our barbers train on classic techniques — fades, scissor work, beard sculpting — and stay current on what's new.
>
> **Honest cuts.** We'll tell you what works for your hair type and face shape, not upsell you on something that won't.
>
> **Walk in, walk out fresh.** No appointment? No problem. Walk-ins welcome at every location. Need a guaranteed slot? Book online in under 60 seconds.
>
> Ready for that first cut?
>
> — The Edgecut team

- **CTA:** [Book Now →]() *(link to booking page)*

---

## 2. Booking Confirmation

| Field | Detail |
|---|---|
| **Trigger** | Appointment successfully booked (online or in-person by staff) |
| **Timing** | Instant |

- **Subject:** Confirmed: {{service}} @ {{shop_name}} on {{date}} ✂️
- **Body:**

> Hey {{first_name}},
>
> You're locked in. Here's what you need to know:
>
> 📍 **Where:** {{shop_address}}
> 🕐 **When:** {{date}} at {{time}}
> ✂️ **Service:** {{service}}
> 💰 **Total:** {{price}} {{currency}}
> {% if deposit > 0 %}💳 **Deposit paid:** {{deposit}} {{currency}}{% endif %}
>
> **Before you arrive:**
> • Free cancellation up to **4 hours before** your slot
> • Inside 4 hours? Your deposit is forfeited — but you can reschedule with 24h+ notice
> • Running late? Call the shop and we'll do our best to fit you in
>
> **Your barber:** {{barber_name}}
>
> See you soon.
>
> — Edgecut & Co.

- **CTA:** [Add to Calendar →]() *(calendar ICS link)* · [Reschedule / Cancel →]() *(link to manage booking)*

---

## 3. Reminder Sequence

### 3a. 24-Hour Reminder

| Field | Detail |
|---|---|
| **Trigger** | Appointment is 24 hours away |
| **Timing** | 24 hours before the booking time |

- **Subject:** Tomorrow at {{time}} — {{shop_name}} | Edgecut & Co. ⏰
- **Body:**

> Hey {{first_name}},
>
> Quick heads-up — your cut is tomorrow:
>
> 📍 **{{shop_name}}** — {{shop_address}}
> 🕐 **{{time}}**
> ✂️ **{{service}}**
>
> **Need to change or cancel?** You've got until {{4hrs_before_time}} to cancel free — just use the link below.
>
> Otherwise, we'll see you there. Fresh incoming.
>
> — Edgecut & Co.

- **CTA:** [Reschedule / Cancel →]() · [View Details →]()

### 3b. 2-Hour Reminder

| Field | Detail |
|---|---|
| **Trigger** | Appointment is 2 hours away |
| **Timing** | 2 hours before the booking time |

- **Subject:** Edgecut in 2 hours — we're ready when you are 🚶
- **Body:**

> Hey {{first_name}},
>
> Your cut's in 2 hours at **{{shop_name}}**.
>
> **{{shop_address}}**
>
> 🅿️ Street parking available / Metro: {{nearest_station}}
>
> Walk in, sit down, walk out fresh. Your barber {{barber_name}} is ready for you.
>
> See you shortly.
>
> — Edgecut & Co.

- **CTA:** [Get Directions →]() *(Google Maps / Citymapper link)*

---

## 4. Win-Back Sequence (30 / 60 / 90 Days)

| Field | Detail |
|---|---|
| **Trigger** | Last visit was 30+ days ago and no future booking on file |
| **Timing** | Day 30, Day 60, Day 90 post last visit |

### Email 1 — Day 30: Miss You Already

- **Subject:** It's been a minute, {{first_name}} — come see us?
- **Body:**

> Hey {{first_name}},
>
> We noticed it's been about a month since your last cut. Fading's probably fading by now 😅
>
> Swing by any of our shops — no appointment needed. Or book ahead in 30 seconds.
>
> **Pro tip:** First Thursday of every month is **Fresh Start Day** — $5 / €5 off any haircut.
>
> — Edgecut & Co.

- **CTA:** [Book Your Next Cut →]()

### Email 2 — Day 60: Something New?

- **Subject:** New styles dropping at {{city}} — just saying
- **Body:**

> Hey {{first_name}},
>
> Your barber {{last_barber_name}} has been training on new techniques — textured crops, modern mullets, skin fades with hard parts. If you've been thinking about switching it up, now's the time.
>
> And remember: **7-day re-cut guarantee** — if you don't love it, we fix it free.
>
> Walk in or book online.
>
> — Edgecut & Co.

- **CTA:** [Browse Styles →]() *(link to gallery / services page)* · [Book Now →]()

### Email 3 — Day 90: Last Call (with Incentive)

- **Subject:** We miss you — here's $15 / €15 on us
- **Body:**

> Hey {{first_name}},
>
> It's been three months. Honestly? That's too long.
>
> Come back and get $15 / €15 off your next cut. Use code `COMEBACK15` — valid for 14 days at any Edgecut location.
>
> No strings. Just a great haircut from people who care about getting it right.
>
> Walk in, walk out fresh.
>
> — The Edgecut team

- **CTA:** [Claim Your $15 / €15 Off →]()

---

## 5. Referral Sequence

| Field | Detail |
|---|---|
| **Trigger** | Customer completes a booking (post-cut or confirmation) — or clicks "Refer a Friend" in-app/in-email |
| **Timing** | Sent 24h after the cut is complete |

- **Subject:** Bring a friend, both get $10 / €10 off — Edgecut & Co.
- **Body:**

> Hey {{first_name}},
>
> You know that feeling when you walk out of Edgecut looking sharp af? Share it.
>
> **Refer a friend** — they get $10 / €10 off their first cut, and so do you. Stackable, no limit.
>
> How it works:
> 1. Share your unique referral link below
> 2. Friend books and uses code {{referral_code}} at checkout
> 3. You both save on your next cut
>
> Your referral link: `{{referral_url}}`
> Your code: **{{referral_code}}**
>
> Good cuts are better with good company.
>
> — Edgecut & Co.

- **CTA:** [Share Your Link →]() *(pre-populated social / SMS share)* · [Copy Code]()

---

## 6. Post-Cut Survey

| Field | Detail |
|---|---|
| **Trigger** | 4 hours after appointment end time |
| **Timing** | +4h post-cut |

- **Subject:** How'd we do, {{first_name}}? Rate your cut ⭐
- **Body:**

> Hey {{first_name}},
>
> You just got cut at {{shop_name}} with {{barber_name}}. How was it?
>
> **Tap a rating:**
>
> ⭐⭐⭐⭐⭐ — "Perfect. Best cut I've ever had."
> ⭐⭐⭐⭐ — "Great. Just what I needed."
> ⭐⭐⭐ — "Good, but something was off."
> ⭐⭐ — "Not happy. Needs fixing."
> ⭐ — "Really not happy."
>
> Rated 1–3? We'll reach out to make it right — **7-day re-cut guarantee**, no questions asked.
>
> Your feedback keeps us sharp.
>
> — Edgecut & Co.

- **CTA:** [Leave a Google Review →]() *(if 4–5 stars)* · [Book a Fix →]() *(if 1–3 stars, links to re-book with same barber)*

---

## 7. No-Show Recovery

| Field | Detail |
|---|---|
| **Trigger** | Appointment time has passed without check-in (no-show detected in POS) |
| **Timing** | 30 minutes after the missed slot |

- **Subject:** Missed you at Edgecut — here's what's next
- **Body:**

> Hey {{first_name}},
>
> Looks like you missed your cut at **{{shop_name}}** today at **{{time}}**.
>
> **What happens now:**
> {% if deposit > 0 %}• Your **{{deposit}} {{currency}} deposit** has been forfeited per our 4-hour cancellation policy{% else %}• No deposit was charged, so no loss there{% endif %}
> • You can rebook right now — no penalty
> • Need to talk to us? Hit reply or call the shop
>
> We get it — things come up. Let's get you back on the books.
>
> — Edgecut & Co.

- **CTA:** [Re-book Now →]() · [Contact Shop →]()

---

## Summary Table

| # | Sequence | Trigger | Timing | Key CTA |
|---|---|---|---|---|
| 1 | Welcome | New account | Instant, +48h | Book first cut with code `FIRSTCUT` |
| 2 | Booking Confirmation | Booking created | Instant | Add to calendar / Reschedule |
| 3a | 24h Reminder | T-24h | 24h before | Reschedule / Cancel |
| 3b | 2h Reminder | T-2h | 2h before | Get Directions |
| 4 | Win-Back | 30/60/90d since last visit | Batch D+30, 60, 90 | Incentive code `COMEBACK15` at D90 |
| 5 | Referral | Post-cut complete | +24h | Share referral code |
| 6 | Post-Cut Survey | Appointment ended | +4h | Rate & Review / Book Fix |
| 7 | No-Show Recovery | Appointment missed | +30min | Re-book / Contact shop |

---

*Last updated: 2026-05-13*
