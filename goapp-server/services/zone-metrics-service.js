'use strict';

const repo = require('../repositories/pg/pg-zone-metrics-repository');
const { logger } = require('../utils/logger');

class ZoneMetricsService {
  async recordRequested({ zoneId, riderId, eventTime = new Date().toISOString() }) {
    if (!zoneId) return;
    await repo.recordRequested({ zoneId, riderId, eventTime });
    await repo.refreshDailyPeaks(this._metricDate(eventTime), zoneId);
  }

  async recordCompleted({ zoneId, riderId, eventTime = new Date().toISOString(), fareInr = null, waitSec = null, tripSec = null }) {
    if (!zoneId) return;
    await repo.recordCompleted({ zoneId, riderId, eventTime, fareInr, waitSec, tripSec });
    await repo.refreshDailyPeaks(this._metricDate(eventTime), zoneId);
  }

  async recordCancelled({ zoneId, riderId, eventTime = new Date().toISOString() }) {
    if (!zoneId) return;
    await repo.recordCancelled({ zoneId, riderId, eventTime });
    await repo.refreshDailyPeaks(this._metricDate(eventTime), zoneId);
  }

  async recordNoDriver({ zoneId, riderId, eventTime = new Date().toISOString() }) {
    if (!zoneId) return;
    await repo.recordNoDriver({ zoneId, riderId, eventTime });
    await repo.refreshDailyPeaks(this._metricDate(eventTime), zoneId);
  }

  async getHourly({ zoneId, from, to }) {
    return repo.getHourly({ zoneId, from, to });
  }

  async getSummaryByDate(metricDate) {
    return repo.getSummaryByDate(metricDate);
  }

  async getPeaksByDate(metricDate) {
    await repo.refreshDailyPeaks(metricDate);
    return repo.getPeaksByDate(metricDate);
  }

  async reconcileFromRides() {
    await repo.reconcileFromRides();
    logger.info('ZONE_METRICS', 'Reconciled hourly zone metrics from rides table');
  }

  _metricDate(eventTime) {
    const d = new Date(eventTime);
    const fmt = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Kolkata',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
    return fmt.format(d);
  }
}

module.exports = new ZoneMetricsService();

