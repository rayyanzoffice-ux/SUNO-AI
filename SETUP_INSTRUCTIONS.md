# SUNO-AI — Setup Instructions

## 1. Install Flutter packages

```bash
cd ~/SUNO-AI
flutter pub get
```

---

## 2. Download the YAMNet TFLite model (required for Phase 2)

YAMNet converts raw 16 kHz audio into 1024-dimensional embeddings that the
SUNO classifier head consumes. Without it, only the demo/mock path works.

```bash
cd ~/SUNO-AI
curl -L -o assets/ml/yamnet.tflite \
  "https://storage.googleapis.com/tfhub-lite-models/google/lite-model/yamnet/tflite/1.tflite"

# Verify size (~3.7 MB expected):
ls -lh assets/ml/yamnet.tflite
```

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

## 5. Supabase Edge Function for alert delivery (optional)

If you want real push notifications to trusted contacts:

```bash
npm install -g supabase
supabase login
supabase init
supabase functions new send-alert
```

The `send-alert` function receives `{ contactTokens: string[], payload: object }`
and calls the FCM HTTP v1 API using a service account. See Firebase docs:
https://firebase.google.com/docs/cloud-messaging/send-message

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
cd ~/SUNO-AI
git add -A
git status          # verify what's staged
git commit -m "feat: Phase 1-6 ML pipeline, real maps, Hive persistence, FCM push, bug fixes"
git push origin feature/backend-yamnet-tflite
```

---

## 8. App launcher icon (optional, removes blank icon)

Generate from your SUNO logo at:
https://romannurik.github.io/AndroidAssetStudio/icons-launcher.html

Place the output mipmap-* folders in `android/app/src/main/res/`.
