const test = require('node:test');
const assert = require('node:assert/strict');

const registerZoneAnalyticsRoutes = require('../routes/zone-analytics-routes');

function buildRouter() {
  const handlers = new Map();
  return {
    handlers,
    register(method, path, handler) {
      handlers.set(`${method} ${path}`, handler);
    },
  };
}

test('zone catalog endpoint returns rows for admin', async () => {
  const router = buildRouter();
  registerZoneAnalyticsRoutes(router, {
    requireAdmin: () => null,
    services: {
      zoneCatalogService: {
        listCatalog: async () => [{ id: 'z1', zoneCode: 'CHN-CENTRAL' }],
      },
      zoneMetricsService: {
        getHourly: async () => [],
        getSummaryByDate: async () => [],
        getPeaksByDate: async () => [],
        reconcileFromRides: async () => {},
      },
    },
  });

  const handler = router.handlers.get('GET /api/v1/admin/zones/catalog');
  const response = await handler({
    headers: { 'x-admin-token': 'ok' },
    params: new URLSearchParams(),
  });

  assert.equal(response.data.total, 1);
  assert.equal(response.data.zones[0].zoneCode, 'CHN-CENTRAL');
});

test('zone hourly endpoint validates required query args', async () => {
  const router = buildRouter();
  registerZoneAnalyticsRoutes(router, {
    requireAdmin: () => null,
    services: {
      zoneCatalogService: {
        listCatalog: async () => [],
      },
      zoneMetricsService: {
        getHourly: async () => [],
        getSummaryByDate: async () => [],
        getPeaksByDate: async () => [],
        reconcileFromRides: async () => {},
      },
    },
  });

  const handler = router.handlers.get('GET /api/v1/admin/zones/metrics/hourly');
  const response = await handler({
    headers: { 'x-admin-token': 'ok' },
    params: new URLSearchParams('zoneId=abc'),
  });

  assert.equal(response.status, 400);
  assert.equal(response.data.code, 'VALIDATION_ERROR');
});

