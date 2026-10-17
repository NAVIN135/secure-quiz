# Security and Forms limitations

## Native quiz

The database locks attempt rows during mutations, rejects cross-user writes, owns the start/deadline timestamps, validates answer choices, and scores only saved answers. Students never receive the correct-answer field. Submit, expiry and the app-switch limit finalize once; repeated calls cannot change a final score. Previously acknowledged answers survive restarts. Failed answer saves are not accepted locally: retry when connected. There is no fully offline quiz-taking mode.

Device clock changes can affect the displayed countdown; they cannot extend the database deadline. Final status and score for disconnected attempts are materialized on the next RPC, rather than by a scheduled server job. Network latency counts against the allotted time.

Student identities depend on accounts, not verified enrollment. A shared join code admits any signed-in account that knows it. One-attempt enforcement is per account, so multiple accounts can bypass it. Institutions should provision accounts for a controlled pilot.

## App-switch monitoring

Flutter's Android `paused` lifecycle event queues a background report. Resuming flushes queued reports; UUIDs make retries idempotent. The configured limit ends the attempt with status `flagged` and scores saved native answers. Reports are evidence for review, not proof of cheating. Android calls, permissions, screen locking and interruptions can produce reports. Split-screen, overlays, notification panels, screenshot tools and force kills are not comprehensively detected or blocked. No kiosk/device-owner provisioning, screenshot prevention, accessibility-service monitoring or device-administration permission is used.

Process termination can happen without lifecycle callbacks; the OS may suspend networking/persistence. Reports lost before durable storage cannot be recovered. Local queues can be tampered with or cleared. A malicious app can omit reports. See [Flutter lifecycle documentation](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html).

## Google/Microsoft Forms

Link modes allow only HTTPS Google Forms or Microsoft Forms share hosts at quiz creation. Redirects and provider content navigate within an HTTPS-only WebView; non-HTTPS navigation is blocked. This does not make a provider-controlled or linked page trusted. No HTML injection, DOM scraping, hidden answer capture, provider API token or credential interception is used.

The form provider controls sign-in, cookies, accessibility, embedded-browser support, response storage, grading and submission. Test the exact tenant/form on the target phone; some institutional configurations reject WebView sign-in. The MVP does not implement an external-browser fallback that would preserve monitoring claims. Choose an accessible form or use native quizzes if authentication fails.

The student must press the provider's submit button **inside the form** before pressing SecureQuiz's end button. SecureQuiz records only `ended`, `expired` or `flagged` with no score; it never labels a Forms session as a verified submission. SecureQuiz's timer cannot stop a form loaded in another browser or revoke provider access. Match results manually in the provider using an explicit class identifier question, subject to the institution's privacy policy.

For assessed scoring, enforced saved-answer deadlines and reliable linkage to the SecureQuiz account, use native mode. No claim is made that Forms link mode provides the same controls.
