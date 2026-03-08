'use strict';

const pgRepo = require('../repositories/pg/pg-identity-repository');

function registerProfileRoutes(router, ctx) {
  const { requireAuth } = ctx;

  // POST /api/v1/profile/create  — save/update rider profile
  const createProfileHandler = async ({ body, headers }) => {
    const authResult = await requireAuth(headers);
    if (authResult.error) return authResult.error;

    const { userId } = authResult.session;
    const name             = String(body?.name || '').trim();
    const gender           = String(body?.gender || '').trim();
    const email            = String(body?.email || '').trim();
    const emergencyContact = String(body?.emergency_contact || '').trim();

    if (!name || !gender) {
      return {
        status: 400,
        data: { success: false, message: 'name and gender are required' },
      };
    }

    await pgRepo.upsertUserProfile({ userId, name, gender, emergencyContact });
    if (email) {
      await pgRepo.updateUserEmail(userId, email);
    }

    return {
      status: 200,
      data: {
        id: userId,
        name,
        gender,
        email,
        emergency_contact: emergencyContact,
      },
    };
  };

  // GET /api/v1/profile  — fetch current rider profile
  const getProfileHandler = async ({ headers }) => {
    const authResult = await requireAuth(headers);
    if (authResult.error) return authResult.error;

    const { userId } = authResult.session;
    const profile = await pgRepo.getUserProfile(userId);
    const user    = await pgRepo.getUserById(userId);

    if (!profile) {
      return {
        status: 404,
        data: { success: false, message: 'Profile not found' },
      };
    }

    return {
      status: 200,
      data: {
        id: userId,
        name:              profile.name || '',
        gender:            profile.gender || '',
        email:             user?.email || '',
        emergency_contact: profile.emergency_contact || '',
      },
    };
  };

  router.register('POST', '/api/v1/profile/create', createProfileHandler);
  router.register('GET',  '/api/v1/profile',        getProfileHandler);
}

module.exports = registerProfileRoutes;
