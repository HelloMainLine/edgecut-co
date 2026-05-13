/**
 * Edgecut & Co. — Realtime Staleness Indicator (MOS Rule 51)
 * Polls a data source, manages data-realtime-state attribute,
 * and renders staleness pill with honest timing.
 * Respects prefers-reduced-data (60s polling instead of 15s).
 * Vanilla JS, no build step.
 */
(function () {
  'use strict';

  /**
   * Attach realtime polling to a DOM element.
   *
   * @param {HTMLElement} el - Element to manage
   * @param {Function} fetchFn - Async function returning { data, lastUpdated: Date|number }
   * @param {object} [opts]
   * @param {number} [opts.pollInterval=15000] - Base polling interval (ms)
   * @param {number} [opts.freshThreshold=30000] - Max age (ms) for "fresh" status
   * @param {number} [opts.staleThreshold=60000] - Max age (ms) for "stale" status
   * @param {boolean} [opts.showPill=true] - Render a staleness pill inside the element
   * @param {boolean} [opts.showRefresh=true] - Show "Refresh" CTA when dead
   * @param {function} [opts.onData] - Callback with fresh data each poll
   * @returns {{ destroy: Function, refresh: Function }} Control handle
   */
  function attachRealtime(el, fetchFn, opts) {
    opts = Object.assign({
      pollInterval: 15000,
      freshThreshold: 30000,
      staleThreshold: 60000,
      showPill: true,
      showRefresh: true,
      onData: null,
    }, opts || {});

    // Respect prefers-reduced-data: 60s polling
    let interval = opts.pollInterval;
    try {
      if (window.matchMedia('(prefers-reduced-data: reduce)').matches) {
        interval = 60000;
      }
    } catch (e) { /* not supported */ }

    let lastUpdated = null;
    let currentData = null;
    let timer = null;
    let destroyed = false;

    // Create staleness pill element
    let pill = null;
    let refreshBtn = null;

    if (opts.showPill) {
      pill = document.createElement('span');
      pill.className = 'realtime-pill';
      pill.setAttribute('aria-live', 'polite');
      pill.style.cssText =
        'display:inline-flex;align-items:center;gap:4px;font-size:11px;' +
        'padding:2px 8px;border-radius:12px;transition:all 300ms;';
      el.appendChild(pill);
    }

    /**
     * Update the realtime state attribute and pill UI.
     */
    function updateState() {
      if (destroyed || !lastUpdated) return;

      const now = Date.now();
      const age = now - lastUpdated;
      let state, label;

      if (age < opts.freshThreshold) {
        state = 'fresh';
        label = 'Live';
      } else if (age < opts.staleThreshold) {
        const secsAgo = Math.floor((age - opts.freshThreshold) / 1000);
        state = 'stale';
        label = 'Stale · ' + secsAgo + 's ago';
      } else {
        const minsAgo = Math.floor(age / 60000);
        state = 'dead';
        label = 'Last updated ' + minsAgo + 'm ago';
      }

      el.setAttribute('data-realtime-state', state);

      if (pill) {
        pill.textContent = '';
        const dot = document.createElement('span');
        dot.style.cssText =
          'width:7px;height:7px;border-radius:50%;flex-shrink:0;';
        dot.setAttribute('aria-hidden', 'true');

        const text = document.createTextNode(label);

        switch (state) {
          case 'fresh':
            dot.style.background = '#22c55e';  // green
            pill.style.background = 'rgba(34,197,94,0.12)';
            pill.style.color = '#15803d';
            break;
          case 'stale':
            dot.style.background = '#f59e0b';  // orange
            pill.style.background = 'rgba(245,158,11,0.12)';
            pill.style.color = '#b45309';
            break;
          case 'dead':
            dot.style.background = '#9ca3af';  // grey
            pill.style.background = 'rgba(156,163,175,0.12)';
            pill.style.color = '#6b7280';
            break;
        }

        pill.appendChild(dot);
        pill.appendChild(text);
      }

      // Show/hide Refresh CTA when dead
      if (opts.showRefresh) {
        if (state === 'dead' && !refreshBtn) {
          refreshBtn = document.createElement('button');
          refreshBtn.className = 'realtime-refresh';
          refreshBtn.textContent = 'Refresh';
          refreshBtn.style.cssText =
            'font-size:11px;padding:2px 10px;border-radius:8px;' +
            'border:1px solid #d1d5db;background:#f9fafb;cursor:pointer;' +
            'margin-left:4px;color:#374151;';
          refreshBtn.addEventListener('click', function (e) {
            e.preventDefault();
            doFetch();
          });
          if (pill) {
            pill.parentNode.insertBefore(refreshBtn, pill.nextSibling);
          } else {
            el.appendChild(refreshBtn);
          }
        } else if (state !== 'dead' && refreshBtn) {
          refreshBtn.remove();
          refreshBtn = null;
        }
      }
    }

    /**
     * Perform a fetch cycle.
     */
    async function doFetch() {
      if (destroyed) return;
      try {
        const result = await fetchFn();
        if (!result || destroyed) return;

        currentData = result.data != null ? result.data : currentData;
        // lastUpdated can be Date, number (epoch ms), or Date.now() default
        if (result.lastUpdated != null) {
          lastUpdated = result.lastUpdated instanceof Date
            ? result.lastUpdated.getTime()
            : new Date(result.lastUpdated).getTime();
          if (isNaN(lastUpdated)) lastUpdated = Date.now();
        } else {
          lastUpdated = Date.now();
        }

        if (opts.onData && currentData != null) {
          opts.onData(currentData);
        }

        updateState();
      } catch (err) {
        console.warn('[realtime] Fetch failed:', err);
        // Don't update lastUpdated — keep showing previous state
        // If we never had data, set to dead immediately
        if (lastUpdated === null) {
          lastUpdated = Date.now();
          updateState();
        }
      }
    }

    // Initial fetch
    doFetch();

    // Start polling
    timer = setInterval(doFetch, interval);

    // Listen for reduced-data changes
    let mediaQuery = null;
    try {
      mediaQuery = window.matchMedia('(prefers-reduced-data: reduce)');
      const handler = function (e) {
        clearInterval(timer);
        interval = e.matches ? 60000 : opts.pollInterval;
        if (!destroyed) {
          timer = setInterval(doFetch, interval);
        }
      };
      if (mediaQuery.addEventListener) {
        mediaQuery.addEventListener('change', handler);
      } else if (mediaQuery.addListener) {
        mediaQuery.addListener(handler);
      }
    } catch (e) { /* not supported */ }

    // Cleanup
    function destroy() {
      destroyed = true;
      clearInterval(timer);
      timer = null;
      if (mediaQuery) {
        try {
          mediaQuery.removeEventListener('change', handler);
        } catch (e) { /* ignore */ }
      }
    }

    return {
      destroy: destroy,
      refresh: doFetch,
      getData: function () { return currentData; },
      getState: function () {
        if (!lastUpdated) return 'unknown';
        const age = Date.now() - lastUpdated;
        if (age < opts.freshThreshold) return 'fresh';
        if (age < opts.staleThreshold) return 'stale';
        return 'dead';
      },
    };
  }

  /**
   * Batch: attach realtime to multiple elements sharing a poll.
   * Saves one fetch per N elements.
   *
   * @param {string|NodeList|HTMLElement[]} selector - CSS selector or element list
   * @param {Function} fetchFn - Single fetch returning { data: any, lastUpdated }
   * @param {object} [opts]
   * @returns {Array} Array of control handles
   */
  function attachRealtimeBatch(selector, fetchFn, opts) {
    let elements;
    if (typeof selector === 'string') {
      elements = document.querySelectorAll(selector);
    } else if (selector instanceof NodeList || Array.isArray(selector)) {
      elements = selector;
    } else {
      elements = [selector];
    }

    const handles = [];
    let lastSharedResult = null;
    let sharedLastUpdated = null;

    const sharedFetch = async function () {
      // Cache across all elements in this batch — only fetch once per cycle
      if (lastSharedResult) {
        const result = lastSharedResult;
        lastSharedResult = null; // consume
        return { data: result, lastUpdated: sharedLastUpdated };
      }
      const result = await fetchFn();
      sharedLastUpdated = result.lastUpdated || Date.now();
      return result;
    };

    for (let i = 0; i < elements.length; i++) {
      handles.push(attachRealtime(elements[i], sharedFetch, opts));
    }

    // Override refresh to batch
    return {
      handles: handles,
      refreshAll: function () {
        fetchFn().then(function (result) {
          sharedLastUpdated = result.lastUpdated || Date.now();
          lastSharedResult = result.data;
          handles.forEach(function (h) { h.refresh(); });
        });
      },
      destroyAll: function () {
        handles.forEach(function (h) { h.destroy(); });
      },
    };
  }

  // Export
  window.EdgecutRealtime = {
    attach: attachRealtime,
    attachBatch: attachRealtimeBatch,
  };
})();
