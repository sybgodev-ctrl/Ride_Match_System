// GoApp Feedback Routes
// Mutual post-trip ratings: rider → driver and driver → rider

function registerFeedbackRoutes(router, ctx) {
  const { services, repositories, requireAuth, requireAdmin } = ctx;
  const feedbackService = services.feedbackService;

  async function authenticate(headers = {}) {
    const auth = await requireAuth(headers);
    if (auth.error) return { error: auth.error };
    return { session: auth.session };
  }

  function isAdmin(headers = {}) {
    if (!headers['x-admin-token']) return false;
    return !requireAdmin(headers);
  }

  // ─── Rider rates Driver ───
  router.register('POST', '/api/v1/rides/:rideId/feedback/rider', async ({ pathParams, body, headers }) => {
    const auth = await authenticate(headers);
    if (auth.error) return auth.error;

    const { rideId } = pathParams;
    const { raterId, rating, comment } = body;

    if (rating === undefined || rating === null) return { status: 400, data: { error: 'rating is required' } };
    if (raterId && raterId !== auth.session.userId) {
      return { status: 403, data: { error: 'Forbidden: raterId must match authenticated user.' } };
    }

    const result = feedbackService.submitRiderFeedback(rideId, auth.session.userId, rating, comment || '');
    if (!result.success) return { status: result.status || 400, data: { error: result.error } };
    return { data: result };
  });

  // ─── Driver rates Rider ───
  router.register('POST', '/api/v1/rides/:rideId/feedback/driver', async ({ pathParams, body, headers }) => {
    const auth = await authenticate(headers);
    if (auth.error) return auth.error;

    const { rideId } = pathParams;
    const { raterId, rating, comment } = body;

    if (rating === undefined || rating === null) return { status: 400, data: { error: 'rating is required' } };
    if (raterId && raterId !== auth.session.userId) {
      return { status: 403, data: { error: 'Forbidden: raterId must match authenticated user.' } };
    }

    const result = feedbackService.submitDriverFeedback(rideId, auth.session.userId, rating, comment || '');
    if (!result.success) return { status: result.status || 400, data: { error: result.error } };
    return { data: result };
  });

  // ─── Get feedback for a specific ride ───
  router.register('GET', '/api/v1/rides/:rideId/feedback', async ({ pathParams, headers }) => {
    const auth = await authenticate(headers);
    if (auth.error) return auth.error;

    const ride = await repositories.ride.getRide(pathParams.rideId);
    if (!ride) return { status: 404, data: { error: 'Ride not found' } };
    if (!isAdmin(headers) && ride.riderId !== auth.session.userId && ride.driverId !== auth.session.userId) {
      return { status: 403, data: { error: 'Forbidden: cannot access this ride feedback.' } };
    }

    const result = feedbackService.getFeedbackForRide(pathParams.rideId);
    return { data: result };
  });

  // ─── Get all feedback received by a driver ───
  router.register('GET', '/api/v1/drivers/:driverId/feedback', async ({ pathParams, params, headers }) => {
    const auth = await authenticate(headers);
    if (auth.error) return auth.error;

    if (!isAdmin(headers) && auth.session.userId !== pathParams.driverId) {
      return { status: 403, data: { error: 'Forbidden: cannot access another driver feedback.' } };
    }

    const limit = parseInt(params.get('limit') || '50', 10);
    const result = feedbackService.getDriverFeedbacks(pathParams.driverId, limit);
    return { data: result };
  });

  // ─── Get all feedback received by a rider ───
  router.register('GET', '/api/v1/riders/:riderId/feedback', async ({ pathParams, params, headers }) => {
    const auth = await authenticate(headers);
    if (auth.error) return auth.error;

    if (!isAdmin(headers) && auth.session.userId !== pathParams.riderId) {
      return { status: 403, data: { error: 'Forbidden: cannot access another rider feedback.' } };
    }

    const limit = parseInt(params.get('limit') || '50', 10);
    const result = feedbackService.getRiderFeedbacks(pathParams.riderId, limit);
    return { data: result };
  });
}

module.exports = registerFeedbackRoutes;
