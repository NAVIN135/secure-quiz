# Validation record

Validated locally on October 17, 2026:

- Next.js production build and TypeScript compilation passed.
- Embedded PostgreSQL (PGlite) executed the actual migration and passed end-to-end RPC/RLS assertions for teacher approval, publication, hidden keys, direct-write denial, student ownership, scoring, immutable final attempts, one-attempt resume, violation deduplication/threshold, Forms URL validation, null Forms score and server expiry.
- Flutter 3.47.7 analyzer passed with no issues; widget smoke test passed for the unconfigured-app explanation. This does not exercise a hosted quiz or Android lifecycle callbacks.

PGlite uses a test auth schema and JWT subject setting; it is not a test of hosted Supabase Auth, email delivery, PostgREST configuration or free-tier capacity. No service credentials are required for these tests.

Hosted Supabase setup was subsequently completed on the owner's SecureQuiz project. All five application tables have RLS enabled. A transaction using two temporary Auth identities verified teacher creation/publication, student answer-key isolation, denied direct score writes, denied anonymous RPC execution and correct submission scoring. All test fixtures were rolled back.

The security advisor flagged Supabase's generated `rls_auto_enable()` helper as publicly executable. Its client execution grants were revoked and the fix was recorded in a second migration. The remaining six advisor warnings identify the intentionally authenticated mutation RPCs. They validate teacher approval or attempt ownership, use a fixed empty search path, and own deadline/scoring writes that clients cannot perform directly. They are reviewed API entry points, not unrestricted helpers. See [Supabase's advisor guidance](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

The local dashboard is configured with the project's public URL and publishable key in an ignored environment file. The owner's selected teacher account was created, approved, and has successfully signed in according to hosted Auth records. Public HTTP checks returned 401 for anonymous question reads and attempt-start RPC calls, and 200 for Auth settings. The configured dashboard production build passed.

Provider Forms sign-in/submission and physical Android behavior remain pending device testing. GitHub publishing/CI is still blocked by integration write access; no APK build has yet been verified.
