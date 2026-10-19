module.exports = function handler(req, res) {
  res.statusCode = req.method === 'GET' ? 200 : 405;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'GET') return res.end(JSON.stringify({ error: 'Use GET.' }));
  // These are public browser credentials. Database access is protected by Supabase RLS.
  const supabaseKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '';
  const supabaseUrl = process.env.SUPABASE_URL || '';
  const missing = [!supabaseUrl && 'SUPABASE_URL', !supabaseKey && 'SUPABASE_PUBLISHABLE_KEY'].filter(Boolean);
  if (missing.length) {
    res.statusCode = 503;
    return res.end(JSON.stringify({ code: 'SUPABASE_ENVIRONMENT_MISSING', error: `Vercel is missing ${missing.join(', ')}. Add the variables to Production and redeploy.` }));
  }
  res.end(JSON.stringify({ supabaseUrl, supabaseKey }));
};
