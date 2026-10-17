# SecureQuiz

Flutter Android student app, Next.js teacher dashboard, and Supabase Auth/Postgres backend. Pilot target: **October 21, 2026 (India time)**.

## Included

- Email/password student registration and sign-in; approved teacher sign-in.
- Teacher quiz builder with multiple-choice questions, duration, app-switch limit, draft/publish and results.
- Native quizzes: code-based joining, one attempt per account, saved answers, resume, countdown, server scoring and deadline enforcement.
- Android lifecycle reports: one report per pause/resume cycle, persisted retry queue, server deduplication, and attempt finalization at the configured report limit.
- Google and Microsoft Forms links in an HTTPS WebView, with explicit session/submission limitations.
- RLS for every application table. Answer keys are teacher-only; students use authenticated RPCs. Teacher approval cannot be self-assigned.

## Run

Prerequisites: Node 22+, Flutter 3.47.7, Android SDK/JDK 17 for APK builds, and a Supabase Free project. No paid AI API or service is used.

1. Apply the SQL files in `supabase/migrations/` in filename order to a **new** Supabase project. The initial migration is one-time, not a reset script.
2. In Supabase Auth create the teacher account, then approve its exact user ID by inserting it into `public.teachers`. Students must never receive that permission. The operator guide has the SQL.
3. Copy `apps/teacher/.env.example` to `apps/teacher/.env.local` and set the project URL and publishable or legacy anon key. Never put a service-role key in either client.
4. At repository root: `npm ci`, then `npm run dev`. Open `http://127.0.0.1:3000`.
5. In `apps/student`: `flutter pub get`, then `flutter run --dart-define=SUPABASE_URL=https://PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=PUBLIC_KEY`.
6. Teacher signs in, creates and publishes a quiz; student signs in and enters the generated code.

The unconfigured dashboard and app show setup instructions. They are not connected demos and do not fabricate students/results.

## Build and verify

```text
npm test
npm run build
cd apps/student
flutter analyze
flutter test
flutter build apk --debug --dart-define=SUPABASE_URL=https://PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=PUBLIC_KEY
```

GitHub Actions verifies the database/dashboard and builds an unconfigured Android smoke APK on push. Run **Build configured pilot APK** manually with the public connection values to produce a usable pilot APK. Debug APKs are for sideloaded trials; no Play Store account is required. They use debug signing, not a production release identity.

## Important operating limits

This is an MVP for supervised trials, not guaranteed lockdown or a high-stakes proctoring system. Server timing and scoring resist client edits, but lifecycle reports come from an untrusted device. Clearing app storage, force-stopping, rooting, alternate accounts/devices, or a modified app can bypass monitoring. Calls and system screens may produce false positives. Teachers should review reports with context.

Forms submission and grading remain entirely with Google/Microsoft. SecureQuiz cannot inspect their cross-origin contents, verify answers/submission, enforce provider deadlines, or stop a form being opened elsewhere. Ending a SecureQuiz Forms session does not submit the form. Tenant sign-in policies may block embedded browsers; browser sign-in may count as an app switch. See [limitations](docs/LIMITATIONS.md).

Zero-cost operation uses an existing computer for the dashboard, a Supabase Free project within quota, and sideloaded APKs. It does not include paid hosting, domain, app-store fees, a production email service, or uptime guarantees. [Supabase Free](https://supabase.com/pricing) currently includes a 500 MB database and pauses after a week of inactivity. [GitHub Actions standard runners](https://docs.github.com/en/billing/concepts/product-billing/github-actions) are free for public repositories; private repositories have quotas. Recheck providers before changing plans.

See [operator setup](docs/OPERATIONS.md), [pilot checks](docs/PILOT.md), and [validation record](docs/VALIDATION.md).
