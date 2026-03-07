function registerWalletRoutes(router, ctx) {
  const { repositories } = ctx;
  const requireAuth = ctx.requireAuth;

  async function ensureWalletOwner(headers, userId) {
    const auth = await requireAuth(headers || {});
    if (auth.error) return { error: auth.error };
    if (auth.session.userId !== userId) {
      return { error: { status: 403, data: { error: 'Forbidden: cannot access another user wallet.' } } };
    }
    return { session: auth.session };
  }

  router.register('GET', '/api/v1/wallet/:userId/balance', async ({ pathParams, headers }) => {
    const auth = await ensureWalletOwner(headers, pathParams.userId);
    if (auth.error) return auth.error;
    const balance = await repositories.wallet.getBalance(pathParams.userId);
    return { data: balance };
  });

  router.register('GET', '/api/v1/wallet/:userId/transactions', async ({ pathParams, params, headers }) => {
    const auth = await ensureWalletOwner(headers, pathParams.userId);
    if (auth.error) return auth.error;
    const transactions = await repositories.wallet.getTransactions(
      pathParams.userId,
      parseInt(params.get('limit') || '50', 10)
    );
    return {
      data: { transactions },
    };
  });

  router.register('POST', '/api/v1/wallet/:userId/pay', async ({ pathParams, body, headers }) => {
    const auth = await ensureWalletOwner(headers, pathParams.userId);
    if (auth.error) return auth.error;
    if (!body.fareInr || body.fareInr <= 0) return { status: 400, data: { error: 'fareInr required' } };
    const result = await repositories.wallet.payRide(pathParams.userId, body.fareInr, body.rideId);
    return { status: result.success ? 200 : 400, data: result };
  });

  router.register('POST', '/api/v1/wallet/:userId/refund', async ({ pathParams, body, headers }) => {
    const auth = await ensureWalletOwner(headers, pathParams.userId);
    if (auth.error) return auth.error;
    if (!body.amount || body.amount <= 0) return { status: 400, data: { error: 'amount required' } };
    const result = await repositories.wallet.refund(pathParams.userId, body.amount, body.rideId, body.reason);
    return { status: result.success ? 200 : 400, data: result };
  });
}

module.exports = registerWalletRoutes;
