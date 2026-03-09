const test = require('node:test');
const assert = require('node:assert/strict');

const registerZoneRestrictionRoutes = require('../routes/zone-restriction-routes');

function buildRouter() {
  const handlers = new Map();
  return {
    handlers,
    register(method, path, handler) {
      handlers.set(`${method} ${path}`, handler);
    },
  };
}

test('admin create zone accepts country/state/pincode fields', async () => {
  const router = buildRouter();
  let capturedPayload = null;

  registerZoneRestrictionRoutes(router, {
    requireAuth: async () => ({ session: { userId: 'user-1' } }),
    requireAdmin: () => null,
    services: {
      zoneRestrictionsService: {
        list: async () => [],
        create: async (payload) => {
          capturedPayload = payload;
          return { id: 'zone-1', ...payload, isEnabled: true };
        },
        update: async () => ({}),
        setEnabled: async () => ({}),
        remove: async () => ({}),
        checkRestricted: async () => ({ restricted: false }),
      },
    },
  });

  const handler = router.handlers.get('POST /api/v1/admin/zone-restrictions');
  const response = await handler({
    headers: { 'x-admin-token': 'admin-token' },
    body: {
      name: 'Chennai Block',
      lat: 13.0827,
      lng: 80.2707,
      radiusKm: 5,
      appliesTo: 'rider',
      zoneType: 'restricted',
      country: 'in',
      state: 'tn',
      pincode: '600001',
      restrictionMessage: 'Not serviceable',
    },
  });

  assert.equal(response.status, 201);
  assert.equal(capturedPayload.country, 'in');
  assert.equal(capturedPayload.state, 'tn');
  assert.equal(capturedPayload.pincode, '600001');
});

test('zones check passes through diagnostics payload from service', async () => {
  const router = buildRouter();

  registerZoneRestrictionRoutes(router, {
    requireAuth: async () => ({ session: { userId: 'user-1' } }),
    requireAdmin: () => null,
    services: {
      zoneRestrictionsService: {
        list: async () => [],
        create: async () => ({}),
        update: async () => ({}),
        setEnabled: async () => ({}),
        remove: async () => ({}),
        checkRestricted: async () => ({
          restricted: true,
          message: 'Service blocked',
          zoneName: 'Test Zone',
          zoneId: 'zone-1',
          geoFilterApplied: true,
          geocodeUnavailable: false,
          location: { country: 'IN', state: 'TN', pincode: '600001' },
        }),
      },
    },
  });

  const handler = router.handlers.get('POST /api/v1/zones/check');
  const response = await handler({
    headers: { authorization: 'Bearer test-token' },
    body: { lat: 13.0827, lng: 80.2707, role: 'rider' },
  });

  assert.equal(response.status, 200);
  assert.equal(response.data.restricted, true);
  assert.equal(response.data.location.country, 'IN');
  assert.equal(response.data.location.state, 'TN');
  assert.equal(response.data.location.pincode, '600001');
});

