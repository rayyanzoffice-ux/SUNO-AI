# SUNO — Technical Documentation

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Tech Stack](#tech-stack)
4. [Project Structure](#project-structure)
5. [ML Audio Pipeline](#ml-audio-pipeline)
6. [Risk Engine](#risk-engine)
7. [Incident System](#incident-system)
8. [Safety Check Engine](#safety-check-engine)
9. [Alert Delivery (FCM + Supabase)](#alert-delivery)
10. [Foreground Service](#foreground-service)
11. [Location Handling](#location-handling)
12. [Screens & Navigation](#screens--navigation)
13. [Data Flow](#data-flow)
14. [CI/CD Pipeline](#cicd-pipeline)
15. [Testing](#testing)
16. [Configuration](#configuration)

---

## Overview

SUNO is a privacy-first personal safety application built with Flutter. It uses an on-device machine learning pipeline to detect distress sounds in real time, evaluates risk using a multi-signal scoring engine, and automatically alerts trusted contacts with live location when danger is detected. All audio processing happens locally — no audio is ever streamed to the cloud.

---

## Architecture

SUNO follows a **layered architecture** with the repository pattern and a central state coordinator.

```
┌─────────────────────────────────────────────────┐
│  Screens (UI Layer)                              │
│  HomeScreen, MonitoringScreen, EmergencyAlert... │
├─────────────────────────────────────────────────┤
│  Services (Coordinator Layer)                    │
│  SunoRuntimeService (ChangeNotifier singleton)   │
├─────────────────────────────────────────────────┤
│  Backend (Domain Layer)                          │
│  Detection, ML, Risk, Safety, Alerts, Location   │
├─────────────────────────────────────────────────┤
│  Models (Data Layer)                             │
│  Incident, DetectionResult, TrustedContact...    │
└─────────────────────────────────────────────────┘
```

**Key design decisions:**

- **Repository pattern with swappable implementations.** `IncidentRepository`, `TrustedContactRepository`, and `DetectionRepository` are abstract interfaces. Each has an in-memory implementation (for demo/testing) and a Hive-backed implementation (for production). The app can switch between them without changing any calling code.
- **Central coordinator via `SunoRuntimeService`.** Extends `ChangeNotifier` and serves as the single source of truth for app state. Holds `currentIncident`, `lastDispatchResult`, and `receivedAlert`. All screens observe it via `ListenableBuilder`.
- **No external state management library.** Uses Flutter's built-in `ChangeNotifier` + `ListenableBuilder` throughout.
- **MethodChannel bridge for native code.** `ForegroundServiceBridge` communicates with the Android foreground service via a `MethodChannel`.

---

## Tech Stack

| Category | Package | Version | Purpose |
|---|---|---|---|
| **Framework** | Flutter (Dart) | SDK ^3.13.1 | Cross-platform UI |
| **ML Inference** | `tflite_flutter` | ^0.12.1 | On-device TensorFlow Lite |
| **Audio Capture** | `record` | ^7.1.1 | PCM16 microphone recording at 44100Hz |
| **Maps** | `flutter_map` | ^6.1.0 | Tile rendering (MapTiler, OpenStreetMap fallback) |
| **Location** | `geolocator` | ^12.0.0 | GPS positioning |
| **Sensors** | `sensors_plus` | ^7.1.0 | Accelerometer for impact/stillness |
| **Haptics** | `vibration` | ^2.0.0 | Foreground Safety Check buzz |
| **Permissions** | `permission_handler` | ^11.3.1 | Runtime permission requests |
| **Persistence** | `hive_flutter` | ^1.1.0 | NoSQL local storage |
| **Firebase Core** | `firebase_core` | ^3.6.0 | Firebase initialization |
| **Push Messaging** | `firebase_messaging` | ^15.1.4 | FCM token management, background messages |
| **Notifications** | `flutter_local_notifications` | ^17.2.4 | Local notifications with full-screen intents |
| **Deep Links** | `url_launcher` | ^6.3.0 | Open Google Maps, external links |
| **IDs** | `uuid` | ^4.4.2 | UUID v4 generation |
| **Paths** | `path_provider` | ^2.1.4 | Filesystem paths |

**Build:** Gradle with Kotlin JVM target 17 (patched for tflite_flutter compatibility in CI).

---

## Project Structure

```
SUNO-AI/
├── android/app/src/main/
│   ├── AndroidManifest.xml
│   └── kotlin/com/example/suno_ai/
│       ├── MainActivity.kt
│       ├── MonitoringForegroundService.kt
│       └── SunoEngine.kt               # Retained FlutterEngine + method channel
├── assets/ml/
│   ├── labels.json                    # Label map & model metadata
│   ├── suno_audio_classifier.tflite   # Custom 4-class classifier (~1.2MB)
│   └── yamnet.tflite                  # YAMNet embedding model (~16MB)
├── lib/
│   ├── main.dart                      # App entry, Firebase init, FCM handlers
│   ├── app.dart                       # MaterialApp shell with route generation
│   ├── core/
│   │   ├── config/app_config.dart     # Relay URL, auth key, compile-time config
│   │   ├── routes/app_routes.dart     # Named route constants
│   │   └── theme/app_theme.dart       # App-wide theme (navy/purple)
│   ├── backend/
│   │   ├── audio/                     # Microphone capture, preprocessing, waveform
│   │   ├── alerts/                    # Alert service interface + FCM implementation
│   │   ├── contacts/                  # Trusted contact repository
│   │   ├── detection/                 # Detection engine, live & mock repositories
│   │   ├── incidents/                 # Incident repository interface
│   │   ├── location/                  # GPS location service
│   │   ├── ml/                        # YAMNet stage, continuous audio detector
│   │   ├── motion/                    # Impact & stillness detection (accelerometer)
│   │   ├── persistence/               # Hive storage, app storage constants
│   │   ├── risk/                      # Risk scoring engine
│   │   ├── safety/                    # Safety check countdown engine
│   │   └── services/                  # Foreground service bridge (MethodChannel)
│   ├── models/                        # Pure data classes
│   ├── screens/                       # Full-page UI screens
│   ├── services/                      # SunoRuntimeService, notification service
│   └── widgets/                       # Reusable UI components
├── ml/config/
│   └── labels.json                    # Full model metadata
├── supabase/functions/send-alert/
│   └── index.ts                       # Deno edge function (FCM relay)
├── test/                              # Unit & widget tests
├── .github/workflows/build-apk.yml    # CI/CD pipeline
├── pubspec.yaml
└── README.md
```

---

## ML Audio Pipeline

The audio ML pipeline is a **two-stage on-device inference system** with four processing stages. No audio leaves the device.

### Stage 0: Audio Capture (`MicrophoneCapture`)

- Uses the `record` package's `AudioRecorder`
- Records PCM16 at 44100Hz, mono channel
- Chunks of raw `Int16` bytes are fed into `AudioPreprocessor` in real time
- Also emits `AudioWaveform` objects (with normalized samples) for UI waveform visualization
- Handles permission checks; throws `MicrophonePermissionException` on denial

### Stage 1: Preprocessing (`AudioPreprocessor`)

- Converts 44100Hz Int16 PCM to normalized [-1.0, 1.0] float32 at 16000Hz
- Resampling via linear interpolation
- **Frame length:** 15,360 samples (0.96 seconds at 16kHz)
- **Frame hop:** 7,680 samples (0.48 seconds at 16kHz)
- Maintains an internal sliding window buffer; yields complete frames as they become available

### Stage 2: YAMNet Embedding (`YamNetStage`)

- **Model:** `yamnet.tflite` (~16MB)
- **Input:** `[15360]` float32 waveform tensor
- **Outputs:**
  - `[N_frames, 521]` class probabilities (unused by SUNO)
  - `[N_frames, 1024]` embedding vectors (used as input to Stage 3)
  - `[96, 64]` internal log-mel spectrogram (unused by SUNO)
- Returns `YamNetEmbedding` objects containing the 1024-dimensional embedding per frame
- Strictly validates input tensor shape
- **Only the embedding output is requested per inference.** The spectrogram
  output's shape is not statically resolvable before `invoke()` (TFLite reports
  a `[1, 64]` placeholder but produces `[96, 64]`), so pre-allocating a buffer
  for every output slot throws `Output object shape mismatch` on each call.
  `load()` scans the output tensors once, records the index of the one whose
  last dimension is `1024`, and `embed()` passes only that index to
  `runForMultipleInputs`. Do not revert this to "request all outputs".

### Stage 3: SUNO Classifier (`SunoAudioClassifier`)

- **Model:** `suno_audio_classifier.tflite` (~1.2MB)
- **Input:** `[1, 1024]` float32 embedding vector from YAMNet
- **Output:** `[1, 4]` float32 class probabilities
- **4 classes:**

| Index | Label | Description |
|---|---|---|
| 0 | `ambient_safe` | Normal ambient sound |
| 1 | `distress_voice` | Screams, cries, distress vocalizations |
| 2 | `alarm_siren` | Emergency alarms, sirens |
| 3 | `breaking_crash` | Breaking glass, crashes, impacts |

- Predictions below `confidence_threshold` (0.6 from `labels.json`) default to `ambient_safe`
- Validates `labels.json` metadata: embedding_size=1024, sample_rate=16000, frame_length=0.96, frame_hop=0.48

### Stage 4: Debounced Detection (`ContinuousAudioDetector`)

- Requires **3 consecutive** identical non-ambient class labels with average confidence above threshold before firing
- After firing a detection, enters a **cooldown of 6 frames** (~2.88 seconds) to avoid rapid re-triggering
- Emits `AudioEvent` objects with label, confidence, and timestamp

### Live Pipeline Assembly (`LiveDetectionRepository`)

Orchestrates all stages in sequence:
1. Starts microphone capture
2. Starts location refresh (every 30 seconds)
3. Starts impact/stillness detector (accelerometer)
4. Starts continuous audio detector
5. On audio event: consumes motion flags (impact/stillness), runs `RiskEngine.evaluateDetection()`, emits `DetectionResult` if riskScore > 0

ML labels are mapped to user-facing event types:
- `distress_voice` → "Distress Sound"
- `alarm_siren` → "Emergency Alarm"
- `breaking_crash` → "Impact / Breaking Sound"

---

## Risk Engine

The `RiskEngine` computes a **0–100 score** from multiple signal sources:

| Signal | Condition | Points |
|---|---|---|
| Audio (high confidence) | Distress class, confidence ≥ 0.80 | 50 |
| Audio (moderate confidence) | Distress class, confidence ≥ 0.60 | 35 |
| Audio (ambient) | `ambient_safe` label | 0 (never contributes) |
| Impact detected | `impactDetected == true` | +30 bonus |
| Stillness detected | `stillnessDetected == true` (post-impact) | +15 bonus |
| No user response | Safety check timeout | +20 escalation |

**Risk levels:**

| Score Range | Level | Action |
|---|---|---|
| 0–39 | Low | Logged only, no alert |
| 40–69 | Medium | Triggers 45-second safety check |
| 70–100 | Critical | Bypasses safety check, immediate escalation |

---

## Incident System

### Incident Model

Each `Incident` contains:
- `id` — UUID v4
- `detectionResult` — The detection that triggered it (event type, confidence, risk score, location)
- `status` — Current lifecycle state
- `createdAt` / `updatedAt` — Timestamps
- `contactResponseText` — Text from trusted contact response
- `origin` — `'self'` for locally detected, or display name for received alerts

### Status Lifecycle

```
detected → safety_check → alert_triggered → contact_notified → contact_checking → resolved
                                                              ↘ cancelled_by_user
```

| Status | Meaning |
|---|---|
| `detected` | Initial detection recorded |
| `safety_check` | Medium-risk; awaiting user response |
| `alert_triggered` | Escalated to emergency; contacts being notified |
| `contact_notified` | FCM alerts successfully sent |
| `contact_checking` | A contact has acknowledged they're checking |
| `resolved` | Incident resolved |
| `cancelled_by_user` | User dismissed/cancelled |

### Persistence

- **`IncidentRepository`** — Abstract interface with `save()`, `update()`, `latest()`, `getAll()`, `remove()`, `clear()`
- **`InMemoryIncidentRepository`** — List-backed, for demo/testing. Data lives only for the current session.
- **`HiveIncidentRepository`** — Uses Hive box `incidents`. Serializes incidents to/from `Map<String, dynamic>`. Status stored as wire value string. Full CRUD with JSON round-tripping. Backward-compatible with previously stored incidents (defaults `origin` to `'self'`).

---

## Safety Check Engine

The `SafetyCheckEngine` handles medium-risk detections with a **45-second countdown**.

The window is deliberately 45 seconds rather than 10: 10 seconds was too tight
to notice the phone and answer it. It is not longer either — this countdown is
the gate before trusted contacts are told something may be wrong, so stretching
it (e.g. to 15 minutes) would delay real escalation. A false alarm noticed late
is still recoverable through the Emergency screen's "I'm okay" action.

**Mechanism:**
- Uses Dart's `Completer<SafetyCheckResult>` pattern
- `startCountdown()` returns a `Future<SafetyCheckResult>` that resolves when:
  - **Timer expires** → outcome is `noResponse` (+20 risk escalation)
  - **User confirms safe** → outcome is `userConfirmedSafe` (incident cancelled)
  - **User escalates manually** → outcome is `noResponse` (immediate emergency alert)
  - **Owning screen is disposed** → outcome is `cancelled`, which is deliberately
    *not* treated as no-response so it cannot trigger an escalation
- If the safety check times out, the `RiskEngine` adds **+20 points** to the risk score during escalation
- The deadline is persisted on the `Incident` (`safetyCheckDeadline`) at detection time, so
  escalation depends on the clock, not on the Safety Check screen or app staying open

**UI (`SafetyCheckScreen`):**
- Animated countdown ring showing seconds remaining out of 45
- Vibrates once (`vibration` package) as soon as the screen appears, independently of the
  background notification channel, so the alert is physical in the foreground too
- "I AM SAFE" button → confirms safe, returns to monitoring
- "CAN'T RESPOND" button → immediate escalation to emergency alert screen

---

## Alert Delivery

Alerts flow through a **two-device push notification path** using Firebase Cloud Messaging relayed via a Supabase Edge Function.

### Outgoing Alerts (`FcmAlertService`)

1. `SunoRuntimeService.notifyTrustedContactsForCurrentIncident()` gathers all trusted contact FCM tokens
2. `FcmAlertService.sendAlert()` sends an HTTP POST to the Supabase edge function
3. Payload includes: incident ID, event type, risk score, risk level, location, sender FCM token
4. Authenticated via `X-SUNO-Relay-Key` header

### Supabase Edge Function (`send-alert/index.ts`)

- **Runtime:** Deno (TypeScript), deployed on Supabase
- **Authentication:** `X-SUNO-Relay-Key` header with constant-time comparison
- **Firebase Admin SDK:** Constructs a JWT (RS256) from a service account private key stored in environment variables. The JWT authenticates directly with the FCM v1 HTTP API.

**Supported actions:**

| Action | Purpose |
|---|---|
| `send_alert` | Send FCM notifications to a list of contact tokens (max 10) |
| `send_response` | Relay a contact's response back to the original sender |
| `test` | Send a silent data-only FCM ping (contact reachability test) |
| `cancel_incident` | Passthrough/no-op |

**Security:**
- Request body size limit: 16KB
- Token array: max 10 tokens, each max 4096 characters
- Text fields: max 256 characters
- Allowed event types validated against whitelist

### Incoming Alerts

- Remote messages are parsed from URL-encoded `key=value` data payloads
- Fields: `incidentId`, `eventType`, `riskScore`, `riskLevel`, `detectedAt`, `location`, `senderToken`, `latitude`, `longitude`
- Background messages handled by `firebaseMessagingBackgroundHandler`
- Received alerts are converted to `Incident` objects with `origin: 'Trusted Contact'` and persisted

### Two-Way Response Flow

1. Trusted contact receives push notification on their device
2. Opens `AlertReceivedScreen` showing event details, map, risk level
3. Taps a response: "I AM CHECKING ON THEM", "THEY ARE SAFE", or "UNABLE TO CONTACT"
4. Response sent back via Supabase edge function (`send_response` action)
5. Original sender's device receives the response, updates incident status and displays `contactResponseText` in real time on the Emergency Alert screen

---

## Foreground Service

### Retained Engine (`SunoEngine.kt`)

Live Mode monitoring runs in the Dart isolate, so the isolate has to outlive the
UI. `MainActivity.provideFlutterEngine()` returns the one engine held by
`SunoEngine` (created on demand and registered in `FlutterEngineCache` under
`suno_runtime`), and `shouldDestroyEngineWithHost()` returns `false`. The same
engine is therefore shared by the Activity and the foreground service, so
backgrounding or swiping the app away does not tear down the isolate that is
running inference.

`SunoEngine` also owns the Dart-facing side of the channel: it answers `start`,
`updateStatus` and `stop`, completes the pending start/stop results once the
service acknowledges them, and pushes the reverse notifications `stopRequested`
and `serviceStopped` so Flutter can react when Android ends monitoring on its own.

### Android Native (`MonitoringForegroundService.kt`)

- Extends Android `Service`
- Creates notification channel `suno_monitoring_channel` with `IMPORTANCE_LOW`
- Displays persistent notification: "SUNO is listening" (alert sound/vibration disabled)
- Uses `FOREGROUND_SERVICE_TYPE_MICROPHONE` on Android 14+ (API 34)
- Returns `START_STICKY` to be restarted by the system if killed
- `onTaskRemoved()` restarts the service when the app is swiped away (anti-kill resilience)
- `onDestroy()` removes the notification and reports back through `SunoEngine`

### Flutter Bridge (`ForegroundServiceBridge`)

- `MethodChannel` named `com.example.suno_ai/monitoring_service`
- Three commands: `start`, `updateStatus`, `stop`
- Installs handlers for the reverse `stopRequested` / `serviceStopped` calls
- Silently handles `MissingPluginException` and `PlatformException` (graceful degradation)
- `start` waits for the native acknowledgment and applies a timeout, so a hung
  service start surfaces as an error instead of leaving Live Mode half-started

### AndroidManifest Declarations

```xml
<service android:name=".MonitoringForegroundService"
         android:foregroundServiceType="microphone|location|shortService" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
```

---

## Location Handling

### LocationService

- Uses the `geolocator` package
- **Permission flow:** Checks if location services are enabled → requests foreground permission → requests background permission via `permission_handler`
- **Timeout:** 10-second timeout on position requests
- Returns `LocationSnapshot` with `latitude` and `longitude`

### Location in Detection Pipeline

- `LiveDetectionRepository` refreshes location every **30 seconds** during active monitoring
- Location is captured at the time of detection and embedded in `DetectionResult`
- Flows through to incidents and displayed on map previews in the UI

### Map Display (`MapPreviewCard`)

- Uses `flutter_map` with a build-time selectable tile provider: MapTiler
  (`streets-v2`) when `MAPTILER_KEY` is passed via `--dart-define`, otherwise the
  OpenStreetMap tiles. The attribution label switches with the provider so the
  required credit is always shown.
- Centered on incident coordinates with a location pin marker
- Tapping opens Google Maps via `url_launcher` with `geo:` URI
- Falls back to a placeholder card when coordinates are unavailable

---

## Screens & Navigation

### Route Table

| Route | Path | Screen |
|---|---|---|
| Home | `/` | `HomeScreen` |
| Monitoring | `/monitoring` | `MonitoringScreen` |
| Safety Check | `/safety-check` | `SafetyCheckScreen` |
| Emergency Alert | `/emergency-alert` | `EmergencyAlertScreen` |
| Alert Received | `/alert-received` | `AlertReceivedScreen` |
| History | `/history` | `HistoryScreen` |
| Contacts Setup | `/contacts-setup` | `ContactsSetupScreen` |

### Screen Details

**HomeScreen** — Navy background with SUNO logo (custom `CustomPaint` with gradient). Long-press on logo triggers Silent SOS bottom sheet. Primary "START MONITORING" button navigates to monitoring. "Trusted Contacts" button navigates to contacts setup. History icon in app bar.

**MonitoringScreen** — The most complex screen. Toggle between Demo and Live mode. Demo mode shows scenario chips (LOW/MEDIUM/CRITICAL) and a simulate button. Live mode initializes the full ML pipeline, starts the foreground service, and shows real-time waveform visualization (23 bars with RMS amplitude). When backgrounded during live monitoring, shows a full-screen intent notification. On detection, stops live mode and navigates to safety check or emergency alert.

**SafetyCheckScreen** — 45-second animated countdown ring that vibrates once on arrival. Two action buttons: "I AM SAFE" and "CAN'T RESPOND".

**EmergencyAlertScreen** — Shows event type, risk score, confidence, location, inline map preview. Displays dispatch status. Reactive via `ListenableBuilder` — updates in real time when a contact response arrives.

**AlertReceivedScreen** — Displayed when an FCM alert is received from another user's device. Shows event details, time, risk badge, map preview. Three response buttons: "I AM CHECKING ON THEM", "THEY ARE SAFE", "UNABLE TO CONTACT". Responses are relayed back via the Supabase edge function.

**HistoryScreen** — Filter bar (All/Alerts/Canceled). Dismissible cards with swipe-to-delete. Clear all button. Shows incident type, event, risk score, status badge, time (12-hour format), and origin for received alerts.

**ContactsSetupScreen** — Displays the user's own FCM token with a copy button. Lists contacts with popup menu (edit/delete/test). Test sends a silent FCM data-only ping. Add/edit form with fields: name, phone, relationship, FCM token.

**SilentSOSSheet** — Bottom sheet triggered by long-pressing the SUNO logo. Lists all verified contacts to alert individually, or "ALERT ALL CONTACTS" to broadcast. Creates a critical incident with real GPS location, bypassing audio detection entirely.

---

## Data Flow

```
Microphone (44100Hz PCM16)
  → AudioPreprocessor (resample to 16kHz, frame into 0.96s windows)
    → YAMNet (15360-sample frames → 1024-dim embeddings)
      → SUNO Classifier (1024-dim → 4-class probabilities)
        → ContinuousAudioDetector (debounce: 3 consecutive + 6 cooldown)
          → LiveDetectionRepository (combine with impact/stillness from accelerometer)
            → RiskEngine (score 0–100)
              → SunoRuntimeService (decide: ignore / safety check / escalate)
                → SafetyCheckEngine (10s countdown for medium risk)
                  → FcmAlertService → Supabase Edge Function → FCM API → Contact devices
                    → AlertReceivedScreen (contact responds)
                      → Supabase Edge Function (relay) → Sender's device
```

---

## CI/CD Pipeline

### GitHub Actions Workflow (`.github/workflows/build-apk.yml`)

- **Triggers:** Push to `main` or `feat/integration` branches, and manual `workflow_dispatch`
- **Runner:** Ubuntu latest

**Steps:**
1. Checkout code
2. Set up Java 17
3. Set up Flutter stable channel
4. `flutter pub get`
5. **Gradle patch:** Modifies tflite_flutter's gradle file to target JVM 17 (required for compatibility)
6. `flutter analyze` (static analysis)
7. `flutter test` (unit/widget tests)
8. **Build release APK:** `flutter build apk --release` with dart-defines:
   - `SUNO_ALERT_RELAY_URL=<supabase-url>`
   - `SUNO_RELAY_AUTH_KEY=${{ secrets.SUNO_RELAY_AUTH_KEY }}`
9. Rename output to `SUNO-final.apk`
10. Upload artifact with 30-day retention

---

## Testing

| Test File | Coverage |
|---|---|
| `risk_engine_test.dart` | Risk scoring logic, boundary conditions |
| `suno_audio_classifier_contract_test.dart` | ML model contract validation (input/output shapes, labels) |
| `suno_runtime_service_test.dart` | Central service behavior, incident lifecycle |
| `widget_test.dart` | End-to-end widget tests: home screen, detection scenarios (low/medium/critical), safety check flow, emergency alert flow, history screen, responsive layout at multiple screen sizes, backend API contract |

---

## Configuration

### Compile-Time Configuration

Values injected via `--dart-define` at build time:

| Key | Purpose | Default |
|---|---|---|
| `SUNO_ALERT_RELAY_URL` | Supabase edge function URL | Hardcoded in `app_config.dart` |
| `SUNO_RELAY_AUTH_KEY` | Authentication key for relay | GitHub secret |

### Model Configuration (`labels.json`)

| Key | Value |
|---|---|
| `embedding_size` | 1024 |
| `sample_rate` | 16000 |
| `frame_length` | 0.96 (seconds) |
| `frame_hop` | 0.48 (seconds) |
| `confidence_threshold` | 0.6 |
| `labels` | `["ambient_safe", "distress_voice", "alarm_siren", "breaking_crash"]` |

### Firebase

- **Firebase Core** (`firebase_core ^3.6.0`): Initialized in `main.dart` via `Firebase.initializeApp()`
- **Firebase Messaging** (`firebase_messaging ^15.1.4`): Token obtained at startup, stored for sharing with trusted contacts. Token refresh listener updates stored token. Background message handler registered. Foreground message handler processes incoming data payloads.
- The app uses **only FCM** from Firebase — no Analytics, Auth, Firestore, or Storage.

### Supabase

- **Project:** `uxqthxlgcyybbrpmfevk` (name: `suno-alerts`)
- **Endpoint:** `https://uxqthxlgcyybbrpmfevk.supabase.co/functions/v1/send-alert`
- **Runtime:** Deno (TypeScript)
- **Auth:** Service account private key stored in environment variable `FIREBASE_SERVICE_ACCOUNT_KEY`
