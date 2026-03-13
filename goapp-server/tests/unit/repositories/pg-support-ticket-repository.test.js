'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const repository = require('../../../repositories/pg/pg-support-ticket-repository');

test('resolveRideForRider queries dropoff_address for destination snapshots', async () => {
  let capturedSql = null;
  let capturedParams = null;

  const row = {
    id: 'ride-1',
    rideNumber: 'RIDE-001',
    status: 'completed',
    fareEstimate: 230,
    pickupAddress: 'Pickup address',
    destinationAddress: 'Dropoff address',
    riderUserId: 'user-1',
    driverUserId: 'driver-1',
  };

  const result = await repository.resolveRideForRider('ride-1', 'user-1', {
    query: async (text, params) => {
      capturedSql = text;
      capturedParams = params;
      return { rows: [row] };
    },
  });

  assert.match(capturedSql, /r\.dropoff_address AS "destinationAddress"/);
  assert.doesNotMatch(capturedSql, /r\.dest_address AS "destinationAddress"/);
  assert.deepEqual(capturedParams, ['ride-1', 'user-1']);
  assert.equal(result.destinationAddress, 'Dropoff address');
});

test('listSupportPastRidesForUser queries support terminal rides with support-oriented fields', async () => {
  let capturedSql = null;
  let capturedParams = null;

  const result = await repository.listSupportPastRidesForUser('user-1', { limit: 5 }, {
    query: async (text, params) => {
      capturedSql = text;
      capturedParams = params;
      return {
        rows: [{
          id: 'ride-1',
          rideNumber: 'RIDE-001',
          status: 'cancelled',
          pickupAddress: 'Pickup address',
          destinationAddress: 'Dropoff address',
          fare: '125.5',
          serviceType: 'bike',
          driverName: 'Charan',
          driverVehicleType: 'bike',
          driverVehicleNumber: 'TN09DEV1003',
          driverPhone: '+919876500003',
          cancelledBy: 'rider',
          cancellationReasonCode: 'changed_plan',
          cancellationReasonText: 'Changed my plan',
          recordedAt: '2026-03-12T10:00:00.000Z',
        }],
      };
    },
  });

  assert.match(
    capturedSql,
    /COALESCE\(rdp\.vehicle_type, req_hist\."requestedServiceType", req_oe\."requestedServiceType", r\.ride_type\) AS "serviceType"/,
  );
  assert.match(capturedSql, /LOWER\(r\.status\) = ANY\(\$2::text\[\]\)/);
  assert.match(capturedSql, /ride_rider_projection/);
  assert.deepEqual(capturedParams, ['user-1', ['completed', 'cancelled', 'cancelled_by_rider', 'cancelled_by_driver', 'no_drivers'], 5]);
  assert.equal(result[0].supportEligible, true);
  assert.equal(result[0].driver.vehicleNumber, 'TN09DEV1003');
  assert.equal(result[0].cancellation.reasonCode, 'changed_plan');
  assert.equal(result[0].fare, 125.5);
});
