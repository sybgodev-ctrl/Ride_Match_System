'use strict';

const config = require('../config');
const pgWalletRepository = require('../repositories/pg/pg-wallet-repository');
const walletService = require('./wallet-service');

class CoinsService {
  async _getPolicy() {
    const fallback = {
      coinInrValue: Number.parseFloat(config?.coins?.coinInrValue || '0.10') || 0.1,
      coinsPerInrEarn: Number.parseFloat(config?.coins?.coinsPerInrEarn || '10') || 10,
      minRedeemCoins: Number.parseInt(config?.coins?.minRedeemCoins || '10', 10) || 10,
      maxRedeemPct: Number.parseFloat(config?.coins?.maxRedeemPct || '0.20') || 0.2,
    };

    try {
      return {
        ...fallback,
        ...(await pgWalletRepository.getCoinPolicy()),
      };
    } catch (_) {
      return fallback;
    }
  }

  async _getAutoUseEnabled(userId) {
    return pgWalletRepository.getCoinAutoUsePreference(userId);
  }

  async getCoinsBalance(userId) {
    const [balance, autoUseEnabled, policy] = await Promise.all([
      walletService.getBalance(userId),
      this._getAutoUseEnabled(userId),
      this._getPolicy(),
    ]);

    return {
      userId,
      totalCoins: Math.max(0, Math.floor(Number(balance.coinBalance || 0))),
      autoUseEnabled,
      conversionRate: policy.coinInrValue,
      maxDiscountPct: policy.maxRedeemPct,
      minRedeemCoins: policy.minRedeemCoins,
    };
  }

  async getCoinsHistory(userId, { page = 1, limit = 20 } = {}) {
    const rows = await pgWalletRepository.getCoinTransactions(userId, page, limit);
    return rows.map((row) => {
      const type = String(row.type || '').toLowerCase();
      const coins = Number(row.coins || 0);
      const normalizedType =
        type.includes('redeem') || coins < 0
          ? 'spent'
          : (type.includes('earn') || type.includes('reward') || type.includes('credit'))
            ? 'earned'
            : 'adjusted';
      return {
        txId: row.txId,
        type: normalizedType,
        coins: Math.abs(Math.trunc(coins)),
        signedCoins: Math.trunc(coins),
        referenceType: row.referenceType || null,
        referenceId: row.referenceId || null,
        description: row.description || null,
        createdAt: typeof row.createdAt === 'number'
          ? new Date(row.createdAt).toISOString()
          : new Date(Number(row.createdAt || Date.now())).toISOString(),
      };
    });
  }

  async setAutoUse(userId, enabled) {
    const next = await pgWalletRepository.setCoinAutoUsePreference(userId, enabled === true);
    return this.getCoinsBalance(userId).then((balance) => ({
      ...balance,
      autoUseEnabled: next,
    }));
  }

  async previewRideDiscount(userId, {
    fareInr,
    rideId = null,
    rideType = null,
    autoUse = null,
    requestedCoins = null,
  } = {}) {
    const numericFare = Number(fareInr || 0);
    const policy = await this._getPolicy();
    const [balance, storedAutoUse] = await Promise.all([
      walletService.getBalance(userId),
      this._getAutoUseEnabled(userId),
    ]);

    const availableCoins = Math.max(0, Math.floor(Number(balance.coinBalance || 0)));
    const autoUseEnabled = autoUse == null ? storedAutoUse : autoUse === true;

    let appliedCoins = 0;
    if (autoUseEnabled && numericFare > 0 && availableCoins >= policy.minRedeemCoins) {
      const maxByFare = Math.floor((numericFare * policy.maxRedeemPct) / policy.coinInrValue);
      const requested = requestedCoins == null
        ? availableCoins
        : Math.max(0, Math.floor(Number(requestedCoins)));
      appliedCoins = Math.min(availableCoins, maxByFare, requested);
    }

    const coinsDiscountAmount = Number((appliedCoins * policy.coinInrValue).toFixed(2));
    const payableFare = Number(Math.max(0, numericFare - coinsDiscountAmount).toFixed(2));

    return {
      enabled: true,
      rideId,
      rideType,
      fareInr: Number(numericFare.toFixed(2)),
      autoUseEnabled,
      conversionRate: policy.coinInrValue,
      maxDiscountPct: policy.maxRedeemPct,
      minRedeemCoins: policy.minRedeemCoins,
      availableCoins,
      appliedCoins,
      coinsDiscountAmount,
      payableFare,
    };
  }

  async toRideCoinsQuote(userId, fareInr, rideMeta = {}) {
    return this.previewRideDiscount(userId, {
      fareInr,
      rideId: rideMeta.rideId || null,
      rideType: rideMeta.rideType || null,
      autoUse: null,
      requestedCoins: null,
    });
  }
}

module.exports = new CoinsService();
