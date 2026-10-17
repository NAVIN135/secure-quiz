# Operator setup

The app owner does not need to write application code. An authorized operator/agent can perform these configuration steps after the owner signs in.

## Supabase

Create an organization/project on **Free**. Do not enable paid upgrades. Choose a nearby region and let the owner set/store the database password. Apply the SQL migration files in filename order in the Supabase SQL editor. The initial migration creates application tables, policies and RPCs; do not rerun it over an existing SecureQuiz installation. The follow-up migration restricts a platform-generated automatic-RLS helper when present.

Enable email/password auth. Keep email confirmation on for real students. Configure a working site URL for confirmation links and test delivery before the pilot. Supabase's built-in email sender is limited; for a tiny controlled pilot, the operator can create confirmed student accounts in Auth instead. Do not disable confirmation for public enrollment merely to avoid configuring email. No SMTP provider is provisioned by this repository.

Create or invite a teacher in Auth, copy the exact user UUID, and approve it in SQL:

```sql
insert into public.teachers(id) values ('TEACHER_AUTH_USER_UUID') on conflict do nothing;
```

Only an authorized database operator can approve teachers. Do not rely on user-editable auth metadata for teacher roles. To revoke future quiz creation/publication: delete their teachers row. Existing quiz ownership still gives that account read access to its quizzes/results; full access revocation also requires disabling the auth account.

Copy the project HTTPS URL and publishable/legacy anon key into the local dashboard environment and Android build inputs. These keys are distributed with the client by design; RLS/RPC authorization protects data. Never distribute a service-role key, database password or personal access token. Verify the migration exists before distributing client keys.

## Dashboard

`npm ci`, then `npm run dev` from the repository root. For a stable local pilot use `npm run build`, then `npm run start -w apps/teacher -- --hostname 127.0.0.1`. The teacher can use the dashboard on that computer while student phones connect directly to Supabase over the internet. The dashboard need not be reachable from the phones. Public hosting is not required for this setup.

If remote teacher access is needed later, choose free hosting explicitly, configure HTTPS and the same public environment values, and rebuild. No hosting account or custom domain has been provisioned here.

## Android

Run the configured APK workflow in GitHub Actions, or build locally with Flutter/JDK/Android SDK. Download the artifact ZIP, extract the APK, and sideload onto the pilot phone. Android may require the owner to allow installation from the chosen file source. Use the same Supabase project as the dashboard. An unconfigured smoke APK intentionally opens a setup message.

## Data and review

Results use stable auth user UUIDs, shortened on screen; full UUIDs appear on hover. Maintain a controlled class roster mapping UUIDs to student names. No student names, browsing history, installed-app inventory, microphone or camera data is collected by SecureQuiz. Stored data includes auth email, quiz answers, timestamps, scores, and app-background reports. Provider Forms pages handle their own data separately.

Published quizzes are immutable and have one attempt per student account. Create another quiz to offer a retake. There is no class membership or join-code rate limiting in this MVP; treat codes as classroom access secrets, revoke access operationally by closing/retiring the pilot project if necessary. Do not share codes publicly.

The deadline is always enforced when a student calls an attempt RPC. A disconnected/abandoned attempt may still appear `active` in the dashboard until that student reconnects; its deadline still prevents late answers. No scheduled worker or real-time polling was provisioned. Refresh results manually. Export/backup and data-retention deletion require an authorized operator; free-tier automatic backups are not assumed.
