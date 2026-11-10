# Host dispatch regression

Run `python3 Scripts/test-action-dispatch.py` from the repository root on macOS
with the Xcode Swift compiler. No dependency download or device is needed.

`ActionHandler` is tied to UIKit, XCTest and private device APIs. The harness
compiles its **complete production `dispatch` method**, blocker detector,
read-response advice and coordinate validator into a host fixture. It uses the
production `ActionCommand`, `ContinuousDragPath`, `AuthManager`, `SecureEnvelope`
and RPC types directly. It does not copy or rewrite their decision logic.

`Host.swift` replaces screen capture, settling, device queries and the
`dispatchInner` execution boundary with deterministic doubles. The execution
spy proves that a gesture reaches the common execution boundary once, with its
parsed command, after an actual CAPTCHA observation. Other checks cover
dispatch preflight, path validation, rate-limit advice, pairing approval and
cooldown, sealed requests, MAC failure, replay and timestamp rejection.
Token persistence is in memory; the test never opens a server, reads real
credentials or injects touches.

Member extraction requires a unique declaration and the existing member
indentation. Missing or ambiguous declarations fail immediately; changed
dependencies must compile against the fixture. Keep the fixture updated when
the dispatcher changes. Device APIs, real reference resolution, rendering,
settling and actual touch delivery still require separate device validation.

For a negative control, use the harness against a clean checkout of the
pre-change source:

```bash
python3 Scripts/test-action-dispatch.py --source-root /path/to/baseline
```

The original CAPTCHA gate must fail at `swipe refused after CAPTCHA observation`.
The optional legacy challenge field is included only when present in that
source, so its real read handler primes the original refusal state.
