/**
 * Edgecut & Co. — Tenant Context
 * Multi-tenant configuration for 3-location barbershop chain.
 * URL > localStorage > default cascade.
 * Vanilla JS, no build step. Sets <html data-tenant="..."> on load.
 */
(function () {
  'use strict';

  const TENANTS = {
    brooklyn: {
      tenantId: 'brooklyn',
      currency: 'USD',
      locale: 'en-US',
      timezone: 'America/New_York',
      language: 'en',
      currencyDisplay: '$',
      dateFormat: { weekday: 'short', month: 'short', day: 'numeric' },
      timeFormat: { hour: 'numeric', minute: '2-digit', timeZoneName: 'short' },
    },
    la: {
      tenantId: 'la',
      currency: 'USD',
      locale: 'en-US',
      timezone: 'America/Los_Angeles',
      language: 'en',
      currencyDisplay: '$',
      dateFormat: { weekday: 'short', month: 'short', day: 'numeric' },
      timeFormat: { hour: 'numeric', minute: '2-digit', timeZoneName: 'short' },
    },
    madrid: {
      tenantId: 'madrid',
      currency: 'EUR',
      locale: 'es-ES',
      timezone: 'Europe/Madrid',
      language: 'es',
      currencyDisplay: '€',
      dateFormat: { weekday: 'short', day: 'numeric', month: 'short' },
      timeFormat: { hour: '2-digit', minute: '2-digit', timeZoneName: 'short' },
    },
  };

  const DEFAULT_TENANT = 'brooklyn';

  function resolveTenant() {
    // URL param takes precedence
    const params = new URLSearchParams(window.location.search);
    const fromUrl = params.get('tenantId');
    if (fromUrl && TENANTS[fromUrl]) return fromUrl;

    // localStorage fallback
    try {
      const stored = localStorage.getItem('edgecut-tenant');
      if (stored && TENANTS[stored]) return stored;
    } catch (e) { /* localStorage unavailable */ }

    // Default
    return DEFAULT_TENANT;
  }

  const activeTenantId = resolveTenant();
  const tenant = TENANTS[activeTenantId];

  // Set data-tenant on <html> for CSS token overrides
  document.documentElement.setAttribute('data-tenant', activeTenantId);

  // Persist choice
  try {
    localStorage.setItem('edgecut-tenant', activeTenantId);
  } catch (e) { /* ignore */ }

  /**
   * Format a price in the tenant's currency.
   * @param {number} amount - Decimal amount (e.g. 45.00)
   * @returns {string} Formatted currency string
   */
  function formatCurrency(amount) {
    try {
      return new Intl.NumberFormat(tenant.locale, {
        style: 'currency',
        currency: tenant.currency,
      }).format(amount);
    } catch (e) {
      return tenant.currencyDisplay + amount.toFixed(2);
    }
  }

  /**
   * Format a date in the tenant's timezone.
   * @param {Date|string|number} date
   * @param {object} [options] - Intl.DateTimeFormat overrides
   * @returns {string}
   */
  function formatDate(date, options) {
    const d = date instanceof Date ? date : new Date(date);
    const opts = Object.assign({}, tenant.dateFormat, options || {}, {
      timeZone: tenant.timezone,
    });
    try {
      return new Intl.DateTimeFormat(tenant.locale, opts).format(d);
    } catch (e) {
      return d.toLocaleDateString();
    }
  }

  /**
   * Format a time in the tenant's timezone.
   * @param {Date|string|number} date
   * @param {object} [options]
   * @returns {string}
   */
  function formatTime(date, options) {
    const d = date instanceof Date ? date : new Date(date);
    const opts = Object.assign({}, tenant.timeFormat, options || {}, {
      timeZone: tenant.timezone,
    });
    try {
      return new Intl.DateTimeFormat(tenant.locale, opts).format(d);
    } catch (e) {
      return d.toLocaleTimeString();
    }
  }

  /**
   * Format a full datetime in tenant's locale + timezone.
   */
  function formatDateTime(date, options) {
    const d = date instanceof Date ? date : new Date(date);
    const opts = Object.assign(
      { dateStyle: 'medium', timeStyle: 'short' },
      options || {},
      { timeZone: tenant.timezone }
    );
    try {
      return new Intl.DateTimeFormat(tenant.locale, opts).format(d);
    } catch (e) {
      return d.toLocaleString();
    }
  }

  /**
   * Get the tenant's timezone abbreviation (e.g. "EST", "CEST").
   */
  function getTimezoneAbbr(date) {
    const d = date || new Date();
    const parts = new Intl.DateTimeFormat('en', {
      timeZone: tenant.timezone,
      timeZoneName: 'short',
    }).formatToParts(d);
    const tzPart = parts.find(p => p.type === 'timeZoneName');
    return tzPart ? tzPart.value : tenant.timezone;
  }

  /**
   * Get a human-friendly timezone label with abbr.
   * e.g. "Pacific Time (PT)" or "Hora de Europa Central (CET)"
   */
  function getTimezoneLabel() {
    const abbr = getTimezoneAbbr();
    const labels = {
      'America/New_York': `Eastern Time (${abbr})`,
      'America/Los_Angeles': `Pacific Time (${abbr})`,
      'Europe/Madrid': `Hora de Europa Central (${abbr})`,
    };
    return labels[tenant.timezone] || `${tenant.timezone} (${abbr})`;
  }

  /**
   * Set the active tenant (e.g. from a tenant switcher UI).
   * Updates localStorage and data-tenant attribute.
   */
  function setTenant(tenantId) {
    if (!TENANTS[tenantId]) {
      console.warn('[tenant-context] Unknown tenant:', tenantId);
      return;
    }
    try {
      localStorage.setItem('edgecut-tenant', tenantId);
    } catch (e) { /* ignore */ }
    document.documentElement.setAttribute('data-tenant', tenantId);
    // Reload page context — in a SPA we'd re-render, but for static pages
    // we store in sessionStorage and suggest page reload
    sessionStorage.setItem('edgecut-tenant-switch', tenantId);
  }

  // Handle tenant-switch signal from another surface's tenant switcher
  try {
    const switchedTo = sessionStorage.getItem('edgecut-tenant-switch');
    if (switchedTo && switchedTo !== activeTenantId && TENANTS[switchedTo]) {
      document.documentElement.setAttribute('data-tenant', switchedTo);
      localStorage.setItem('edgecut-tenant', switchedTo);
    }
    sessionStorage.removeItem('edgecut-tenant-switch');
  } catch (e) { /* ignore */ }

  // Export to window for inline <script> use
  window.EdgecutTenant = {
    ...tenant,
    TENANTS,
    formatCurrency,
    formatDate,
    formatTime,
    formatDateTime,
    getTimezoneAbbr,
    getTimezoneLabel,
    setTenant,
    activeTenantId,
  };

  // Also set a CSP-friendly global for simple price formatting
  window.__ec = window.__ec || {};
  window.__ec.currency = function (amount) { return formatCurrency(amount); };
  window.__ec.tzLabel = getTimezoneLabel();

  console.log('[tenant-context] Active:', activeTenantId, '| TZ:', tenant.timezone);
})();
