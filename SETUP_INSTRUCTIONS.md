# SUNO — Setup Instructions

## 1. Install Flutter packages

```bash
cd SUNO-AI
flutter pub get
```

New packages added in the latest build:

- `flutter_local_notifications` — shows system notifications for foreground FCM messages on Android.
- `url_launcher` — opens incident locations in Google Maps.

---

## 2. Download the YAMNet TFLite model (required for Phase 2)

YAMNet converts raw 16 kHz audio into 1024-dimensional embeddings that the
SUNO classifier head consumes. Without it, only the demo/mock path works.

```bash
cd SUNO-AI
curl -L -o assets/ml/yamnet.tflite \
  "https://tfhub.dev/google/lite-model/yamnet/tflite/1?lite-format=tflite"

# Verify size (~16 MB expected for the float32 TF Hub Lite model):
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

On Android 10+ the app requests location in two stages: foreground location first, then `ACCESS_BACKGROUND_LOCATION` after the user has already granted foreground access. Do not deny the second prompt if you want location attached to alerts when the app is in the background.

---

## 4. Firebase push notifications

### 4a. Create Firebase project
1. Go to https://console.firebase.google.com
2. New project → name it "SUNO-AI"
3. Add Android app with package name: `com.example.suno_ai`
4. Download `google-services.json`
5. Place it at `android/app/google-services.json`

### 4b. Apply the google-services Gradle plugin

In `android/build.gradle.kts`, add to the plugins block:
```kotlin
id("com.google.gms.google-services") version "4.4.2" apply false
```

In `android/app/build.gradle.kts`, add at the very end:
```kotlin
apply(plugin = "com.google.gms.google-services")
```

### 4c. Enable FCM
Firebase console → Your project → Cloud Messaging → Enable

---

## 5. OpenStreetMap / flutter_map

No API key needed. The map tiles are served by OpenStreetMap's free tile
server. Requires the `INTERNET` permission already added to AndroidManifest.

Tapping the map preview card or the **OPEN** button launches the location in
Google Maps via `url_launcher`.

---

## 6. Supabase Edge Function for alert delivery

The app cannot send FCM directly to another phone. It sends alert metadata to
`supabase/functions/send-alert`, and that function calls Firebase Cloud Messaging
with server credentials.

```bash
npm install -g supabase
supabase login
supabase init
supabase functions deploy send-alert
```

Set these Supabase secrets from your Firebase service account JSON:

```bash
supabase secrets set FIREBASE_PROJECT_ID="suno-ai-c5463"
supabase secrets set FIREBASE_CLIENT_EMAIL="firebase-adminsdk-xxxxx@suno-ai-c5463.iam.gserviceaccount.com"
supabase secrets set FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

The production Supabase function URL is already baked into
`lib/core/config/app_config.dart`, so a plain `flutter run` or
`flutter build apk --release` will use it automatically. You only need to
override it at compile time if you are deploying against a different Supabase
project:

```bash
flutter run --dart-define=SUNO_ALERT_RELAY_URL="https://YOUR_PROJECT_REF.functions.supabase.co/send-alert"
```

For a release APK:

```bash
flutter build apk --release \
  --dart-define=SUNO_ALERT_RELAY_URL="https://YOUR_PROJECT_REF.functions.supabase.co/send-alert"
```

> **Important:** If you fork this project and change the Supabase project,
> update `AppConfig.alertRelayUrl` or always build with `--dart-define`.
> Building without either will fall back to the original production URL and
> push alerts will silently fail for your Firebase project.

Trusted contacts only receive push alerts if their saved contact record includes
that phone's FCM token. The contact setup screen has an optional FCM token
field for hackathon testing.

Two-phone test flow:
1. Install/run SUNO on the contact phone.
2. Read the console line: `[SUNO FCM] This device token: ...`.
3. Copy that token into the sender phone's Trusted Contact → FCM token field.
4. On the sender phone, tap the contact's **⋮ → Test reachability**. A silent
   FCM ping is sent; if delivery succeeds, the contact status changes to
   **Verified reachable**.
5. Trigger a critical alert; the sender posts event/risk/location metadata to
   Supabase, and Supabase sends FCM to the contact phone.
6. On the contact phone, tap a response button; the response is relayed back
   to the sender and shown on the sender's Emergency Alert screen.

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

The sender's phone receives a data-only FCM, and the app updates the Emergency
Alert screen with the contact's response.

### Contact reachability testing

The Edge Function accepts `{ "test": true, "contactTokens": ["..."] }` to
send a silent data-only ping. This is used from **Trusted contacts → Test
reachability** to verify a contact's FCM token before a real emergency.

---

## 7. Build and run

Your friend should run these exact commands from the project root after
cloning the repo and placing `google-services.json`:

```bash
cd SUNO-AI
flutter pub get
flutter build apk --release
```

The release APK will be at:

```
build/app/outputs/flutter-apk/app-release.apk
```

To install and run on a connected device or emulator instead of building an APK:

```bash
flutter run
```

The production Supabase Edge Function URL is already baked into
`lib/core/config/app_config.dart`, so no `--dart-define` is required for the
official relay. Only use the override if you are deploying against a different
Supabase project:

```bash
flutter build apk --release \
  --dart-define=SUNO_ALERT_RELAY_URL="https://YOUR_PROJECT_REF.functions.supabase.co/send-alert"
```

---

## 8. Push to GitHub

```bash
cd SUNO-AI
git add -A
git status          # verify what's staged
git commit -m "feat: describe your change"
git push origin feature/day2-integration
```

---

## 9. App launcher icon (optional, removes blank icon)

Generate from your SUNO logo at:
https://romannurik.github.io/AndroidAssetStudio/icons-launcher.html

Place the output mipmap-* folders in `android/app/src/main/res/`.
