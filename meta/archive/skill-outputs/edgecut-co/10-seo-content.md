# SEO & Content Strategy — Edgecut & Co.

> **Version:** 1.0  
> **Last updated:** 2026-05-13  
> **Target markets:** Brooklyn, NY (US/en) · Los Angeles, CA (US/en) · Madrid (ES/es)  
> **Primary keywords:** "barber [city]", "fade [neighborhood]", "best barbershop [area]"

---

## 1. Meta Tags Template

### 1.1 Homepage (Per Tenant)

```html
<!-- BROOKLYN -->
<title>Edgecut &amp; Co. Brooklyn | Best Barbershop in Brooklyn, NY</title>
<meta name="description" content="Book a premium haircut, fade, or straight-razor shave at Edgecut &amp; Co. Brooklyn. Top-rated barbers in Williamsburg, Bushwick &amp; Downtown BK. Book online.">
<meta name="keywords" content="barber Brooklyn, fade Brooklyn, best barbershop Brooklyn, haircut Williamsburg, barber Bushwick, Edgecut & Co.">
<link rel="canonical" href="https://edgecut.co/brooklyn-ny">

<!-- LA -->
<title>Edgecut &amp; Co. Los Angeles | Best Barbershop in Los Angeles, CA</title>
<meta name="description" content="Premium haircuts, fades, and beard trims at Edgecut &amp; Co. Los Angeles. Top barbers in Silver Lake, Echo Park &amp; Downtown LA. Book your appointment online.">
<meta name="keywords" content="barber Los Angeles, fade Los Angeles, best barbershop LA, haircut Silver Lake, barber Echo Park, Edgecut &amp; Co.">
<link rel="canonical" href="https://edgecut.co/los-angeles-ca">

<!-- MADRID -->
<title>Edgecut &amp; Co. Madrid | Mejor Barbería en Madrid</title>
<meta name="description" content="Cortes de pelo, fade y afeitado clásico en Edgecut &amp; Co. Madrid. Los mejores barberos en Malasaña, Chueca y Salamanca. Reserva online.">
<meta name="keywords" content="barbería Madrid, fade Madrid, mejor barbería Madrid, corte de pelo Malasaña, barbero Chueca, Edgecut &amp; Co.">
<link rel="canonical" href="https://edgecut.co/madrid-es">
```

### 1.2 City + Neighborhood Pages (Programmatic)

```html
<!-- Pattern: barber-in-{city}-{neighborhood} -->
<title>Barber in Williamsburg, Brooklyn | Edgecut &amp; Co. BK</title>
<meta name="description" content="Find top-rated barbers in Williamsburg, Brooklyn. Book fades, scissor cuts, and beard trims at Edgecut &amp; Co. near McCarren Park.">
<meta name="keywords" content="barber Williamsburg, fade Williamsburg, barber shop Williamsburg Brooklyn, haircut near McCarren Park">
<link rel="canonical" href="https://edgecut.co/brooklyn-ny/neighborhoods/williamsburg">

<!-- Spanish equivalent -->
<title>Barbero en Malasaña, Madrid | Edgecut &amp; Co.</title>
<meta name="description" content="Los mejores barberos en Malasaña, Madrid. Cortes de pelo modernos, fades y afeitado clásico. Reserva cita online en Edgecut &amp; Co.">
<meta name="keywords" content="barbero Malasaña, barbería Malasaña Madrid, fade Malasaña, corte de pelo Malasaña">
<link rel="canonical" href="https://edgecut.co/madrid-es/barrios/malasana">
```

### 1.3 Service Pages

```html
<!-- Service detail page -->
<title>Fade Haircut in Brooklyn, NY | Edgecut &amp; Co. Brooklyn</title>
<meta name="description" content="Professional fade haircuts starting at $45. Skin fades, mid fades, temp fades — all styles available at Edgecut &amp; Co. Brooklyn. Book a fade today.">
<meta name="keywords" content="fade haircut Brooklyn, skin fade Brooklyn, mid fade Brooklyn, temp fade, barber fade">
<link rel="canonical" href="https://edgecut.co/brooklyn-ny/services/fade-haircut">
```

### 1.4 OG / Social Meta

```html
<meta property="og:title" content="Edgecut &amp; Co. Brooklyn — Best Barbershop in BK">
<meta property="og:description" content="Book award-winning barbers in Brooklyn. Premium fades, scissor cuts &amp; shaves.">
<meta property="og:image" content="https://cdn1.edgecut.co/images/og/brooklyn-og.jpg">
<meta property="og:url" content="https://edgecut.co/brooklyn-ny">
<meta property="og:type" content="website">
<meta property="og:locale" content="en_US">

<!-- Alternate locales -->
<meta property="og:locale:alternate" content="es_ES">

<!-- Twitter Card -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Edgecut &amp; Co. Brooklyn">
<meta name="twitter:description" content="Premium barbershop. Book online.">
<meta name="twitter:image" content="https://cdn1.edgecut.co/images/twitter/brooklyn-card.jpg">
```

---

## 2. JSON-LD Structured Data

### 2.1 LocalBusiness — Tenant Homepage

```json
{
  "@context": "https://schema.org",
  "@type": "LocalBusiness",
  "@id": "https://edgecut.co/brooklyn-ny#business",
  "name": "Edgecut & Co. Brooklyn",
  "description": "Premium barbershop in Brooklyn, NY. Fades, scissor cuts, beard trims, and straight-razor shaves.",
  "url": "https://edgecut.co/brooklyn-ny",
  "telephone": "+1-718-555-0134",
  "email": "brooklyn@edgecut.co",
  "image": "https://cdn1.edgecut.co/images/brooklyn-storefront.webp",
  "logo": "https://cdn1.edgecut.co/images/logo.svg",
  "priceRange": "$30-$75",
  "currenciesAccepted": "USD",
  "areaServed": {
    "@type": "City",
    "name": "Brooklyn",
    "sameAs": "https://en.wikipedia.org/wiki/Brooklyn"
  },
  "address": {
    "@type": "PostalAddress",
    "streetAddress": "123 Bedford Ave",
    "addressLocality": "Brooklyn",
    "addressRegion": "NY",
    "postalCode": "11211",
    "addressCountry": "US"
  },
  "geo": {
    "@type": "GeoCoordinates",
    "latitude": 40.718,
    "longitude": -73.958
  },
  "openingHoursSpecification": [
    { "@type": "OpeningHoursSpecification", "dayOfWeek": "Monday", "opens": "09:00", "closes": "19:00" },
    { "@type": "OpeningHoursSpecification", "dayOfWeek": "Tuesday", "opens": "09:00", "closes": "19:00" },
    { "@type": "OpeningHoursSpecification", "dayOfWeek": "Wednesday", "opens": "09:00", "closes": "19:00" },
    { "@type": "OpeningHoursSpecification", "dayOfWeek": "Thursday", "opens": "09:00", "closes": "20:00" },
    { "@type": "OpeningHoursSpecification", "dayOfWeek": "Friday", "opens": "09:00", "closes": "20:00" },
    { "@type": "OpeningHoursSpecification", "dayOfWeek": "Saturday", "opens": "08:00", "closes": "18:00" },
    { "@type": "OpeningHoursSpecification", "dayOfWeek": "Sunday", "opens": "10:00", "closes": "16:00" }
  ],
  "sameAs": [
    "https://instagram.com/edgecutbrooklyn",
    "https://facebook.com/edgecutbrooklyn",
    "https://yelp.com/biz/edgecut-brooklyn"
  ],
  "aggregateRating": {
    "@type": "AggregateRating",
    "ratingValue": "4.8",
    "reviewCount": "342",
    "bestRating": "5"
  }
}
```

### 2.2 BarberService — Service Detail

```json
{
  "@context": "https://schema.org",
  "@type": "BarberService",
  "@id": "https://edgecut.co/brooklyn-ny/services/fade-haircut#service",
  "name": "Fade Haircut",
  "description": "Professional fade haircut including skin fade, mid fade, or temp fade. Includes wash, style, and hot towel finish.",
  "provider": {
    "@type": "LocalBusiness",
    "@id": "https://edgecut.co/brooklyn-ny#business"
  },
  "offers": {
    "@type": "Offer",
    "price": "45.00",
    "priceCurrency": "USD",
    "availability": "https://schema.org/InStock",
    "url": "https://edgecut.co/brooklyn-ny/services/fade-haircut",
    "validFrom": "2026-01-01"
  },
  "duration": "PT30M",
  "image": "https://cdn1.edgecut.co/images/services/fade-haircut.webp",
  "areaServed": {
    "@type": "City",
    "name": "Brooklyn"
  }
}
```

### 2.3 Product — Retail Items (Merch)

```json
{
  "@context": "https://schema.org",
  "@type": "Product",
  "@id": "https://edgecut.co/shop/pomade#product",
  "name": "Edgecut & Co. Premium Pomade",
  "description": "Water-based pomade with medium hold and natural shine. Made with beeswax and argan oil.",
  "brand": {
    "@type": "Brand",
    "name": "Edgecut & Co."
  },
  "offers": {
    "@type": "Offer",
    "price": "18.00",
    "priceCurrency": "USD",
    "availability": "https://schema.org/InStock",
    "url": "https://edgecut.co/shop/pomade",
    "shippingDetails": {
      "@type": "OfferShippingDetails",
      "shippingRate": {
        "@type": "MonetaryAmount",
        "value": "5.00",
        "currency": "USD"
      }
    }
  },
  "image": "https://cdn1.edgecut.co/images/shop/pomade.webp",
  "category": "Hair Products"
}
```

### 2.4 BreadcrumbList

```json
{
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "itemListElement": [
    { "@type": "ListItem", "position": 1, "name": "Home", "item": "https://edgecut.co" },
    { "@type": "ListItem", "position": 2, "name": "Brooklyn", "item": "https://edgecut.co/brooklyn-ny" },
    { "@type": "ListItem", "position": 3, "name": "Services", "item": "https://edgecut.co/brooklyn-ny/services" },
    { "@type": "ListItem", "position": 4, "name": "Fade Haircut", "item": "https://edgecut.co/brooklyn-ny/services/fade-haircut" }
  ]
}
```

---

## 3. Sitemap Structure

### 3.1 sitemap.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:xhtml="http://www.w3.org/1999/xhtml">
  <!-- Homepages -->
  <url>
    <loc>https://edgecut.co/brooklyn-ny</loc>
    <xhtml:link rel="alternate" hreflang="en-us" href="https://edgecut.co/brooklyn-ny"/>
    <lastmod>2026-05-13</lastmod>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>https://edgecut.co/los-angeles-ca</loc>
    <xhtml:link rel="alternate" hreflang="en-us" href="https://edgecut.co/los-angeles-ca"/>
    <lastmod>2026-05-13</lastmod>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>https://edgecut.co/madrid-es</loc>
    <xhtml:link rel="alternate" hreflang="es-es" href="https://edgecut.co/madrid-es"/>
    <lastmod>2026-05-13</lastmod>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>

  <!-- Neighborhood pages -->
  <url>
    <loc>https://edgecut.co/brooklyn-ny/neighborhoods/williamsburg</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://edgecut.co/brooklyn-ny/neighborhoods/bushwick</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://edgecut.co/brooklyn-ny/neighborhoods/downtown-brooklyn</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://edgecut.co/brooklyn-ny/neighborhoods/greenpoint</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://edgecut.co/los-angeles-ca/neighborhoods/silver-lake</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://edgecut.co/los-angeles-ca/neighborhoods/echo-park</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://edgecut.co/los-angeles-ca/neighborhoods/downtown-la</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://edgecut.co/los-angeles-ca/neighborhoods/venice</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://edgecut.co/madrid-es/barrios/malasana</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://edgecut.co/madrid-es/barrios/chueca</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://edgecut.co/madrid-es/barrios/salamanca</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://edgecut.co/madrid-es/barrios/lavapies</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>

  <!-- Service pages -->
  <url>
    <loc>https://edgecut.co/brooklyn-ny/services/fade-haircut</loc>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>
  <url>
    <loc>https://edgecut.co/brooklyn-ny/services/scissor-cut</loc>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>
  <url>
    <loc>https://edgecut.co/brooklyn-ny/services/beard-trim</loc>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>
  <url>
    <loc>https://edgecut.co/brooklyn-ny/services/straight-razor-shave</loc>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>
  <url>
    <loc>https://edgecut.co/los-angeles-ca/services/fade-haircut</loc>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>
  <url>
    <loc>https://edgecut.co/los-angeles-ca/services/hot-towel-shave</loc>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>
  <url>
    <loc>https://edgecut.co/madrid-es/servicios/corte-fade</loc>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>
  <url>
    <loc>https://edgecut.co/madrid-es/servicios/afeitado-clasico</loc>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>

  <!-- Barber profile pages -->
  <url>
    <loc>https://edgecut.co/brooklyn-ny/barbers/marcus-jones</loc>
    <changefreq>monthly</changefreq>
    <priority>0.6</priority>
  </url>
  <url>
    <loc>https://edgecut.co/brooklyn-ny/barbers/aiko-tanaka</loc>
    <changefreq>monthly</changefreq>
    <priority>0.6</priority>
  </url>

  <!-- Static pages -->
  <url>
    <loc>https://edgecut.co/about</loc>
    <changefreq>monthly</changefreq>
    <priority>0.4</priority>
  </url>
  <url>
    <loc>https://edgecut.co/faq</loc>
    <changefreq>monthly</changefreq>
    <priority>0.4</priority>
  </url>
  <url>
    <loc>https://edgecut.co/privacy</loc>
    <changefreq>yearly</changefreq>
    <priority>0.2</priority>
  </url>
  <url>
    <loc>https://edgecut.co/terms</loc>
    <changefreq>yearly</changefreq>
    <priority>0.2</priority>
  </url>
</urlset>
```

### 3.2 sitemap Index (if > 50k URLs)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <sitemap>
    <loc>https://edgecut.co/sitemaps/static.xml</loc>
    <lastmod>2026-05-13</lastmod>
  </sitemap>
  <sitemap>
    <loc>https://edgecut.co/sitemaps/neighborhoods.xml</loc>
    <lastmod>2026-05-13</lastmod>
  </sitemap>
  <sitemap>
    <loc>https://edgecut.co/sitemaps/services.xml</loc>
    <lastmod>2026-05-13</lastmod>
  </sitemap>
  <sitemap>
    <loc>https://edgecut.co/sitemaps/barbers.xml</loc>
    <lastmod>2026-05-13</lastmod>
  </sitemap>
</sitemapindex>
```

### 3.3 robots.txt

```
User-agent: *
Allow: /
Disallow: /admin/
Disallow: /api/
Disallow: /*/book$
Disallow: /*/calendar$
Disallow: /_stripe/

Sitemap: https://edgecut.co/sitemap.xml
```

---

## 4. Programmatic SEO — Neighborhood Pages

### 4.1 URL Pattern

```
/{tenant-slug}/neighborhoods/{neighborhood-slug}
/{tenant-slug}/barrios/{neighborhood-slug}  (Spanish)
```

### 4.2 Page Template

Each page is generated server-side using the following template:

```html
<h1>Best Barbers in {{neighborhood}}, {{city}}</h1>
<p>Looking for a top-rated barber in {{neighborhood}}? Edgecut &amp; Co. serves the {{neighborhood}} area with premium haircuts, fades, and beard trims starting at {{lowest_price}}.</p>

<section>
  <h2>Our Barbers in {{neighborhood}}</h2>
  <!-- Dynamically list barbers serving this neighborhood -->
  <div data-neighborhood-barbers></div>
</section>

<section>
  <h2>Services Available in {{neighborhood}}</h2>
  <ul>
    <li><a href="/{{slug}}/services/fade-haircut">Fade Haircut — from $45</a></li>
    <li><a href="/{{slug}}/services/scissor-cut">Scissor Cut — from $50</a></li>
    <li><a href="/{{slug}}/services/beard-trim">Beard Trim — from $25</a></li>
  </ul>
</section>

<section>
  <h2>Book a Barber in {{neighborhood}}</h2>
  <p>Choose your barber, pick a time, and book online in under 2 minutes.</p>
  <a href="/{{slug}}/book" class="cta-button">Book Now</a>
</section>

<section id="faq">
  <h2>Frequently Asked Questions — Barber in {{neighborhood}}</h2>
  <details>
    <summary>How much does a haircut cost in {{neighborhood}}?</summary>
    <p>Prices start at ${{lowest_price}} for a standard cut and range up to ${{highest_price}} for premium services.</p>
  </details>
  <details>
    <summary>Do I need to book an appointment?</summary>
    <p>Yes, we recommend booking online to guarantee your preferred time slot with your chosen barber.</p>
  </details>
  <details>
    <summary>What neighborhoods do you serve near {{neighborhood}}?</summary>
    <p>We also serve <a href="/{{slug}}/neighborhoods/{{nearby_1}}">{{nearby_1}}</a>, <a href="/{{slug}}/neighborhoods/{{nearby_2}}">{{nearby_2}}</a>, and <a href="/{{slug}}/neighborhoods/{{nearby_3}}">{{nearby_3}}</a>.</p>
  </details>
</section>
```

### 4.3 Neighborhood Inventory

| City           | Neighborhood         | Slug                    | Target Keywords                                    |
|----------------|----------------------|-------------------------|----------------------------------------------------|
| Brooklyn       | Williamsburg         | williamsburg            | barber Williamsburg, fade Williamsburg             |
| Brooklyn       | Bushwick             | bushwick                | barber Bushwick, best barber Bushwick              |
| Brooklyn       | Downtown Brooklyn    | downtown-brooklyn       | barber downtown Brooklyn, haircut downtown BK      |
| Brooklyn       | Greenpoint           | greenpoint              | barber Greenpoint, fade Greenpoint                 |
| Los Angeles    | Silver Lake          | silver-lake             | barber Silver Lake, fade Silver Lake               |
| Los Angeles    | Echo Park            | echo-park               | barber Echo Park, best barbershop Echo Park        |
| Los Angeles    | Downtown LA          | downtown-la             | barber downtown LA, haircut DTLA                   |
| Los Angeles    | Venice               | venice                  | barber Venice, fade Venice Beach                   |
| Madrid         | Malasaña             | malasana                | barbero Malasaña, barbería Malasaña                |
| Madrid         | Chueca               | chueca                  | barbero Chueca, barbería Chueca Madrid             |
| Madrid         | Salamanca            | salamanca               | barbería Salamanca, corte de pelo Salamanca        |
| Madrid         | Lavapiés             | lavapies                | barbero Lavapiés, barbería Lavapiés                |

### 4.4 Internal Linking Strategy

- Every neighborhood page links to 2–3 nearby neighborhood pages in the FAQ
- Every service page links to relevant neighborhood pages
- Every barber profile links to the neighborhoods they serve
- Breadcrumbs on every page: `Home > Brooklyn > Williamsburg > Barber`
- Sitemap submitted to Google Search Console after each content update

---

## 5. Keyword Research & Targeting

### 5.1 Primary Keywords (Head Terms)

| Keyword              | Intent   | Target Page                   |
|----------------------|----------|-------------------------------|
| barber Brooklyn      | Commercial | Homepage / Neighborhood pages |
| barber Los Angeles   | Commercial | Homepage / Neighborhood pages |
| barbería Madrid      | Commercial | Homepage / Barrio pages       |
| best barbershop NYC  | Commercial | Brooklyn homepage             |
| fade haircut near me | Local     | Neighborhood pages            |

### 5.2 Secondary Keywords (Long-Tail)

| Keyword                              | Intent   | Target Page                     |
|--------------------------------------|----------|----------------------------------|
| skin fade barber Williamsburg        | Local    | Williamsburg neighborhood page   |
| best fade haircut Silver Lake        | Local    | Silver Lake neighborhood page    |
| barber shop open Sunday Brooklyn     | Local    | Brooklyn homepage                |
| corte de pelo moderno Malasaña       | Local    | Malasaña barrio page             |
| straight razor shave downtown LA     | Local    | Downtown LA neighborhood page    |
| kids haircut Bushwick                | Local    | Bushwick neighborhood page       |
| hot towel shave Madrid               | Local    | Afeitado clásico service page    |
| barber for men with long hair Venice | Local    | Venice neighborhood page         |

### 5.3 Keyword Density Guidelines

| Element             | Keyword Usage Guidelines                              |
|---------------------|-------------------------------------------------------|
| Title tag           | Primary keyword in first 60 characters                |
| H1                  | Primary keyword naturally, once                       |
| H2s                 | Secondary keywords in 2–3 subheadings                 |
| Body copy           | Keyword and synonyms 3–5 times per 500 words           |
| Meta description    | Primary keyword + CTA, ≤ 160 characters (en) / ≤ 150 (es) |
| Alt text            | Descriptive, include primary keyword where natural     |

---

## 6. Technical SEO Checklist

- [ ] Canonical URLs set on all pages (no duplicate content across tenant pages)
- [ ] `hreflang` tags correct: `en-US` for Brooklyn/LA, `es-ES` for Madrid
- [ ] Sitemap submitted to Google Search Console (3 properties: each tenant)
- [ ] robots.txt blocks admin, API, booking pages from indexing
- [ ] Server-side rendered (SSR) — no critical content behind JavaScript
- [ ] Page speed ≥ 90 on mobile per Lighthouse (target: 95)
- [ ] Core Web Vitals tracked: LCP < 2.5 s, FID < 100 ms, CLS < 0.1
- [ ] 404 page returns 404 status code (not 200)
- [ ] All images have descriptive alt text
- [ ] All links are crawlable (no `href="#"` or JS-only links)
- [ ] Structured data validated with Google Rich Results Test
- [ ] GSC indexed pages monitored weekly
- [ ] Broken link checker runs monthly

---

## 7. Measurement & KPIs

| KPI                         | Target       | Tool                   |
|-----------------------------|--------------|------------------------|
| Organic traffic (monthly)   | +20 % MoM    | Google Analytics 4     |
| Impressions (Search Console)| +15 % MoM    | Google Search Console  |
| Average position            | ≤ 5 for head terms | Google Search Console |
| Click-through rate          | ≥ 5 %        | Google Search Console  |
| Indexed pages               | 100 % of sitemap | Google Search Console |
| Crawl errors                | 0            | Google Search Console  |
| Core Web Vitals pass rate   | ≥ 90 %       | CrUX / Lighthouse      |
| JSON-LD validation          | 100 % pass   | Rich Results Test      |
