'use strict';

const repo = require('../repositories/pg/pg-saved-locations-repository');

// Hard cap on saved locations per rider to prevent unbounded DB growth.
const MAX_SAVED_LOCATIONS = 50;

/**
 * Business logic for rider saved locations.
 * Enforces label uniqueness and per-rider location cap.
 * Database access is delegated entirely to the repository.
 */
class SavedLocationsService {
  // ── list ──────────────────────────────────────────────────────────────────
  async list(userId) {
    return repo.listByRider(userId);
  }

  // ── add ───────────────────────────────────────────────────────────────────
  async add(userId, { label, address, lat, lng, placeId, iconKey }) {
    const existing = await repo.listByRider(userId);

    // Enforce per-rider cap
    if (existing.length >= MAX_SAVED_LOCATIONS) {
      const err = new Error(`You can save at most ${MAX_SAVED_LOCATIONS} locations.`);
      err.code = 'LOCATIONS_LIMIT';
      throw err;
    }

    // Enforce case-insensitive label uniqueness
    const labelNorm = label.trim().toLowerCase();
    if (existing.some((loc) => loc.label.toLowerCase() === labelNorm)) {
      const err = new Error(`A saved location with label "${label}" already exists.`);
      err.code = 'LABEL_DUPLICATE';
      throw err;
    }

    return repo.create({
      userId,
      label:   label.trim(),
      address,
      lat,
      lng,
      placeId: placeId || null,
      iconKey: iconKey || 'bookmark',
    });
  }

  // ── update ────────────────────────────────────────────────────────────────
  async update(id, userId, updates) {
    // If label is changing, check uniqueness excluding the record being updated
    if (updates.label !== undefined) {
      const existing  = await repo.listByRider(userId);
      const labelNorm = updates.label.trim().toLowerCase();
      const conflict  = existing.find(
        (loc) => loc.label.toLowerCase() === labelNorm && loc.id !== id,
      );
      if (conflict) {
        const err = new Error(`A saved location with label "${updates.label}" already exists.`);
        err.code = 'LABEL_DUPLICATE';
        throw err;
      }
      updates = { ...updates, label: updates.label.trim() };
    }

    return repo.update(id, userId, updates);
  }

  // ── remove ────────────────────────────────────────────────────────────────
  async remove(id, userId) {
    return repo.remove(id, userId);
  }

  // ── incrementUsage ────────────────────────────────────────────────────────
  async incrementUsage(id, userId) {
    return repo.incrementUsage(id, userId);
  }
}

module.exports = new SavedLocationsService();
