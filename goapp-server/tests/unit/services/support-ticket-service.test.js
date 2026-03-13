'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const service = require('../../../services/support-ticket-service');

test('createTicket allows cancelled rides and keeps the destination snapshot from the rides schema', async () => {
  const originalRepository = service.repository;
  const originalRedis = service.redis;
  const originalNotificationService = service.notificationService;
  const originalStorageService = service.storageService;
  const originalWsServer = service.wsServer;
  const originalBuildTicketCode = service._buildTicketCode;

  let resolveRideArgs = null;
  let createdTicketPayload = null;

  service.repository = {
    resolveRideForRider: async (rideId, userId) => {
      resolveRideArgs = { rideId, userId };
      return {
        id: 'ride-1',
        rideNumber: 'RIDE-001',
        status: 'cancelled',
        pickupAddress: 'Pickup address',
        destinationAddress: 'Dropoff address',
        fareEstimate: 230,
        riderUserId: 'user-1',
        driverUserId: 'driver-1',
      };
    },
    withTransaction: async (callback) => callback({}),
    getAssignableAgent: async () => null,
    createTicket: async (_client, payload) => {
      createdTicketPayload = payload;
      return 'ticket-1';
    },
    updateTicketAfterCreate: async () => {},
    createMessage: async () => 'message-1',
    insertStatusHistory: async () => {},
    upsertReadState: async () => {},
    enqueueOutbox: async () => {},
    getTicketDetail: async () => ({
      id: 'ticket-1',
      ticketCode: 'SUP-TEST-001',
      status: 'OPEN',
      canReply: true,
    }),
  };
  service.redis = null;
  service.notificationService = null;
  service.storageService = null;
  service.wsServer = null;
  service._buildTicketCode = () => 'SUP-TEST-001';

  try {
    const result = await service.createTicket({
      userId: 'user-1',
      category: 'driver_vehicle_issue',
      subject: 'Past ride issue',
      message: 'Driver was rude',
      rideId: 'ride-1',
      metadata: {
        source: 'past_ride_issue_details_page',
      },
    });

    assert.equal(result.success, true);
    assert.deepEqual(resolveRideArgs, {
      rideId: 'ride-1',
      userId: 'user-1',
    });
    assert.equal(createdTicketPayload.rideId, 'ride-1');
    assert.equal(
      createdTicketPayload.metadata.rideSnapshot.destinationAddress,
      'Dropoff address',
    );
    assert.equal(
      createdTicketPayload.metadata.rideSnapshot.pickupAddress,
      'Pickup address',
    );
  } finally {
    service.repository = originalRepository;
    service.redis = originalRedis;
    service.notificationService = originalNotificationService;
    service.storageService = originalStorageService;
    service.wsServer = originalWsServer;
    service._buildTicketCode = originalBuildTicketCode;
  }
});

test('listSupportPastRides prefers the vehicle type for support display metadata', async () => {
  const originalRepository = service.repository;

  service.repository = {
    listSupportPastRidesForUser: async () => ([
      {
        id: 'ride-1',
        rideNumber: 'RIDE-001',
        status: 'no_drivers',
        pickupAddress: 'Pickup address',
        destinationAddress: 'Dropoff address',
        fare: 126.61,
        serviceType: 'on_demand',
        driver: {
          vehicleType: 'bike',
        },
        recordedAt: '2026-03-12T10:00:00.000Z',
        supportEligible: true,
      },
    ]),
  };

  try {
    const result = await service.listSupportPastRides('user-1', { limit: 10 });

    assert.equal(result.success, true);
    assert.equal(result.data.rides[0].serviceType, 'bike');
  } finally {
    service.repository = originalRepository;
  }
});

test('createTicket derives category from past ride issue group and validates sub-issues', async () => {
  const originalRepository = service.repository;
  const originalRedis = service.redis;
  const originalNotificationService = service.notificationService;
  const originalStorageService = service.storageService;
  const originalWsServer = service.wsServer;
  const originalBuildTicketCode = service._buildTicketCode;

  let createdTicketPayload = null;

  service.repository = {
    getPastRideIssueGroupById: async () => ({
      id: 'group-1',
      title: 'Driver behavior',
      backendCategory: 'driver_vehicle_issue',
    }),
    listPastRideSubIssuesByIds: async () => ([
      { id: 'sub-1', groupId: 'group-1', title: 'Driver was rude' },
      { id: 'sub-2', groupId: 'group-1', title: 'Driver ignored instructions' },
    ]),
    resolveRideForRider: async () => ({
      id: 'ride-1',
      rideNumber: 'RIDE-001',
      status: 'completed',
      pickupAddress: 'Pickup address',
      destinationAddress: 'Dropoff address',
      fareEstimate: 230,
      riderUserId: 'user-1',
      driverUserId: 'driver-1',
    }),
    withTransaction: async (callback) => callback({}),
    getAssignableAgent: async () => null,
    createTicket: async (_client, payload) => {
      createdTicketPayload = payload;
      return 'ticket-1';
    },
    updateTicketAfterCreate: async () => {},
    createMessage: async () => 'message-1',
    insertStatusHistory: async () => {},
    upsertReadState: async () => {},
    enqueueOutbox: async () => {},
    getTicketDetail: async () => ({
      id: 'ticket-1',
      ticketCode: 'SUP-TEST-002',
      status: 'OPEN',
      canReply: true,
    }),
  };
  service.redis = null;
  service.notificationService = null;
  service.storageService = null;
  service.wsServer = null;
  service._buildTicketCode = () => 'SUP-TEST-002';

  try {
    const result = await service.createTicket({
      userId: 'user-1',
      subject: 'Past ride issue',
      message: 'Driver was rude',
      rideId: 'ride-1',
      issueGroupId: 'group-1',
      issueSubIssueIds: ['sub-1', 'sub-2'],
      metadata: {
        source: 'past_ride_issue_details_page',
      },
    });

    assert.equal(result.success, true);
    assert.equal(createdTicketPayload.category, 'driver_vehicle_issue');
    assert.equal(createdTicketPayload.metadata.pastRideIssueSelection.issueGroupId, 'group-1');
    assert.deepEqual(
      createdTicketPayload.metadata.pastRideIssueSelection.issueSubIssueIds,
      ['sub-1', 'sub-2'],
    );
  } finally {
    service.repository = originalRepository;
    service.redis = originalRedis;
    service.notificationService = originalNotificationService;
    service.storageService = originalStorageService;
    service.wsServer = originalWsServer;
    service._buildTicketCode = originalBuildTicketCode;
  }
});

test('createTicket rejects mismatched past ride sub-issue selections', async () => {
  const originalRepository = service.repository;
  const originalRedis = service.redis;

  service.repository = {
    getPastRideIssueGroupById: async () => ({
      id: 'group-1',
      title: 'Driver behavior',
      backendCategory: 'driver_vehicle_issue',
    }),
    listPastRideSubIssuesByIds: async () => ([
      { id: 'sub-1', groupId: 'group-2', title: 'Wrong parent' },
    ]),
  };
  service.redis = null;

  try {
    const result = await service.createTicket({
      userId: 'user-1',
      subject: 'Past ride issue',
      message: 'Driver was rude',
      rideId: 'ride-1',
      issueGroupId: 'group-1',
      issueSubIssueIds: ['sub-1'],
    });

    assert.equal(result.success, false);
    assert.equal(result.code, 'SUPPORT_TRIP_SUB_ISSUE_GROUP_MISMATCH');
  } finally {
    service.repository = originalRepository;
    service.redis = originalRedis;
  }
});

test('addMessage persists attachments against message_id and returns attachment metadata', async () => {
  const originalRepository = service.repository;
  const originalRedis = service.redis;
  const originalNotificationService = service.notificationService;
  const originalStorageService = service.storageService;
  const originalWsServer = service.wsServer;

  const createdAttachments = [];
  let createMessagePayload = null;

  service.repository = {
    canAccessTicket: async () => true,
    withTransaction: async (callback) => callback({}),
    getTicketForUpdate: async () => ({
      id: 'ticket-1',
      userId: 'user-1',
      status: 'OPEN',
    }),
    createMessage: async (_client, payload) => {
      createMessagePayload = payload;
      return 'message-1';
    },
    createAttachment: async (_client, payload) => {
      createdAttachments.push(payload);
      return `attachment-${createdAttachments.length}`;
    },
    updateTicketState: async () => {},
    insertStatusHistory: async () => {},
    upsertReadState: async () => {},
    enqueueOutbox: async () => {},
    getTicketDetail: async () => ({
      id: 'ticket-1',
      status: 'OPEN',
      canReply: true,
    }),
    listMessages: async () => ([{
      id: 'message-1',
      ticketId: 'ticket-1',
      attachments: [{
        id: 'attachment-1',
        fileName: 'proof.png',
        mimeType: 'image/png',
        sizeBytes: 4,
        downloadUrl: '/api/v1/tickets/ticket-1/attachments/attachment-1',
      }],
      messageType: 'user',
      senderRole: 'user',
      senderDisplayName: 'You',
      senderId: 'user-1',
      content: 'See screenshot',
      createdAt: new Date().toISOString(),
      readByCurrentActor: true,
    }]),
  };
  service.redis = null;
  service.notificationService = null;
  service.storageService = {
    save: async () => ({
      storageBackend: 'local',
      storageKey: 'ticket-1/proof.png',
      safeName: 'proof-safe.png',
      originalName: 'proof.png',
      sizeBytes: 4,
      checksumSha256: 'checksum-1',
    }),
  };
  service.wsServer = null;

  try {
    const result = await service.addMessage('ticket-1', {
      actorId: 'user-1',
      content: 'See screenshot',
      files: [{
        filename: 'proof.png',
        mimeType: 'image/png',
        data: Buffer.from('demo'),
      }],
      isAdmin: false,
      visibility: 'public',
    });

    assert.equal(result.success, true);
    assert.equal(createMessagePayload.attachments.length, 1);
    assert.equal(createdAttachments.length, 1);
    assert.equal(createdAttachments[0].messageId, 'message-1');
    assert.equal(result.data.message.attachments[0].id, 'attachment-1');
  } finally {
    service.repository = originalRepository;
    service.redis = originalRedis;
    service.notificationService = originalNotificationService;
    service.storageService = originalStorageService;
    service.wsServer = originalWsServer;
  }
});
