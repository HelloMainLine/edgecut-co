/**
 * biz-dashboard-data.js — Mock data for Edgecut & Co. provider dashboard
 * 
 * Seeds 90 days of realistic bookings, payments, and reviews across 3 tenants.
 * Exports async functions consumed by the provider dashboard HTML surfaces.
 * Vanilla JS — no build step, no imports.
 */

(function () {
  'use strict';

  // ── Configuration ───────────────────────────────────────────
  const TENANTS = {
    brooklyn: {
      currency: 'USD',
      locale: 'en-US',
      timezone: 'America/New_York',
      barbers: ['Miguel Santos', 'Keisha Okafor', 'Jordan Medina'],
      services: [
        { name: 'Classic Fade', price: 45 },
        { name: 'Straight Razor Shave', price: 35 },
        { name: 'Beard Trim & Shape', price: 25 },
        { name: 'Haircut + Shave Combo', price: 65 },
        { name: 'Hot Towel Treatment', price: 20 },
        { name: 'Kids Cut (under 12)', price: 30 },
      ],
    },
    la: {
      currency: 'USD',
      locale: 'en-US',
      timezone: 'America/Los_Angeles',
      barbers: ['Luca Romano', 'Sam Park', 'Jasper Chen'],
      services: [
        { name: 'Textured Crop', price: 55 },
        { name: 'Skin Fade', price: 50 },
        { name: 'Beard Sculpt', price: 30 },
        { name: 'Pompadour Cut', price: 55 },
        { name: 'Hair Design + Color', price: 85 },
        { name: 'Express Cleanup', price: 25 },
      ],
    },
    madrid: {
      currency: 'EUR',
      locale: 'es-ES',
      timezone: 'Europe/Madrid',
      barbers: ['Marta de la Vega', 'Yusuf Osman', 'Carlos Jiménez'],
      services: [
        { name: 'Corte Clásico', price: 35 },
        { name: 'Degradado (Fade)', price: 40 },
        { name: 'Arreglo de Barba', price: 20 },
        { name: 'Corte + Barba', price: 50 },
        { name: 'Navaja Clásica', price: 30 },
        { name: 'Corte Infantil', price: 25 },
      ],
    },
  };

  const DAYS_BACK = 90;
  const CUSTOMER_NAMES = {
    brooklyn: [
      'Marcus T.', 'Jasmine K.', 'Darnell W.', 'Aisha M.', 'Tyrone B.',
      'Naomi P.', 'Elijah R.', 'Zoe C.', 'Malik J.', 'Sasha D.',
      'Kwame A.', 'Nia L.', 'DeShawn F.', 'Imani S.', 'Terrence H.',
    ],
    la: [
      'Dani R.', 'Alex P.', 'Skyler Y.', 'Jordan L.', 'Riley B.',
      'Casey N.', 'Avery W.', 'Morgan T.', 'Quinn S.', 'Taylor K.',
      'Blake M.', 'Reese D.', 'Drew H.', 'Hayden C.', 'Parker J.',
    ],
    madrid: [
      'Carlos M.', 'Lucía G.', 'Miguel A.', 'Elena R.', 'Pablo S.',
      'Sofía L.', 'Antonio V.', 'Carmen P.', 'Jorge D.', 'Ana M.',
      'David N.', 'Laura F.', 'Raúl H.', 'Marta C.', 'Javier T.',
    ],
  };

  // ── Helpers ─────────────────────────────────────────────────
  function randomInt(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }

  function randomFloat(min, max, decimals) {
    return parseFloat((Math.random() * (max - min) + min).toFixed(decimals));
  }

  function randomChoice(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
  }

  function formatDate(date) {
    return date.toISOString().split('T')[0];
  }

  function formatIso(date) {
    return date.toISOString();
  }

  function isWeekend(date) {
    const day = date.getDay();
    return day === 0 || day === 6;
  }

  function isPeakHour(hour) {
    // Lunch dip at 12-14, peak at 10-12 and 15-18
    return (hour >= 10 && hour < 12) || (hour >= 15 && hour < 18);
  }

  function isDipHour(hour) {
    return hour >= 12 && hour < 14;
  }

  // ── Generate 90 Days of Bookings ────────────────────────────
  function generateBookings(tenantId, days) {
    const config = TENANTS[tenantId];
    if (!config) return [];

    const bookings = [];
    const now = new Date();
    let bookingId = 1;

    for (let d = 0; d < days; d++) {
      const date = new Date(now);
      date.setDate(date.getDate() - d);
      date.setHours(0, 0, 0, 0);

      const isWeekendDay = isWeekend(date);
      const baseBookingCount = isWeekendDay ? randomInt(18, 35) : randomInt(10, 22);

      for (let b = 0; b < baseBookingCount; b++) {
        const hour = randomInt(9, 20);
        const minute = randomChoice([0, 15, 30, 45]);

        // Apply realistic distribution
        let bookingWeight = 1.0;
        if (isPeakHour(hour)) bookingWeight = 1.5;
        if (isDipHour(hour)) bookingWeight = 0.4;
        if (hour < 10 || hour >= 19) bookingWeight = 0.3;

        if (Math.random() > bookingWeight) continue;

        const startsAt = new Date(date);
        startsAt.setHours(hour, minute, 0, 0);

        const barber = randomChoice(config.barbers);
        const service = randomChoice(config.services);
        const customerName = randomChoice(CUSTOMER_NAMES[tenantId]);
        const createdAt = new Date(startsAt);
        createdAt.setDate(createdAt.getDate() - randomInt(0, 7));

        // Status distribution
        const statusRoll = Math.random();
        let status;
        if (statusRoll < 0.65) status = 'completed';
        else if (statusRoll < 0.80) status = 'confirmed';
        else if (statusRoll < 0.88) status = 'no-show';
        else if (statusRoll < 0.94) status = 'cancelled';
        else status = 'completed'; // future bookings

        const rating = status === 'completed' && randomInt(1, 10) > 2 ? randomInt(4, 5) : null;
        const reviewText = rating && rating >= 4
          ? randomChoice([
              'Great cut, will be back!',
              'Best fade in town.',
              'Always consistent quality.',
              'Love the vibe here.',
              'Barber really knows their craft.',
            ])
          : rating === 3
            ? 'Okay, but waited a while.'
            : null;

        bookings.push({
          id: `BKG-${tenantId}-${String(bookingId++).padStart(4, '0')}`,
          tenantId,
          barberName: barber,
          serviceName: service.name,
          price: service.price,
          currency: config.currency,
          startsAt: formatIso(startsAt),
          customerName,
          status,
          rating,
          reviewText,
          createdAt: formatIso(createdAt),
        });
      }
    }

    return bookings;
  }

  // ── Compute KPIs ────────────────────────────────────────────
  function computeKpis(bookings, tenantId, period) {
    if (!bookings || bookings.length === 0) {
      return {
        todayRevenue: 0,
        todayBookings: 0,
        todayNoShows: 0,
        nps: 75,
        topServices: [],
        churnRisk: 0.05,
        period,
        tenantId,
      };
    }

    const now = new Date();
    const todayStr = formatDate(now);

    let periodStart;
    switch (period) {
      case '7d': periodStart = new Date(now); periodStart.setDate(periodStart.getDate() - 7); break;
      case '30d': periodStart = new Date(now); periodStart.setDate(periodStart.getDate() - 30); break;
      case '90d': default: periodStart = new Date(now); periodStart.setDate(periodStart.getDate() - 90); break;
    }

    const periodBookings = bookings.filter(b => new Date(b.startsAt) >= periodStart);
    const todayBookings = bookings.filter(b => b.startsAt.startsWith(todayStr));
    const todayCompleted = todayBookings.filter(b => b.status === 'completed');
    const todayNoShows = todayBookings.filter(b => b.status === 'no-show');
    const todayRevenue = todayCompleted.reduce((sum, b) => sum + b.price, 0);

    // NPS: % of ratings >= 4 minus % of ratings <= 2
    const completed = periodBookings.filter(b => b.status === 'completed' && b.rating);
    const promoters = completed.filter(b => b.rating >= 4).length;
    const detractors = completed.filter(b => b.rating <= 2).length;
    const totalRated = completed.length;
    const nps = totalRated > 0
      ? Math.round(((promoters / totalRated) - (detractors / totalRated)) * 100)
      : 75;

    // Top services
    const serviceCounts = {};
    periodBookings.filter(b => b.status === 'completed').forEach(b => {
      serviceCounts[b.serviceName] = (serviceCounts[b.serviceName] || 0) + 1;
    });
    const topServices = Object.entries(serviceCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([name, count]) => ({ name, count }));

    // Churn risk: % of customers who haven't returned in 60+ days
    const customerLastVisit = {};
    bookings.forEach(b => {
      const iso = b.startsAt;
      if (!customerLastVisit[b.customerName] || iso > customerLastVisit[b.customerName]) {
        customerLastVisit[b.customerName] = iso;
      }
    });
    const totalCustomers = Object.keys(customerLastVisit).length;
    const churned = Object.entries(customerLastVisit).filter(([name, date]) => {
      const diffDays = (now - new Date(date)) / (1000 * 60 * 60 * 24);
      return diffDays > 60;
    }).length;
    const churnRisk = totalCustomers > 0 ? churned / totalCustomers : 0.05;

    return {
      todayRevenue,
      todayBookings: todayBookings.filter(b => b.status !== 'cancelled').length,
      todayNoShows: todayNoShows.length,
      nps,
      topServices,
      churnRisk: parseFloat(churnRisk.toFixed(2)),
      period,
      tenantId,
    };
  }

  // ── Generate data once ──────────────────────────────────────
  const _cache = {};

  function getData(tenantId, forceRefresh) {
    if (!_cache[tenantId] || forceRefresh) {
      _cache[tenantId] = generateBookings(tenantId, DAYS_BACK);
    }
    return _cache[tenantId];
  }

  // ── Exported API ────────────────────────────────────────────
  /**
   * Get KPI data for a tenant over a period
   * @param {string} tenantId - 'brooklyn', 'la', 'madrid'
   * @param {string} period - '7d', '30d', '90d'
   * @returns {Promise<Object>} KPI object
   */
  async function getKpis(tenantId, period) {
    const bookings = getData(tenantId);
    return computeKpis(bookings, tenantId, period || '90d');
  }

  /**
   * Get booking history for a tenant
   * @param {string} tenantId - 'brooklyn', 'la', 'madrid'
   * @param {number} days - Number of days of history
   * @returns {Promise<Array>} Array of booking objects
   */
  async function getBookingHistory(tenantId, days) {
    const bookings = getData(tenantId);
    if (!days || days >= DAYS_BACK) return bookings;

    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - days);
    return bookings.filter(b => new Date(b.startsAt) >= cutoff);
  }

  /**
   * Get barber stats for a tenant
   * @param {string} tenantId
   * @returns {Promise<Array>} Array of barber stat objects
   */
  async function getBarberStats(tenantId) {
    const bookings = getData(tenantId);
    const config = TENANTS[tenantId];
    if (!config) return [];

    const completed = bookings.filter(b => b.status === 'completed');
    const barberData = config.barbers.map(name => {
      const barberBookings = completed.filter(b => b.barberName === name);
      const revenue = barberBookings.reduce((s, b) => s + b.price, 0);
      const ratings = barberBookings.filter(b => b.rating).map(b => b.rating);
      const avgRating = ratings.length > 0
        ? parseFloat((ratings.reduce((s, r) => s + r, 0) / ratings.length).toFixed(1))
        : 4.5;
      return {
        barberName: name,
        totalBookings: barberBookings.length,
        revenue,
        avgRating,
        currency: config.currency,
      };
    });

    return barberData;
  }

  /**
   * Preview recent bookings (top N)
   * @param {string} tenantId
   * @param {number} limit
   * @returns {Promise<Array>}
   */
  async function getRecentBookings(tenantId, limit) {
    const bookings = getData(tenantId);
    return bookings
      .sort((a, b) => new Date(b.startsAt) - new Date(a.startsAt))
      .slice(0, limit || 20);
  }

  // Expose globally
  window.EdgecutData = {
    getKpis,
    getBookingHistory,
    getBarberStats,
    getRecentBookings,
    TENANTS,
  };

  console.log('%c📊 Edgecut & Co. Data Layer loaded', 'color:#B8926B;font-weight:bold');
})();
