'use strict';

const { validationError } = require('./validation');

function isDateOnly(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(value || '').trim());
}

function registerZoneAnalyticsRoutes(router, ctx) {
  const { requireAdmin } = ctx;
  const zoneCatalogService = ctx.services?.zoneCatalogService || require('../services/zone-catalog-service');
  const zoneMetricsService = ctx.services?.zoneMetricsService || require('../services/zone-metrics-service');

  router.register('GET', '/api/v1/admin/zones/catalog', async ({ headers, params }) => {
    const adminErr = requireAdmin(headers);
    if (adminErr) return adminErr;

    const activeOnly = String(params.get('activeOnly') || 'true').toLowerCase() !== 'false';
    const city = params.get('city') || 'Chennai';
    const state = params.get('state') || 'Tamil Nadu';
    const country = params.get('country') || 'IN';
    const zoneLevel = params.get('zoneLevel') || null;

    const zones = await zoneCatalogService.listCatalog({
      city,
      state,
      country,
      zoneLevel,
      activeOnly,
    });
    return { data: { zones, total: zones.length } };
  });

  router.register('GET', '/api/v1/admin/zones/metrics/hourly', async ({ headers, params }) => {
    const adminErr = requireAdmin(headers);
    if (adminErr) return adminErr;

    const zoneId = String(params.get('zoneId') || '').trim();
    const from = String(params.get('from') || '').trim();
    const to = String(params.get('to') || '').trim();
    if (!zoneId) return validationError('zoneId is required');
    if (!from) return validationError('from is required (ISO timestamp)');
    if (!to) return validationError('to is required (ISO timestamp)');

    const fromDate = new Date(from);
    const toDate = new Date(to);
    if (Number.isNaN(fromDate.getTime())) return validationError('from is invalid');
    if (Number.isNaN(toDate.getTime())) return validationError('to is invalid');
    if (fromDate > toDate) return validationError('from must be <= to');

    const rows = await zoneMetricsService.getHourly({
      zoneId,
      from: fromDate.toISOString(),
      to: toDate.toISOString(),
    });
    return { data: { zoneId, from: fromDate.toISOString(), to: toDate.toISOString(), rows } };
  });

  router.register('GET', '/api/v1/admin/zones/metrics/summary', async ({ headers, params }) => {
    const adminErr = requireAdmin(headers);
    if (adminErr) return adminErr;
    const date = String(params.get('date') || '').trim();
    if (!isDateOnly(date)) return validationError('date is required in YYYY-MM-DD');
    const rows = await zoneMetricsService.getSummaryByDate(date);
    return { data: { date, rows } };
  });

  router.register('GET', '/api/v1/admin/zones/peaks', async ({ headers, params }) => {
    const adminErr = requireAdmin(headers);
    if (adminErr) return adminErr;
    const date = String(params.get('date') || '').trim();
    if (!isDateOnly(date)) return validationError('date is required in YYYY-MM-DD');
    const rows = await zoneMetricsService.getPeaksByDate(date);
    return { data: { date, rows } };
  });

  router.register('POST', '/api/v1/admin/zones/metrics/reconcile', async ({ headers }) => {
    const adminErr = requireAdmin(headers);
    if (adminErr) return adminErr;
    await zoneMetricsService.reconcileFromRides();
    return { data: { success: true } };
  });
}

module.exports = registerZoneAnalyticsRoutes;
