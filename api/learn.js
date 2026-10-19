function send(res, status, payload) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(payload));
}

function geminiError(response, body) {
  const providerStatus = body?.error?.status || 'UNKNOWN';
  const providerMessage = String(body?.error?.message || '').slice(0, 350);
  console.error('Onward Gemini request failed', { httpStatus: response.status, providerStatus, providerMessage });

  if ((response.status === 400 && /api key.*not valid|api_key_invalid/i.test(providerMessage)) || response.status === 401 || response.status === 403) return { status: 503, code: 'GEMINI_KEY_REJECTED', error: 'Google rejected GEMINI_API_KEY. In Vercel, replace it with an active Gemini API key from the correct Google AI Studio project, then redeploy.' };
  if (response.status === 400 && providerStatus === 'FAILED_PRECONDITION') return { status: 503, code: 'GEMINI_PLAN_REQUIRED', error: 'Gemini API is unavailable for this project or region on its current plan. Check the project billing and Gemini API availability in Google AI Studio.' };
  if (response.status === 400) return { status: 400, code: 'GEMINI_REQUEST_INVALID', error: 'Google rejected the request. Check the configured model and request options.' };
  if (response.status === 404) return { status: 503, code: 'GEMINI_MODEL_UNAVAILABLE', error: 'The configured Gemini model is unavailable. Check GEMINI_MODEL in Vercel or remove it to use the default model.' };
  if (response.status === 429) return { status: 429, code: 'GEMINI_QUOTA_EXCEEDED', error: 'The Gemini API quota or rate limit has been reached. Check the Google AI Studio project and retry after its quota resets.' };
  return { status: 502, code: 'GEMINI_TEMPORARY_FAILURE', error: 'Google’s Gemini API is temporarily unavailable. Try again shortly.' };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return send(res, 405, { error: 'Use POST.' });
  const origin = req.headers.origin;
  const host = req.headers.host;
  if (origin && host && new URL(origin).host !== host) return send(res, 403, { error: 'Cross-origin requests are not allowed.' });

  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;
  const geminiKey = process.env.GEMINI_API_KEY || process.env.GOOGLE_GEMINI_API_KEY;
  if (!supabaseUrl || !supabaseKey || !geminiKey) {
    const missing = [!supabaseUrl && 'SUPABASE_URL', !supabaseKey && 'SUPABASE_PUBLISHABLE_KEY', !geminiKey && 'GEMINI_API_KEY'].filter(Boolean);
    return send(res, 503, { code: 'ENVIRONMENT_VARIABLE_MISSING', error: `Vercel is missing ${missing.join(', ')}. Add it to this project’s Production environment and redeploy.` });
  }

  const auth = req.headers.authorization || '';
  if (!auth.startsWith('Bearer ')) return send(res, 401, { code: 'SIGN_IN_REQUIRED', error: 'Sign in to use the learning assistant.' });
  try {
    const userUrl = supabaseUrl.replace(/\/$/, '') + '/auth/v1/user';
    const userResponse = await fetch(userUrl, { headers: { apikey: supabaseKey, Authorization: auth } });
    if (!userResponse.ok) return send(res, 401, { code: 'SESSION_INVALID', error: 'Your session has expired. Please sign in again.' });

    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const question = typeof body.question === 'string' ? body.question.trim().slice(0, 3000) : '';
    const mode = body.mode === 'practice' ? 'practice' : 'explain';
    if (!question) return send(res, 400, { code: 'QUESTION_REQUIRED', error: 'Add a question to continue.' });

    const system = mode === 'practice'
      ? 'Create one short, practical developer learning exercise from the requested technology and focus. Return ONLY valid JSON with keys question (string), options (array of exactly 3 short strings), answer (integer 0, 1, or 2), explanation (string), and hint (string). Use fictional examples and do not invent facts about the user’s environment.'
      : 'You are Onward, a practical learning companion for people across roles and teams. Teach through relevant, hands-on examples. Start with a concise explanation, then concepts to check, a step-by-step investigation, and one question for the learner. For debugging, give plausible causes as hypotheses, never claim an unverified diagnosis. Prefer safe, fictional examples. Do not claim access to the user’s actual systems or code.';
    const model = process.env.GEMINI_MODEL || 'gemini-3.8-flash';
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 25000);
    let response;
    try {
      response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(geminiKey)}`, {
        method: 'POST',
        signal: controller.signal,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ system_instruction: { parts: [{ text: system }] }, contents: [{ role: 'user', parts: [{ text: question }] }], generationConfig: { temperature: 0.45, maxOutputTokens: 1400 } })
      });
    } finally {
      clearTimeout(timeout);
    }
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      const failure = geminiError(response, result);
      return send(res, failure.status, failure);
    }
    const text = result.candidates?.[0]?.content?.parts?.map(part => part.text || '').join('').trim();
    if (!text) return send(res, 502, { code: 'GEMINI_EMPTY_RESPONSE', error: 'Gemini returned an empty response. Try rephrasing the question.' });
    return send(res, 200, { text });
  } catch (error) {
    if (error.name === 'AbortError') return send(res, 504, { code: 'GEMINI_TIMEOUT', error: 'Gemini took too long to respond. Please try again.' });
    console.error('Onward AI request failed', { name: error.name, message: String(error.message || '').slice(0, 250) });
    return send(res, 502, { code: 'AI_UPSTREAM_UNAVAILABLE', error: 'Could not reach Supabase or Gemini. Check the Vercel function logs for this request.' });
  }
};
