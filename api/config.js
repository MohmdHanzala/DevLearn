module.exports = function handler(req, res) {
  res.statusCode = req.method === 'GET' ? 200 : 405;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'GET') return res.end(JSON.stringify({ error: 'Use GET.' }));
  const supabaseKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '';
  res.end(JSON.stringify({ supabaseUrl: process.env.SUPABASE_URL || '', supabaseKey }));
};
