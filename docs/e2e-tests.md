# E2E Tests

Native e2e tests are opt-in. Default XCTest runs skip these network scenarios.

## Covered opt-in scenarios

- `CloudTranscriptionServiceE2ETests`:
  - native file translation through `/api/v1/transcriptions`
  - owned OTP sign-in through `/api/v1/auth/send-otp` and `/api/v1/auth/verify-otp` with Mailpit
  - rotating-token refresh (`AuthService.refreshTokens`) after OTP sign-in
  - HTTP access-token validation for `/api/v1/translations` (invalid token → 401, valid token → success)
  - realtime WebSocket access-token validation (`/api/v1/realtime`, valid token → proxy_ready, bad token → failure)

## Required environment

```bash
export DIDUNY_E2E_NATIVE=1
export DIDUNY_E2E_PROXY_BASE_URL=http://127.0.0.1:3910
export DIDUNY_E2E_ACCESS_TOKEN="<local Diduny access token>"
export DIDUNY_E2E_AUDIO_PATH="$HOME/Library/Application Support/ua.com.rmarinsky.diduny.test/Recordings/6136BD79-8B0A-4DE3-932F-0D5CF616243B.wav"
export DIDUNY_E2E_EXPECTED_TEXT="Translation test: will it translate?"
export DIDUNY_E2E_SOURCE_LANGUAGE=uk
export DIDUNY_E2E_TARGET_LANGUAGE=en
export DIDUNY_E2E_MAILPIT_URL=http://127.0.0.1:55324
```

Optional override for OTP seed account:

```bash
export DIDUNY_E2E_OTP_EMAIL="diduny-e2e-auto@example.com"
```

## Build and test commands

Build test bundle:

```bash
xcodebuild \
  -project Diduny.xcodeproj \
  -scheme "Diduny DEV" \
  -configuration Debug \
  -derivedDataPath /tmp/diduny-e2e-derived \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

Run only this class:

```bash
xcodebuild \
  -project Diduny.xcodeproj \
  -scheme "Diduny DEV" \
  -configuration Debug \
  -derivedDataPath /tmp/diduny-e2e-derived \
  -destination "platform=macOS" \
  -only-testing:DidunyTests/CloudTranscriptionServiceE2ETests \
  CODE_SIGNING_ALLOWED=NO \
  test
```
