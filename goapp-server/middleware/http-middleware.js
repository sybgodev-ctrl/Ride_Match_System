function applySecurityHeaders(req, res) {
  const allowedOrigin = process.env.CORS_ORIGIN || '*';
  res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Session-Token, X-Admin-Token');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Content-Type', 'application/json');
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
  return JSON.parse(body);
}

module.exports = {
  applySecurityHeaders,
  parseJsonBody,
};
