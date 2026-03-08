// GoApp Driver Wallet Service
//
// Rules:
//   - Driver must maintain minimum ₹300 balance to receive ride requests
//   - If balance drops below ₹300, driver is blocked from accepting rides
//   - Driver can recharge wallet via UPI/Card/NetBanking
//   - Platform deducts commission from driver wallet after each ride
//   - Admin can credit/debit driver wallet

const config = require('../config');
const { logger, eventBus } = require('../utils/logger');

const USE_PG = config.db.backend === 'pg';
const pgRepo = USE_PG ? require('../repositories/pg/pg-driver-wallet-repository') : null;

const DRIVER_MIN_BALANCE = parseFloat(process.env.DRIVER_MIN_WALLET_BALANCE || '300');

class DriverWalletService {
  constructor() {
    // driverId -> { balance, transactions[], isBlocked }
    this.wallets = new Map();
  }

  // ─── Internal: get or create driver wallet ───────────────────────────────
  _getWallet(driverId) {
    if (!this.wallets.has(driverId)) {
      this.wallets.set(driverId, {
        driverId,
        balance: 0,
        transactions: [],
        isBlocked: true,   // blocked until they recharge above minimum
        totalEarned: 0,
        totalDeducted: 0,
      });
    }
    return this.wallets.get(driverId);
  }

  // ─── Check if driver can receive rides ───────────────────────────────────
  canReceiveRide(driverId) {
    const wallet = this._getWallet(driverId);
    const eligible = wallet.balance >= DRIVER_MIN_BALANCE;
    return {
      eligible,
      balance: wallet.balance,
      minRequired: DRIVER_MIN_BALANCE,
      shortfall: eligible ? 0 : Math.round((DRIVER_MIN_BALANCE - wallet.balance) * 100) / 100,
      message: eligible
        ? 'Driver is eligible to receive rides.'
        : `Wallet balance ₹${wallet.balance} is below minimum ₹${DRIVER_MIN_BALANCE}. Please recharge to receive rides.`,
    };
  }

  // ─── Get driver wallet balance ────────────────────────────────────────────
  async getBalance(driverId) {
    if (USE_PG) {
      const row = await pgRepo.getBalance(driverId);
      if (!row) return { driverId, balance: 0, minRequired: DRIVER_MIN_BALANCE, canReceiveRide: false, shortfall: DRIVER_MIN_BALANCE };
      const balance = parseFloat(row.balance || 0);
      return { driverId, balance, minRequired: DRIVER_MIN_BALANCE, canReceiveRide: balance >= DRIVER_MIN_BALANCE, shortfall: balance < DRIVER_MIN_BALANCE ? Math.round((DRIVER_MIN_BALANCE - balance) * 100) / 100 : 0, totalEarned: parseFloat(row.total_earned || 0), totalDeducted: parseFloat(row.total_deducted || 0) };
    }
    const wallet = this._getWallet(driverId);
    return { driverId, balance: wallet.balance, minRequired: DRIVER_MIN_BALANCE, canReceiveRide: wallet.balance >= DRIVER_MIN_BALANCE, shortfall: wallet.balance < DRIVER_MIN_BALANCE ? Math.round((DRIVER_MIN_BALANCE - wallet.balance) * 100) / 100 : 0, totalEarned: wallet.totalEarned, totalDeducted: wallet.totalDeducted };
  }

  // ─── Driver recharges wallet ──────────────────────────────────────────────
  rechargeWallet(driverId, amount, method = 'upi', referenceId = null) {
    if (!amount || amount <= 0) {
      return { success: false, error: 'Invalid recharge amount.' };
    }
    if (amount > 100000) {
      return { success: false, error: 'Max recharge per transaction is ₹1,00,000.' };
    }

    const wallet = this._getWallet(driverId);
    const prevBalance = wallet.balance;
    wallet.balance = Math.round((wallet.balance + amount) * 100) / 100;
    wallet.totalEarned += amount;

    const wasBlocked = prevBalance < DRIVER_MIN_BALANCE;
    const nowEligible = wallet.balance >= DRIVER_MIN_BALANCE;

    const tx = {
      txId: `DRV-TOPUP-${Date.now()}`,
      type: 'recharge',
      amountInr: amount,
      method,
      referenceId,
      balanceAfter: wallet.balance,
      createdAt: new Date().toISOString(),
    };
    wallet.transactions.push(tx);

    eventBus.publish('driver_wallet_recharged', {
      driverId,
      amount,
      method,
      balance: wallet.balance,
      nowEligible,
    });

    logger.info('DRIVER_WALLET', `Driver ${driverId} recharged ₹${amount} via ${method}. Balance: ₹${wallet.balance}`);

    if (wasBlocked && nowEligible) {
      logger.info('DRIVER_WALLET', `Driver ${driverId} is now eligible to receive rides.`);
      eventBus.publish('driver_ride_eligible', { driverId, balance: wallet.balance });
    }

    return {
      success: true,
      transaction: tx,
      balance: wallet.balance,
      canReceiveRide: nowEligible,
      message: nowEligible
        ? 'Recharge successful. You can now receive ride requests.'
        : `Recharge successful. Add ₹${Math.round((DRIVER_MIN_BALANCE - wallet.balance) * 100) / 100} more to start receiving rides.`,
    };
  }

  // ─── Deduct commission/platform fee from driver wallet ───────────────────
  async deductCommission(driverId, amount, rideId, reason = 'platform_commission') {
    if (!amount || amount <= 0) return { success: false, error: 'Invalid deduction amount.' };

    const tx = { type: 'commission_deduction', amountInr: amount, rideId, reason, createdAt: new Date().toISOString() };

    if (USE_PG) {
      const row = await pgRepo.adjustAndRecord(driverId, -amount, tx).catch(err => { logger.warn('DRIVER_WALLET', `pg deductCommission failed: ${err.message}`); return null; });
      const balance = row ? parseFloat(row.balance) : 0;
      const belowMin = balance < DRIVER_MIN_BALANCE;
      if (belowMin) eventBus.publish('driver_wallet_low', { driverId, balance, minRequired: DRIVER_MIN_BALANCE });
      logger.info('DRIVER_WALLET', `Driver ${driverId} commission ₹${amount} deducted (ride ${rideId})`);
      return { success: true, transaction: { txId: `DRV-COM-${Date.now()}`, ...tx }, balance, canReceiveRide: !belowMin };
    }

    const wallet = this._getWallet(driverId);
    wallet.balance = Math.max(0, Math.round((wallet.balance - amount) * 100) / 100);
    wallet.totalDeducted += amount;
    const fullTx = { txId: `DRV-COM-${Date.now()}`, ...tx, balanceAfter: wallet.balance };
    wallet.transactions.push(fullTx);

    const belowMin = wallet.balance < DRIVER_MIN_BALANCE;
    if (belowMin) {
      eventBus.publish('driver_wallet_low', { driverId, balance: wallet.balance, minRequired: DRIVER_MIN_BALANCE, shortfall: Math.round((DRIVER_MIN_BALANCE - wallet.balance) * 100) / 100 });
      logger.warn('DRIVER_WALLET', `Driver ${driverId} wallet below minimum after commission. Balance: ₹${wallet.balance}. Rides blocked until recharge.`);
    }
    return { success: true, transaction: fullTx, balance: wallet.balance, canReceiveRide: !belowMin, warning: belowMin ? `Balance below ₹${DRIVER_MIN_BALANCE}. Recharge to continue receiving rides.` : null };
  }

  // ─── Credit earnings to driver wallet (ride fare share) ──────────────────
  async creditEarnings(driverId, amount, rideId, reason = 'ride_earnings') {
    if (!amount || amount <= 0) return { success: false, error: 'Invalid earnings amount.' };

    const tx = { type: 'ride_earnings', amountInr: amount, rideId, reason, createdAt: new Date().toISOString() };

    if (USE_PG) {
      const row = await pgRepo.adjustAndRecord(driverId, amount, tx).catch(err => { logger.warn('DRIVER_WALLET', `pg creditEarnings failed: ${err.message}`); return null; });
      const balance = row ? parseFloat(row.balance) : 0;
      eventBus.publish('driver_earnings_credited', { driverId, amount, rideId, balance });
      logger.info('DRIVER_WALLET', `Driver ${driverId} earned ₹${amount} (ride ${rideId})`);
      return { success: true, transaction: { txId: `DRV-EARN-${Date.now()}`, ...tx }, balance };
    }

    const wallet = this._getWallet(driverId);
    wallet.balance = Math.round((wallet.balance + amount) * 100) / 100;
    wallet.totalEarned += amount;
    const fullTx = { txId: `DRV-EARN-${Date.now()}`, ...tx, balanceAfter: wallet.balance };
    wallet.transactions.push(fullTx);
    eventBus.publish('driver_earnings_credited', { driverId, amount, rideId, balance: wallet.balance });
    logger.info('DRIVER_WALLET', `Driver ${driverId} earned ₹${amount} (ride ${rideId}). Balance: ₹${wallet.balance}`);
    return { success: true, transaction: fullTx, balance: wallet.balance };
  }

  // ─── Credit incentive/bonus to driver wallet ─────────────────────────────
  creditIncentive(driverId, amount, incentiveId, reason = 'incentive_bonus') {
    if (!amount || amount <= 0) return { success: false, error: 'Invalid incentive amount.' };

    const wallet = this._getWallet(driverId);
    wallet.balance = Math.round((wallet.balance + amount) * 100) / 100;
    wallet.totalEarned += amount;

    const tx = {
      txId: `DRV-INC-${Date.now()}`,
      type: 'incentive_credit',
      amountInr: amount,
      incentiveId,
      reason,
      balanceAfter: wallet.balance,
      createdAt: new Date().toISOString(),
    };
    wallet.transactions.push(tx);

    eventBus.publish('driver_incentive_credited', { driverId, amount, incentiveId, balance: wallet.balance });
    logger.info('DRIVER_WALLET', `Driver ${driverId} incentive ₹${amount} (${reason}). Balance: ₹${wallet.balance}`);

    return { success: true, transaction: tx, balance: wallet.balance };
  }

  // ─── Admin: adjust driver wallet ─────────────────────────────────────────
  adminAdjust(driverId, amount, reason) {
    const wallet = this._getWallet(driverId);
    wallet.balance = Math.max(0, Math.round((wallet.balance + amount) * 100) / 100);

    const tx = {
      txId: `DRV-ADJ-${Date.now()}`,
      type: amount >= 0 ? 'admin_credit' : 'admin_debit',
      amountInr: amount,
      reason,
      balanceAfter: wallet.balance,
      createdAt: new Date().toISOString(),
    };
    wallet.transactions.push(tx);

    logger.info('DRIVER_WALLET', `Admin adjusted ₹${amount} for driver ${driverId} (${reason}). Balance: ₹${wallet.balance}`);
    return { success: true, transaction: tx, balance: wallet.balance };
  }

  // ─── Transaction history ──────────────────────────────────────────────────
  getTransactions(driverId, limit = 20) {
    const wallet = this._getWallet(driverId);
    return {
      driverId,
      balance: wallet.balance,
      canReceiveRide: wallet.balance >= DRIVER_MIN_BALANCE,
      transactions: wallet.transactions.slice(-limit).reverse(),
    };
  }

  // ─── Global stats ─────────────────────────────────────────────────────────
  async getStats() {
    if (USE_PG) return pgRepo.getStats();

    let totalBalance = 0, totalDrivers = 0, blockedDrivers = 0;
    this.wallets.forEach(w => { totalBalance += w.balance; totalDrivers++; if (w.balance < DRIVER_MIN_BALANCE) blockedDrivers++; });
    return { totalDrivers, blockedDrivers, eligibleDrivers: totalDrivers - blockedDrivers, totalBalanceInWallets: Math.round(totalBalance * 100) / 100, minBalanceRequired: DRIVER_MIN_BALANCE };
  }
}

module.exports = new DriverWalletService();
