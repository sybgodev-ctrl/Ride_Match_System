// GoApp Driver Wallet Service — PostgreSQL via pg-driver-wallet-repository
//
// Rules:
//   - Driver must maintain minimum ₹300 balance to receive ride requests
//   - If balance drops below ₹300, driver is blocked from accepting rides
//   - Driver can recharge wallet via UPI/Card/NetBanking
//   - Platform deducts commission from driver wallet after each ride
//   - Admin can credit/debit driver wallet

const { logger, eventBus } = require('../utils/logger');
const pgRepo = require('../repositories/pg/pg-driver-wallet-repository');

const DRIVER_MIN_BALANCE = parseFloat(process.env.DRIVER_MIN_WALLET_BALANCE || '300');

class DriverWalletService {
  // ─── Check if driver can receive rides ───────────────────────────────────
  async canReceiveRide(driverId) {
    const row = await pgRepo.getBalance(driverId);
    const balance = row ? parseFloat(row.balance || 0) : 0;
    const eligible = balance >= DRIVER_MIN_BALANCE;
    return {
      eligible,
      balance,
      minRequired: DRIVER_MIN_BALANCE,
      shortfall: eligible ? 0 : Math.round((DRIVER_MIN_BALANCE - balance) * 100) / 100,
      message: eligible
        ? 'Driver is eligible to receive rides.'
        : `Wallet balance ₹${balance} is below minimum ₹${DRIVER_MIN_BALANCE}. Please recharge to receive rides.`,
    };
  }

  // ─── Get driver wallet balance ────────────────────────────────────────────
  async getBalance(driverId) {
    const row = await pgRepo.getBalance(driverId);
    if (!row) return { driverId, balance: 0, minRequired: DRIVER_MIN_BALANCE, canReceiveRide: false, shortfall: DRIVER_MIN_BALANCE };
    const balance = parseFloat(row.balance || 0);
    return {
      driverId,
      balance,
      minRequired: DRIVER_MIN_BALANCE,
      canReceiveRide: balance >= DRIVER_MIN_BALANCE,
      shortfall: balance < DRIVER_MIN_BALANCE ? Math.round((DRIVER_MIN_BALANCE - balance) * 100) / 100 : 0,
      totalEarned: parseFloat(row.total_earned || 0),
      totalDeducted: parseFloat(row.total_deducted || 0),
    };
  }

  // ─── Deduct commission/platform fee from driver wallet ───────────────────
  async deductCommission(driverId, amount, rideId, reason = 'platform_commission') {
    if (!amount || amount <= 0) return { success: false, error: 'Invalid deduction amount.' };

    const tx = { type: 'commission_deduction', amountInr: amount, rideId, reason, createdAt: new Date().toISOString() };

    const row = await pgRepo.adjustAndRecord(driverId, -amount, tx).catch(err => {
      logger.warn('DRIVER_WALLET', `pg deductCommission failed: ${err.message}`);
      return null;
    });
    const balance = row ? parseFloat(row.balance) : 0;
    const belowMin = balance < DRIVER_MIN_BALANCE;
    if (belowMin) eventBus.publish('driver_wallet_low', { driverId, balance, minRequired: DRIVER_MIN_BALANCE });
    logger.info('DRIVER_WALLET', `Driver ${driverId} commission ₹${amount} deducted (ride ${rideId})`);
    return { success: true, transaction: { txId: `DRV-COM-${Date.now()}`, ...tx }, balance, canReceiveRide: !belowMin };
  }

  // ─── Credit earnings to driver wallet (ride fare share) ──────────────────
  async creditEarnings(driverId, amount, rideId, reason = 'ride_earnings') {
    if (!amount || amount <= 0) return { success: false, error: 'Invalid earnings amount.' };

    const tx = { type: 'ride_earnings', amountInr: amount, rideId, reason, createdAt: new Date().toISOString() };

    const row = await pgRepo.adjustAndRecord(driverId, amount, tx).catch(err => {
      logger.warn('DRIVER_WALLET', `pg creditEarnings failed: ${err.message}`);
      return null;
    });
    const balance = row ? parseFloat(row.balance) : 0;
    eventBus.publish('driver_earnings_credited', { driverId, amount, rideId, balance });
    logger.info('DRIVER_WALLET', `Driver ${driverId} earned ₹${amount} (ride ${rideId})`);
    return { success: true, transaction: { txId: `DRV-EARN-${Date.now()}`, ...tx }, balance };
  }

  // ─── Global stats ─────────────────────────────────────────────────────────
  async getStats() {
    return pgRepo.getStats();
  }
}

module.exports = new DriverWalletService();
