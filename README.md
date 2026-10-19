# DevLearn

DevLearn is a developer learning companion for individuals and teams across companies, departments, and email domains. People can keep notes private, create or join a workspace, invite colleagues across domains, and deliberately share learning notes with that workspace. It does not rank employees or expose private notes to administrators.

## Services

- Supabase Auth and Postgres with row-level security for accounts, personal notes, organizations, departments, and invitations.
- Vercel serverless functions for the configuration endpoint and authenticated AI requests.
- Google Gemini API for practical explanations and exercises.
- Static HTML, CSS, and JavaScript frontend.

## Supabase setup

1. Create a Supabase project.
2. In Project Settings → API, copy the Project URL and the publishable key (or legacy anon key).
3. Open SQL Editor and run the complete [`supabase/schema.sql`](supabase/schema.sql). Wait for Supabase to report success before reloading DevLearn. The migration is safe to rerun and refreshes the PostgREST schema cache.
4. In Authentication → URL Configuration, set the Site URL to your deployed Vercel URL and add local or preview URLs to the allowed redirect URLs when needed.
5. Configure email delivery and confirmation behavior before relying on sign-up emails in production.

## Vercel environment

Add these variables to the Vercel project's Production environment (and Preview if used), then redeploy:

- `SUPABASE_URL` — Supabase project URL.
- `SUPABASE_PUBLISHABLE_KEY` — the public publishable key. The legacy `SUPABASE_ANON_KEY` is also accepted.
- `GEMINI_API_KEY` — an active key created for the Gemini API in Google AI Studio. Keep it server-side; never add it to frontend code or Git.
- `GEMINI_MODEL` — optional model override. Defaults to `gemini-3.8-flash`.

The `/api/learn` response distinguishes rejected keys, model errors, quota limits, missing environment variables, and temporary upstream failures. It does not log prompts or API keys. If a provider request still fails, inspect Vercel → Functions → Logs and follow the returned error guidance. Google's Gemini API documentation lists [provider error codes and remedies](https://ai.google.dev/gemini-api/docs/generate-content/api-errors).

## Workspaces

- Each account starts with a private personal workspace.
- Any signed-in user can create a workspace with a company, domain, project, or department name. No ACME-specific name or email domain is hard-coded.
- Owners and admins can add departments, create 14-day invitation codes, and address an invite to a specific email. The email button opens a prefilled draft in the admin's mail app.
- Entering an invite code submits a join request; the person is added only after an owner or admin approves it. An administrator can optionally restrict a code to one email domain.
- Members can see workspace notes only when the author explicitly marks them shared. Personal notes stay visible to their author. Workspace row-level policies isolate different organizations.
- A note that cannot reach Supabase is kept in that account's browser storage and shown as pending. It retries on the next sign-in/reload; pending browser-only notes do not appear on another device until synced.
- Share sanitized, verified troubleshooting notes only. Do not put employer-confidential source code, credentials, customer data, or internal personal information into an AI prompt.

## Deploy

Import this repository into Vercel with the default static frontend and serverless `api/` functions. Set the environment variables, deploy, update Supabase Auth's allowed URLs to include the final Vercel URL, and run the SQL setup. Verify sign-up, note saving, one AI explanation, and workspace creation/join using separate accounts.

Vercel Hobby is intended for personal, non-commercial use. Use a plan that permits the intended company or team deployment before rolling this out for business use. Review current provider plans and terms before using work content.

## Current scope

This version provides private learning notes, opt-in workspace sharing, departments, email-addressed invite drafts, and admin-approved invitation-code onboarding. It does not yet include SSO/SCIM, audit exports, retention controls, team analytics, or a reviewed-publication workflow. Workspace learning data is not an employee performance measure.

## Troubleshooting database setup

- If workspace creation says `Could not find the function public.create_workspace(p_name) in the schema cache`, the migration has not completed in the connected Supabase project or its API cache has not refreshed. Run the whole `supabase/schema.sql` again in that project's SQL Editor, wait for a success result, then wait briefly and reload DevLearn.
- If notes report missing tables/columns or row-level security errors, run that same complete migration. The app will show a database status banner and keep new unsynced notes in browser storage instead of claiming they were saved to Supabase.
