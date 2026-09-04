# SUNO — Setup Instructions

## 1. Install Flutter packages

```bash
cd SUNO-AI
flutter pub get
```

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

## 3. Firebase push notifications

### 3a. Create Firebase project
1. Go to https://console.firebase.google.com
2. New project → name it "SUNO-AI"
3. Add Android app with package name: `com.example.suno_ai`
4. Download `google-services.json`
5. Place it at `android/app/google-services.json`

### 3b. Apply the google-services Gradle plugin

In `android/build.gradle.kts`, add to the plugins block:
```kotlin
id("com.google.gms.google-services") version "4.4.2" apply false
```

In `android/app/build.gradle.kts`, add at the very end:
```kotlin
apply(plugin = "com.google.gms.google-services")
```

### 3c. Enable FCM
Firebase console → Your project → Cloud Messaging → Enable

---

## 4. OpenStreetMap / flutter_map

No API key needed. The map tiles are served by OpenStreetMap's free tile
server. Requires the `INTERNET` permission already added to AndroidManifest.

---

## 5. Supabase Edge Function for alert delivery

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

After deploy, copy the function URL and run the app with:

```bash
flutter run --dart-define=SUNO_ALERT_RELAY_URL="https://YOUR_PROJECT_REF.functions.supabase.co/send-alert"
```

For a release APK:

```bash
flutter build apk --release \
  --dart-define=SUNO_ALERT_RELAY_URL="https://YOUR_PROJECT_REF.functions.supabase.co/send-alert"
```

Trusted contacts only receive push alerts if their saved contact record includes
that phone's FCM token. The contact setup screen now has an optional FCM token
field for hackathon testing.

Two-phone test flow:
1. Install/run SUNO on the contact phone.
2. Read the console line: `[SUNO FCM] This device token: ...`.
3. Copy that token into the sender phone's Trusted Contact → FCM token field.
4. Run the sender phone with `SUNO_ALERT_RELAY_URL` configured.
5. Trigger a critical alert; the sender posts event/risk/location metadata to
   Supabase, and Supabase sends FCM to the contact phone.

No raw audio is sent — only incident metadata and location coordinates.

---

## 6. Build and run

```bash
# Connect Android device or start emulator first
flutter run

# Release APK
flutter build apk --release
```

---

## 7. Push to GitHub

```bash
cd SUNO-AI
git add -A
git status          # verify what's staged
git commit -m "feat: describe your change"
git push origin feature/day2-integration
```

---

## 8. App launcher icon (optional, removes blank icon)

Generate from your SUNO logo at:
https://romannurik.github.io/AndroidAssetStudio/icons-launcher.html

Place the output mipmap-* folders in `android/app/src/main/res/`.
