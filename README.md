# DevLearn

DevLearn is a small full-stack developer learning app. It uses Supabase Auth for email/password accounts, Supabase Postgres with row-level security for private learning notes, a Vercel serverless function for AI requests, and the Gemini Developer API for explanations and practice exercises.

## Set up Supabase

1. Create a Supabase project on the free plan.
2. In **Project Settings → API**, copy the Project URL and the publishable (or legacy anon) key.
3. Open **SQL Editor** and run [`supabase/schema.sql`](supabase/schema.sql).
4. In **Authentication → URL Configuration**, set the Site URL to your deployed Vercel URL. Add your local development URL to the allowed redirect URLs if needed.
5. Email/password sign-in is enabled by default. Configure SMTP before relying on confirmation emails in production; otherwise use the project’s available auth email behavior and test the flow.

## Configure AI

Create a Gemini API key in Google AI Studio. Add these environment variables to the Vercel project:

- `SUPABASE_URL` — Supabase project URL
- `SUPABASE_PUBLISHABLE_KEY` — Supabase public publishable key (the app also accepts the older `SUPABASE_ANON_KEY`)
- `GEMINI_API_KEY` — Gemini API key (server-side only)

The Vercel function checks the Supabase access token before sending a question to Gemini. The client sends only the specific prompt submitted in the Explain or Practice screen. Do not submit passwords, access tokens, customer data, source code that your employer considers confidential, or other sensitive material. Gemini’s free tier may use submitted content to improve Google products; review the current [Gemini API terms and pricing](https://ai.google.dev/gemini-api/docs/pricing) before using it with work material.

## Deploy to Vercel

Vercel Hobby is limited to personal, non-commercial use. A company-internal or business deployment needs a Vercel plan that permits commercial use; check current plan terms before publishing for ACME.

1. Push this folder to a Git repository you control.
2. Import the repository in Vercel and keep the project as a static site with the included serverless `api/learn.js` function.
3. Add the three server environment variables above. Do not prefix the Gemini key with `VITE_` or expose it in `config.js`.
4. The public Supabase URL and publishable key are read by `/api/config`; they are intentionally browser-visible. The Gemini key is only used in `/api/learn` and must remain server-side.
5. Deploy, then add the final Vercel URL to Supabase Auth’s allowed URLs and set it as the Site URL.
6. Test account creation, sign-in, note creation/deletion, explanation, and practice generation in the deployed site.

## Limitations

- Free-tier quotas and inactivity/pause rules can change. Review the providers’ current plan details.
- AI-generated explanations are educational suggestions, not confirmed diagnoses of a company environment.
- The database persists notes per user. Some progress and review interactions are still session-only and are not yet stored as durable learning history.
- No team library or organization-wide account provisioning is included in this first full-stack version.
