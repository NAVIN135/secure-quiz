# October 21 pilot gates

Target date: October 21, 2026, Asia/Kolkata. Do not treat source completion as a live launch.

1. Sign in to Supabase, create a Free project, apply migration and approve the teacher.
2. Configure the dashboard and APK with the project's public connection values.
3. On a physical Android phone create/sign in a student account and take a two-question native quiz. Check the teacher's result against the saved answers.
4. Kill/reopen the app mid-attempt; confirm the same deadline and saved answers return.
5. Use a one-minute quiz. Disconnect, wait past deadline, reconnect and confirm late answers are rejected and status expires.
6. Switch to another app and back. Confirm exactly one report, retry without double counting, and verify the configured threshold flags/finalizes the attempt. Test a call/screen lock and agree the teacher review policy for false positives.
7. Test two students and a second teacher; confirm they cannot see another user's records/keys. The automated database suite covers role boundaries; repeat through hosted Auth before launch.
8. Open each actual Google/Microsoft Form in the app. Confirm the tenant's login works, submit in the provider, and match the response manually. Confirm SecureQuiz shows no Forms score or verified submission claim.
9. Confirm auth email delivery or pre-provision controlled accounts. Keep a UUID-to-student roster.
10. Download and install the configured pilot APK, verify free-tier usage, and agree a backup/retention process.

No deployment or device acceptance check is complete until its real environment has been tested. No recurring job has been scheduled to perform these checks automatically.
