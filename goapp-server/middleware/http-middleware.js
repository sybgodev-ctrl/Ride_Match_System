const config = require('../config');

function applySecurityHeaders(req, res) {
  // Use the explicit CORS origin from config; if unset in production, send no
  // CORS header (most restrictive) rather than falling back to '*'.
  const allowedOrigin = config.security.corsOrigin;
  if (allowedOrigin) {
    res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Session-Token, X-Admin-Token');
  res.setHeader('Access-Control-Expose-Headers', 'Content-Disposition');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Content-Type', 'application/json');
  // Enforce HTTPS in production — tells browsers never to downgrade to HTTP.
  if (process.env.NODE_ENV === 'production') {
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  }
}

async function parseJsonBody(req, maxBodyBytes) {
  if (!['POST', 'PUT', 'DELETE'].includes(req.method)) return {};

  const body = await new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', chunk => {
      size += chunk.length;
      if (size > maxBodyBytes) {
        req.destroy();
        reject(Object.assign(new Error('Request body too large'), { statusCode: 413 }));
        return;
      }
      chunks.push(chunk);
    });
    // Buffer.concat avoids O(n²) string concatenation for large bodies
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });

  if (!body) return {};

  // Throw a SyntaxError so the server's outer catch can return 400.
  try {
    return JSON.parse(body);
  } catch (_) {
    const err = new SyntaxError('Invalid JSON body');
    err.statusCode = 400;
    throw err;
  }
}

// Reads raw body as a Buffer (used for webhook signature verification where we need the
// exact bytes before JSON.parse, so we can recompute the HMAC over the original payload).
async function readRawBody(req, maxBodyBytes) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', chunk => {
      size += chunk.length;
      if (size > maxBodyBytes) {
        req.destroy();
        reject(Object.assign(new Error('Request body too large'), { statusCode: 413 }));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

module.exports = {
  applySecurityHeaders,
  parseJsonBody,
  readRawBody,
};
