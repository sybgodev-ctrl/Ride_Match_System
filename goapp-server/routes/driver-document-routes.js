// Driver Document Routes
// Endpoints for uploading, listing, verifying, and serving driver KYC documents.

function registerDriverDocumentRoutes(router, ctx) {
  const { services, requireAdmin, requireAuth } = ctx;
  const docService = services.driverDocumentService;

  function hasAdminToken(headers) {
    return Boolean((headers || {})['x-admin-token']);
  }

  async function ensureDocumentAccess(headers, driverId) {
    const reqHeaders = headers || {};
    if (hasAdminToken(reqHeaders)) {
      const adminCheck = requireAdmin(reqHeaders);
      if (adminCheck) return adminCheck;
      return null;
    }

    const auth = await requireAuth(reqHeaders);
    if (auth.error) return auth.error;
    if (auth.session.userId !== driverId) {
      return { status: 403, data: { error: 'Forbidden: cannot access another driver documents.' } };
    }
    return null;
  }

  // ─── Upload a document (multipart/form-data) ───
  // Fields: document_type, document_number (optional), expiry_date (optional)
  // File field: file
  router.register('POST', '/api/v1/drivers/:driverId/documents', async ({ pathParams, body, files, headers }) => {
    const { driverId } = pathParams;
    const accessError = await ensureDocumentAccess(headers, driverId);
    if (accessError) return accessError;

    const documentType = body.document_type;
    const documentNumber = body.document_number || null;
    const expiryDate = body.expiry_date || null;

    if (!documentType) return { status: 400, data: { error: 'document_type field is required' } };
    if (!files || files.length === 0) return { status: 400, data: { error: 'A file must be uploaded in the "file" field' } };

    const uploaded = files.find(f => f.fieldName === 'file');
    if (!uploaded) return { status: 400, data: { error: 'No "file" field found in upload' } };

    const result = await docService.uploadDocument(driverId, {
      documentType,
      documentNumber,
      expiryDate,
      filename: uploaded.filename || 'document',
      mimeType: uploaded.mimeType,
      buffer: uploaded.data,
    });

    if (!result.success) return { status: result.status || 400, data: { error: result.error } };
    return { status: 201, data: result.document };
  });

  // ─── List all documents for a driver ───
  router.register('GET', '/api/v1/drivers/:driverId/documents', async ({ pathParams, headers }) => {
    const accessError = await ensureDocumentAccess(headers, pathParams.driverId);
    if (accessError) return accessError;
    const result = docService.listDocuments(pathParams.driverId);
    return { data: result };
  });

  // ─── Get a single document record ───
  router.register('GET', '/api/v1/drivers/:driverId/documents/:docId', async ({ pathParams, headers }) => {
    const { driverId, docId } = pathParams;
    const accessError = await ensureDocumentAccess(headers, driverId);
    if (accessError) return accessError;

    const result = docService.getDocument(driverId, docId);
    if (!result.success) return { status: result.status || 404, data: { error: result.error } };
    return { data: result.document };
  });

  // ─── Serve the raw file (binary) ───
  // Returns { raw: true, ... } — server.js handles sending binary response.
  router.register('GET', '/api/v1/drivers/:driverId/documents/:docId/file', async ({ pathParams, headers }) => {
    const { driverId, docId } = pathParams;
    const accessError = await ensureDocumentAccess(headers, driverId);
    if (accessError) return accessError;

    const result = await docService.getDocumentFile(driverId, docId);
    if (!result.success) return { status: result.status || 404, data: { error: result.error } };
    return {
      raw: true,
      contentType: result.mimeType,
      filename: result.filename,
      buffer: result.buffer,
    };
  });

  // ─── Admin: verify or reject a document ───
  // Body: { status: 'verified'|'rejected'|'expired', rejection_reason?, verified_by? }
  router.register('PUT', '/api/v1/drivers/:driverId/documents/:docId/verify', async ({ pathParams, body, headers }) => {
    const adminCheck = requireAdmin(headers);
    if (adminCheck) return adminCheck;

    const { docId } = pathParams;
    const { status, rejection_reason, verified_by } = body;

    if (!status) return { status: 400, data: { error: 'status is required' } };

    const result = docService.verifyDocument(docId, status, rejection_reason || null, verified_by || 'admin');
    if (!result.success) return { status: result.status || 400, data: { error: result.error } };
    return { data: result.document };
  });

  // ─── Delete a document ───
  router.register('DELETE', '/api/v1/drivers/:driverId/documents/:docId', async ({ pathParams, headers }) => {
    const { driverId, docId } = pathParams;
    const accessError = await ensureDocumentAccess(headers, driverId);
    if (accessError) return accessError;

    const result = await docService.deleteDocument(driverId, docId);
    if (!result.success) return { status: result.status || 400, data: { error: result.error } };
    return { data: result };
  });
}

module.exports = registerDriverDocumentRoutes;
