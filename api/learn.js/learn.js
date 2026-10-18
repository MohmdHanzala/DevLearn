function send(res, status, payload) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(payload));
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return send(res, 405, { error: 'Use POST.' });
  const origin = req.headers.origin;
  const host = req.headers.host;
  if (origin && host && new URL(origin).host !== host) return send(res, 403, { error: 'Cross-origin requests are not allowed.' });

  const supabaseUrl = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;
  const geminiKey = process.env.GEMINI_API_KEY;
  if (!supabaseUrl || !anonKey || !geminiKey) return send(res, 503, { error: 'AI service is not configured yet. Add the Supabase and Gemini environment variables in Vercel.' });

  const auth = req.headers.authorization || '';
  if (!auth.startsWith('Bearer ')) return send(res, 401, { error: 'Sign in to use the learning assistant.' });
  try {
    const userUrl = supabaseUrl.replace(/\/$/, '') + '/auth/v1/user';
    const userResponse = await fetch(userUrl, {
      headers: { apikey: anonKey, Authorization: auth }
    });
    if (!userResponse.ok) return send(res, 401, { error: 'Your session has expired. Please sign in again.' });
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const question = typeof body.question === 'string' ? body.question.trim().slice(0, 3000) : '';
    const mode = body.mode === 'practice' ? 'practice' : 'explain';
    if (!question) return send(res, 400, { error: 'Add a question to continue.' });

    const system = mode === 'practice'
      ? 'Create one short, practical developer learning exercise from the requested technology and focus. Return ONLY valid JSON with keys question (string), options (array of exactly 3 short strings), answer (integer 0, 1, or 2), explanation (string), and hint (string). Use fictional examples and do not invent facts about the user’s environment.'
      : 'You are DevLearn, a careful developer learning companion. Teach through practical examples. Start with a concise explanation, then concepts to check, a step-by-step investigation, and one question for the learner. For debugging, give plausible causes as hypotheses, never claim an unverified diagnosis. Prefer safe, fictional examples. Do not claim access to the user’s actual systems or code.';
    const response = await fetch('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=' + encodeURIComponent(geminiKey), {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ system_instruction: { parts: [{ text: system }] }, contents: [{ role: 'user', parts: [{ text: question }] }], generationConfig: { temperature: 0.45, maxOutputTokens: 1400 } })
    });
    const result = await response.json();
    if (!response.ok) return send(res, response.status === 429 ? 429 : 502, { error: 'The AI service could not complete that request. Please try again shortly.' });
    const text = result.candidates?.[0]?.content?.parts?.map(part => part.text || '').join('').trim();
    if (!text) return send(res, 502, { error: 'The AI service returned an empty response. Try rephrasing your question.' });
    return send(res, 200, { text });
  } catch (error) {
    return send(res, 502, { error: 'Could not reach the AI service. Check the deployment configuration and try again.' });
  }
};
