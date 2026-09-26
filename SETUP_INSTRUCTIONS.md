# SUNO — Setup Instructions

## 1. Install Flutter packages

```bash
cd SUNO-AI
flutter pub get
```

Use Flutter stable with Dart 3.13.1 or newer within Dart 3.x, Java 17, and the Android SDK required by Flutter. Local verification uses Flutter 3.47.5 / Dart 3.13.4; CI follows Flutter stable. Run `flutter doctor -v` before building. Use `flutter pub get --enforce-lockfile` for repeatable dependency resolution.

`flutter_local_notifications` supplies Android notification channels and foreground notifications; `url_launcher` opens incident coordinates externally. Demo uses neither microphone capture nor model inference.

---

## 2. Download the YAMNet TFLite model (required for Phase 2)

YAMNet converts raw 16 kHz audio into 1024-dimensional embeddings that the
SUNO classifier head consumes. Without it, only the demo/mock path works.

```bash
cd SUNO-AI
curl -L -o assets/ml/yamnet.tflite \
  "https://tfhub.dev/google/lite-model/yamnet/tflite/1?lite-format=tflite"

# Verify size (~16 MB expected for the float32 TF Hub lite model):
ls -lh assets/ml/yamnet.tflite
file assets/ml/yamnet.tflite
```

If the file is around 411 bytes or `file` says XML/text, the download failed and saved an AccessDenied response instead of the model.

---

## 3. Android permissions

`android/app/src/main/AndroidManifest.xml` already contains the required permissions. Verify these are present before building:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```

Demo requests foreground location, never microphone permission. Live requests microphone permission while the app is visible before starting capture. Location refreshes during Live do not repeatedly request permission. Android also requires `FOREGROUND_SERVICE_LOCATION`; the service declares `microphone|location|shortService`. Android 14+ uses a bounded short service for Demo countdown/dispatch without microphone access.

Enable GPS and notification permission on both test phones. Denied, disabled, or timed-out location must show unavailable instead of invented coordinates; alerts can still be attempted. Notification sound, vibration, full-screen display and background behavior depend on Android settings and device restrictions. The retained engine supports ordinary screen navigation/task removal while its service runs, but cannot guarantee survival after force-stop, process death, reboot or OEM termination.

---

## 4. Firebase push notifications

### 4a. Create Firebase project
1. Go to https://console.firebase.google.com
2. New project → name it "SUNO-AI"
3. Add Android app with package name: `com.example.suno_ai`
4. Download `google-services.json`
5. Place it at `android/app/google-services.json`

### 4b. Verify the google-services Gradle plugin

The plugin is already declared in `android/settings.gradle.kts` and applied in the `plugins` block of `android/app/build.gradle.kts`. Do not add duplicate declarations; supply `android/app/google-services.json` for your Firebase project.

### 4c. Enable FCM
Firebase console → Your project → Cloud Messaging → Enable

---

## 5. Map tiles / flutter_map

The tile source is selected at build time:

- `--dart-define=MAPTILER_KEY="<key>"` → MapTiler Streets v2 raster tiles, with
  `MapTiler` added to the on-map attribution as their terms require.
- No key → OpenStreetMap's public tile server. This is the development fallback
  only: OSM's tile usage policy targets light, occasional use and rate-limits
  app-shaped traffic, so many tiles loading at once from several phones can fail.
  The in-app "Map tiles unavailable" banner and Retry stay working either way.

Create a free MapTiler account, copy its default API key, and add it as the
`MAPTILER_KEY` repository secret so CI passes it through. A key compiled into an
APK can be extracted from the binary, so use a dedicated key and rotate it after
demo day.

Requires the `INTERNET` permission already added to AndroidManifest.

The map supports pan and zoom; the explicit **OPEN** button launches the saved coordinates externally via `url_launcher`. Tile errors offer Retry while preserving the coordinates. Location is captured at alert time, not continuously tracked on the recipient's phone. OpenStreetMap attribution is included.

---

## 6. Supabase Edge Function for alert delivery

The app cannot send FCM directly to another phone. It sends alert metadata to
`supabase/functions/send-alert`, and that function calls Firebase Cloud Messaging
with server credentials.

```bash
npx supabase login
npx supabase init
npx supabase functions deploy send-alert --no-verify-jwt
```

This prototype authenticates requests with `X-SUNO-Relay-Key`, not a Supabase user JWT. The deployment flag disables the gateway's JWT requirement; the function still rejects requests without the matching relay key. Configure that secret before testing.

Set these Supabase secrets from your Firebase service account JSON:

```bash
npx supabase secrets set FIREBASE_PROJECT_ID="suno-ai-c5463"
npx supabase secrets set FIREBASE_CLIENT_EMAIL="firebase-adminsdk-xxxxx@suno-ai-c5463.iam.gserviceaccount.com"
npx supabase secrets set FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
npx supabase secrets set SUNO_RELAY_AUTH_KEY="use-a-random-demo-only-value"
```

The default relay URL is in `lib/core/config/app_config.dart`. Override `SUNO_ALERT_RELAY_URL` when using a different project. The reviewed relay source must be deployed separately; local edits do not update the hosted endpoint.

`SUNO_RELAY_AUTH_KEY` is REQUIRED on the relay and in the app build. Missing server configuration fails closed; missing client configuration produces a visible failure. Supply the matching key using `--dart-define=SUNO_RELAY_AUTH_KEY="..."` and never commit it. An APK-embedded key can be extracted, so this is prototype abuse resistance, not production-grade user authentication. Keep Firebase private credentials server-side.

### Building with relay configuration

```bash
flutter run \
  --dart-define=SUNO_ALERT_RELAY_URL="https://YOUR_PROJECT_REF.functions.supabase.co/send-alert" \
  --dart-define=SUNO_RELAY_AUTH_KEY="YOUR_DEMO_KEY"
```

For a release APK:

```bash
flutter build apk --release \
  --dart-define=SUNO_ALERT_RELAY_URL="https://YOUR_PROJECT_REF.functions.supabase.co/send-alert" \
  --dart-define=SUNO_RELAY_AUTH_KEY="YOUR_DEMO_KEY"
```

> **Important:** If you fork this project and change the Supabase project,
> update `AppConfig.alertRelayUrl` or always build with `--dart-define`.
> Building without either will fall back to the original project URL. Alerts
> may fail; check the saved incident's delivery status and relay configuration.

Trusted contacts only receive push alerts if their saved contact record includes
that phone's FCM token. The contact setup screen has an optional FCM token
field for hackathon testing.

### Two-phone test flow

1. Install SUNO on two consenting Android test phones and allow notifications.
2. On the contact phone, open **Trusted Contacts**, refresh the device token if needed and copy it using the screen's copy control. Tokens are not logged.
3. Save that token in the sender phone's contact record. The sender also needs its own registered token for responses.
4. **Test FCM acceptance** sends a silent test. **FCM test accepted** is not proof of device receipt/display; verify a visible alert separately.
5. In **Demo Mode**, check real GPS, select **CRITICAL**, and simulate distress. Confirm the same coordinates on the saved sender incident and received alert; pan/zoom and open the map externally.
6. Respond on the contact phone and verify that only the matching incident changes on the sender. Reopen both apps and check history.
7. Repeat medium safe, medium timeout without opening the safety notification, immediate escalation, Silent SOS, no contacts, expired token, offline tiles/relay, denied permissions and repeated taps. Test notifications foreground/background/cold-start and Live screen-off/task removal/reopening/explicit stop on the actual evaluation devices.

Passing automated tests alone does not establish demo readiness. Relay deployment and the two-phone acceptance checks are separate release gates.

No raw audio is sent — only incident metadata and location coordinates.

### Two-way responses

The same Edge Function also relays contact responses back to the original
sender. The recipient app sends:

```json
{
  "response": {
    "recipientToken": "<sender's FCM token>",
    "incidentId": "<incident id>",
    "responderName": "<contact name>",
    "status": "contactChecking | resolved | alertTriggered",
    "message": "I am checking on them | They are safe | Unable to contact"
  }
}
```

Alerts and responses use notification-plus-data FCM messages. The response updates its explicit incident ID and can open that incident when tapped. FCM acceptance does not prove the sender saw the response.

### Contact token testing

The Edge Function accepts `{ "payload": {"type": "test"}, "test": true, "contactTokens": ["<valid test token>"] }` for a silent data-only test. **Trusted Contacts → Test FCM acceptance** records relay acceptance, not verified reachability. Requests require the matching relay auth key; the client batches recipients within the relay's ten-token and 16 KiB request limits.

---

## 7. Build and run

Your friend should run these exact commands from the project root after
cloning the repo and placing `google-services.json`:

```bash
cd SUNO-AI
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --release --dart-define=SUNO_RELAY_AUTH_KEY="YOUR_DEMO_KEY"
```

Use Java 17 and the TFLite Java-target alignment step already present in `.github/workflows/build-apk.yml` if your environment reports a Java/Kotlin target mismatch. Do not disable validation or change model files to work around build errors.

The release APK will be at:

```
build/app/outputs/flutter-apk/app-release.apk
```

To install and run on a connected device or emulator instead of building an APK:

```bash
flutter run --dart-define=SUNO_RELAY_AUTH_KEY="YOUR_DEMO_KEY"
```

The default URL is already configured, but the matching relay key is still required. For a different Supabase project, also pass `--dart-define=SUNO_ALERT_RELAY_URL="https://YOUR_PROJECT_REF.functions.supabase.co/send-alert"`.

---

## 8. Push to GitHub

```bash
cd SUNO-AI
git add -A
git status          # verify what's staged
git commit -m "feat: describe your change"
git push origin feat/integration
```

---

## 9. App launcher icon (optional, removes blank icon)

Generate from your SUNO logo at:
https://romannurik.github.io/AndroidAssetStudio/icons-launcher.html

Place the output mipmap-* folders in `android/app/src/main/res/`.
