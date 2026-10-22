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
9. [Alert Delivery (FCM + SMS + Alarm)](#alert-delivery)
10. [Offline Resilience](#offline-resilience)
11. [Foreground Service](#foreground-service)
12. [Location Handling](#location-handling)
13. [Screens & Navigation](#screens--navigation)
14. [Data Flow](#data-flow)
15. [CI/CD Pipeline](#cicd-pipeline)
16. [Testing](#testing)
17. [Configuration](#configuration)

---

## Overview

SUNO is a privacy-first personal safety application built with Flutter. It uses an on-device machine learning pipeline to detect distress sounds in real time, evaluates risk using a multi-signal scoring engine, and alerts trusted contacts when danger is detected. Delivery is layered so a single failure does not silence the alert: push first, direct SMS when the relay cannot reach a contact, and an on-device alarm when neither channel reaches anyone. All audio processing happens locally — no audio is ever streamed to the cloud.

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

- **Repository pattern with swappable implementations.** `IncidentRepository`, `TrustedContactRepository`, `DetectionRepository`, `ProfileRepository`, and `LocaleRepository` are abstract interfaces. Each has an in-memory implementation (for demo/testing) and a Hive-backed implementation (for production). The app can switch between them without changing any calling code.
- **Central coordinator via `SunoRuntimeService`.** Extends `ChangeNotifier` and serves as the single source of truth for app state. Holds `currentIncident`, `lastDispatchResult`, and `receivedAlert`. All screens observe it via `ListenableBuilder`.
- **No external state management library.** Uses Flutter's built-in `ChangeNotifier` + `ListenableBuilder` throughout.
- **MethodChannel bridges for native code.** `ForegroundServiceBridge` talks to the Android foreground service and `SmsNativeBridge` talks to the native `SmsManager`; both degrade silently when the platform side is unavailable.
- **Offline-first alerting.** A cached GPS fix, the device's own SMS radio, and a local alarm keep the escalation path working without internet or a relay.

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
| **SMS (offline)** | Android `SmsManager` | OS API | Native Kotlin bridge; no SMS gateway package |

**Build:** Gradle with Kotlin JVM target 17 (patched for tflite_flutter compatibility in CI). The APK also bundles `android/app/src/main/res/raw/suno_alarm.wav` (~2.7 MB) for the last-resort alarm.

---

## Project Structure

```
SUNO-AI/
├── android/app/src/main/
│   ├── AndroidManifest.xml
│   ├── kotlin/com/example/suno_ai/
│   │   ├── AlarmPlayer.kt             # Native alarm-stream MediaPlayer
│   │   ├── MainActivity.kt
│   │   ├── MonitoringForegroundService.kt
│   │   ├── SmsSender.kt               # Native SmsManager bridge
│   │   └── SunoEngine.kt              # Retained FlutterEngine + method channels
│   └── res/raw/
│       └── suno_alarm.wav             # Last-resort alarm loop
├── assets/ml/
│   ├── labels.json                    # Label map & model metadata
│   ├── suno_audio_classifier.tflite   # Custom 4-class classifier (~1.2MB)
│   └── yamnet.tflite                  # YAMNet embedding model (~16MB)
├── lib/
│   ├── main.dart                      # App entry, Firebase init, FCM handlers
│   ├── app.dart                       # MaterialApp shell with route generation
│   ├── core/
│   │   ├── config/app_config.dart     # Relay URL, compile-time config
│   │   ├── l10n/                      # Locale controller, ARB accessors
│   │   ├── navigation/                # Global navigator key
│   │   ├── routes/app_routes.dart     # Named route constants
│   │   ├── theme/app_theme.dart       # App-wide theme (navy/purple)
│   │   └── utils/                     # Display names, time formatting
│   ├── backend/
│   │   ├── alerts/                    # FCM relay, SMS fallback, local alarm
│   │   ├── audio/                     # Microphone capture, preprocessing, waveform
│   │   ├── contacts/                  # Trusted contact repository
│   │   ├── detection/                 # Detection engine, live & mock repositories
│   │   ├── incidents/                 # Incident repository interface
│   │   ├── location/                  # GPS service + last-known cache
│   │   ├── ml/                        # YAMNet stage, continuous audio detector
│   │   ├── motion/                    # Impact & stillness detection (accelerometer)
│   │   ├── persistence/               # Hive boxes, repositories, cache storage
│   │   ├── profile/                   # Display name, locale repositories
│   │   ├── risk/                      # Risk scoring engine
│   │   ├── safety/                    # Safety check countdown engine
│   │   └── services/                  # Foreground service bridge (MethodChannel)
│   ├── l10n/                          # app_en.arb + 7 translated ARB files
│   ├── models/                        # Pure data classes
│   ├── screens/                       # Home, Monitoring, Settings, Language, ...
│   ├── services/                      # Runtime, monitoring, notifications, inbox
│   └── widgets/                       # Reusable UI components
├── ml/config/
│   └── labels.json                    # Full model metadata
├── supabase/functions/send-alert/
│   ├── index.ts                       # Deno edge function (FCM relay)
│   └── index_test.ts                  # Relay unit tests
├── test/                              # Unit & widget tests
├── .github/workflows/
│   ├── build-apk.yml                  # main/feat/integration → release APK
│   └── test-branch.yml                # fix/** → analysis + tests only
├── l10n.yaml
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
- **Outputs**, identified by their last dimension: `521` class probabilities,
  `1024` embeddings (Stage 3's input), and a `64`-bin internal log-mel
  spectrogram. SUNO reads only the embedding.
- Returns `YamNetEmbedding` objects containing the 1024-dimensional embedding per frame
- Strictly validates input tensor shape
- **Every declared output gets a buffer on each run.** `runForMultipleInputs()`
  copies into all of the model's outputs and null-checks each entry of the map
  handed to it, so requesting only the embedding crashes with `Null check
  operator used on a null value`.
- **Output row counts are measured, not assumed.** The model file states shapes
  that a real run then contradicts — the spectrogram reports one row before
  running and returns 96 — and the outputs do not share a row count. The
  rejection is raised *after* inference, so the true shapes are readable at
  that moment: `embed()` runs with the declared shapes, and on `ArgumentError`
  re-reads every output shape and runs once more. Steady-state frames use the
  measured shapes and never take that path.
- `load()` locates the embedding output by its `1024`-wide last dimension
  instead of assuming export order.

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
- `safetyCheckDeadline` — Persisted deadline for a medium-risk countdown
- `dispatchResult` — Per-channel delivery outcome (`sentCount`, `smsSentCount`, `failedReason`)
- `senderToken` / `senderName` / `senderLang` — Routing and language for received alerts

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
| `contact_notified` | At least one contact's push token was accepted by the relay. An SMS the OS accepted does not set this status on its own |
| `contact_checking` | A contact has acknowledged they're checking |
| `resolved` | Incident resolved |
| `cancelled_by_user` | User dismissed/cancelled |

### Persistence

- **`IncidentRepository`** — Abstract interface with `save()`, `update()`, `latest()`, `getAll()`, `remove()`, `clear()`
- **`InMemoryIncidentRepository`** — List-backed, for demo/testing. Data lives only for the current session.
- **`HiveIncidentRepository`** — Uses Hive box `incidents`. Serializes incidents to/from `Map<String, dynamic>`. Status stored as wire value string. Full CRUD with JSON round-tripping. The nested `dispatch` map persists `success`, `attemptedCount`, `sentCount`, `smsSentCount`, `queued`, and `failedReason`; older records without the key still load, with `smsSentCount` and `queued` defaulting to `false`/`0`. Backward-compatible with previously stored incidents (defaults `origin` to `'self'`).

---

## Safety Check Engine

The `SafetyCheckEngine` handles medium-risk detections with a **45-second countdown**.

The window is deliberately 45 seconds rather than 10: 10 seconds was too tight
to notice the phone and answer it. It is not longer either — this countdown is
the gate before trusted contacts are told something may be wrong, so stretching
it (e.g. to 15 minutes) would delay real escalation. A medium-risk false alarm is
cancelled with **I AM SAFE** on the Safety Check screen; for a critical incident that
has already dispatched, there is currently no self-service "I'm okay" action — the
incident is closed when a trusted contact responds that they are safe.

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
- Starting the countdown also starts the audible alarm for the exact time remaining (45 seconds
  for a new check, less when a persisted check is restored). The outcome handler stops it before
  escalating, so **I AM SAFE**, **CAN'T RESPOND**, and timeout all silence it; if the escalation
  then reaches nobody, the last-resort alarm deliberately starts again.

**UI (`SafetyCheckScreen`):**
- Animated countdown ring showing seconds remaining out of 45
- Vibrates once (`vibration` package) as soon as the screen appears, independently of the
  background notification channel, so the alert is physical in the foreground too
- "I AM SAFE" button → confirms safe, returns to monitoring
- "CAN'T RESPOND" button → immediate escalation to emergency alert screen

---

## Alert Delivery

Alerts flow through up to three layers, attempted in order:

| Layer | Transport | Needs | Fires when |
|---|---|---|---|
| 1. Push | FCM via Supabase Edge Function | Internet, contact FCM token | Every dispatch |
| 2. SMS | Device SIM via native `SmsManager` | `SEND_SMS`, contact phone number, carrier signal | Push did not confirm every contact (relay unreachable, a partial result, or a contact with only a phone) |
| 3. Local alarm | Native alarm-stream playback + notification card | Alarm volume (vibration fallback; notification permission only for the card) | Neither push nor SMS was accepted for anyone |

`AlertDispatchResult` records the outcome on the incident: `attemptedCount`, `sentCount` (push tokens the relay accepted), `smsSentCount` (SMS the OS confirmed it submitted), `queued` (the push half is saved for retry), `failedReason`, and the derived `totalDelivered` / `partiallyDelivered` / `usedSmsFallback`. `success` is deliberately **push-only**: true when every attempted contact's token was accepted by the relay. Android confirming `SMS_SENT` proves the phone handed the message to the radio, not that the contact received it, so SMS never makes `success` true and never moves the incident to `contact_notified` by itself.

### Outgoing Push Alerts (`FcmAlertService`)

1. `SunoRuntimeService.dispatchIncident()` gathers the trusted contacts' non-empty FCM tokens and de-duplicates them.
2. `FcmAlertService.sendAlert()` batches tokens within the relay's ten-token and 16KB limits and POSTs to the Supabase Edge Function with an 8-second timeout. It returns the set of tokens the relay accepted, read from the per-token `results` array in request order, so acceptance is tracked per contact rather than as one aggregate number.
3. The payload carries `incidentId`, `eventType`, `riskScore`, `riskLevel`, `detectedAt`, `isSimulated`, optional `latitude` / `longitude` / `locationText`, `senderToken`, `senderName`, `lang` (with legacy `languageCode`), and — when the fix came from the cache — `locationIsCached` plus `locationAgeMinutes`. That is at most 15 keys, inside the relay's 16-key cap.
4. Requests authenticate with the `X-SUNO-Relay-Key` header.

A zero or invalid relay acceptance count is treated as push failure, not success: a response whose `sent` / `attempted` / `results` disagree is rejected with a `StateError`. Acceptance collected from earlier batches is kept when a later batch fails, so a partial result is never discarded because of a subsequent error.

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
- At most 16 payload keys, each key ≤ 64 characters
- Allowed event types validated against whitelist

### SMS Fallback (`SmsFallbackService`)

Triggered for every contact push did not reach — a relay timeout, an offline device, a partial failure, or a contact who has a number but no recorded token.

- Phone numbers are reduced to digits plus one leading `+`; blanks are skipped and duplicate numbers are sent once.
- Every number receives the same plain-GSM-7 message, kept short to limit segments:
  `SUNO EMERGENCY: <sender> - <event> (risk N%). Location: https://maps.google.com/?q=<lat>,<lon>. Sent by SMS - SUNO could not reach the push alert.`
  When the location is cached the message says `(last known fix, Nm old)`; with no coordinates it says `Location unavailable.`
- `SmsNativeBridge` calls `SmsSender.kt` over `com.example.suno_ai/sms`. The native side checks `SEND_SMS` through `PackageManager`, picks the platform `SmsManager` (or the deprecated default below API 31), splits long messages with `divideMessage()`, and registers a receiver for the per-part `SMS_SENT` `PendingIntent`s. It resolves `true` only when every part reports `Activity.RESULT_OK`. A generic failure, no service, radio off, or missing balance therefore resolves `false`; a 6-second wait that receives no broadcast also resolves `false`. The Dart bridge waits 9 seconds, leaving the native side time to report first.
- No delivery receipt is requested. `smsSentCount` means "the OS confirmed it submitted the SMS", not "delivered to the contact".
- Failures are swallowed into `false`; the dispatch never crashes because a SIM or balance is missing.

### Last-Resort Local Alarm (`LocalAlarmService`)

If `delivered == 0` and at least one contact was attempted, SUNO alerts the person next to the phone.

- The tune is played by `AlarmPlayer.kt` (a looping `MediaPlayer` on `AudioAttributes.USAGE_ALARM`) over the `com.example.suno_ai/alarm` channel. Playback lives in the app process and ignores notification permission and activity visibility, so it stays audible with SUNO in the background or its task swiped away: the pending safety check keeps `MonitoringForegroundService` (`stopWithTask="false"`) running, and the cached `FlutterEngine` keeps the isolate alive. `start()` returns `false` when the WAV cannot be decoded, and Dart then vibrates instead.
- The `suno_local_alarm_v3` channel is registered at startup with `Importance.max` and vibration but **no sound**. The notification supplies the visible card, full-screen intent and vibration, while the tune comes from the native player, so the two can never overlap. Android freezes channel settings after first creation, which is why each change to the sound strategy needs a new channel id.
- `res/raw/suno_alarm.wav` is referenced from Kotlin (`R.raw.suno_alarm`) and from Dart by name, so R8/resource shrinking can remove it from release APKs. `res/raw/keep.xml` (`tools:keep="@raw/suno_alarm"`) pins it in the build. The file is 16-bit PCM so every Android version can decode it.
- The countdown passes the remaining time as `durationMs`. The native side also stops the tune and a duration-bounded vibration waveform at that deadline, so a throttled Dart isolate cannot leave the phone ringing or buzzing past the 45 seconds. Without a duration (the post-dispatch last resort) both loop until the alarm is acknowledged or the incident is resolved. The vibration is started natively with the tune, so it still works when notification permission is denied; when the process is killed early the bounded waveform ends on its own.
- Payload `type=emergency_alert&incidentId=...&alarm=1` opens the incident when tapped and tells `main.dart` to stop the native loop. It is deliberately not treated as an inbound alert.
- Resolving or cancelling the incident through `updateStatus()` cancels the notification, stops the native player and cancels vibration. `applyContactResponse` stops it too once the new status is persisted, but only for `resolved` — a "checking on them" response leaves the alarm sounding. A force-stop from Android settings kills the process, so no alarm layer can sound in that state even though the countdown keeps its deadline.

### Incoming Alerts

- Remote messages are parsed from URL-encoded `key=value` data payloads
- Fields: `incidentId`, `eventType`, `riskScore`, `riskLevel`, `detectedAt`, `location` (also accepted as `locationText`), `senderToken`, `senderName`, `isSimulated`, `latitude`, `longitude`, plus `lang` — read before the older `languageCode` — naming the sender's language for the push banner
- Background messages handled by `firebaseMessagingBackgroundHandler`
- Received alerts are converted to `Incident` objects with `origin: 'Trusted Contact'` and persisted
- The language code is kept only when it is one of the 8 supported codes, stored on the incident as `senderLang`, and selects the language of the reply that goes back; unknown or missing means English

### Two-Way Response Flow

1. Trusted contact receives push notification on their device
2. Opens `AlertReceivedScreen` showing event details, map, risk level
3. Taps a response: "I AM CHECKING ON THEM", "THEY ARE SAFE", or "UNABLE TO CONTACT" — these labels are shown in the responder's own language, the English above being the template
4. Response sent back via Supabase edge function (`send_response` action)
5. Original sender's device receives the response, updates incident status and displays `contactResponseText` in real time on the Emergency Alert screen
6. The message the person in danger actually reads is built in **their** language, not the responder's; the responder's own status line stays in the language of their app

---

## Offline Resilience

Three offline layers keep an alert useful when the network, relay, or contact tokens fail.

### Last-Known Location Cache

- Every successful `LocationService.currentLocation()` writes a `LocationSnapshot` (latitude, longitude, capture time) to Hive box `location_cache` under key `last_known`. The write is wrapped in try/catch: a failed cache write never interrupts detection or dispatch.
- While Live monitoring is active, `MonitoringService` owns a 30-minute `Timer.periodic` that calls `LocationService.refreshCacheQuietly()`. Every app resume also triggers one quiet refresh, so the cache keeps ageing truthfully when the timer is not running. The refresh returns immediately unless location services are enabled and permission is already granted, so it never prompts and never changes the UI's `status`. Stopping monitoring cancels the timer.
- Alert paths call `refreshLocation(useCache: true)` → `LocationService.bestEffortLocation()`: a fresh high-accuracy fix with a 6-second limit and **no permission dialog**, then the cached snapshot if that fails.
- A cached snapshot has `isCached == true`; its age is computed from the original capture time. The push payload gains `locationIsCached` / `locationAgeMinutes`, the SMS says `(last known fix, Nm old)`, and the in-app location shows the cached coordinates rather than an invented one.
- Ordinary UI lookups still use permission-aware, non-cached requests, so a stale fix is never displayed as if it were live.
- The cache is local-only and cleared only with app data.

### Offline Alert Outbox

A push alert raised with no internet must not be lost, and it must not be reported as delivered.

- **Queue:** when the relay throws or times out, the runtime saves a `PendingAlert` (incident id,
  the exact payload, the contact tokens, a timestamp, and an attempt count) to Hive box
  `alert_outbox`. Queuing needs at least one FCM token; it also happens when Firebase failed to
  initialise, which is common when the app launches offline, because the next launch can deliver
  the saved alert. A relay that answers and rejects every token is *not* queued: retrying an
  invalid token cannot succeed.
- **Retry:** `startPendingAlertRetries()` runs at launch, `retryPendingAlerts()` runs on every app
  resume, and a one-minute timer covers a connection that returns while the app stays open. An
  entry is removed once the relay accepts at least one token (and the incident's dispatch result is
  updated), once the relay answers with no accepted tokens, or when the incident is resolved,
  cancelled, deleted, or history is cleared.
- **Scope:** only the push half is retried. Re-sending SMS automatically could duplicate messages
  the OS already submitted, so SMS remains a single best-effort attempt.
- **Wording:** while queued, the Emergency screen says the alert is saved on the device and will be
  sent automatically; if an SMS was submitted first, it says so and marks delivery as unconfirmed.

### SMS Permission

- `SEND_SMS` is requested once per contacts-screen visit, and only after a contact with a non-empty phone number is saved. `SmsPermission.ensureGranted()` returns a bool; denial is surfaced in the UI but never blocks saving the contact.
- With the permission denied, push alerts still work; only the offline fallback is unavailable.
- The native layer re-checks the permission before every send, so a permission revoked in Android settings turns into a `false` result rather than an exception.

### Dispatch Fallback Order

`SunoRuntimeService._dispatch()`:

1. Collect the trusted contacts in scope (all of them, or the single `onlyContactId` when the alert targets one person). `attemptedCount` is the number of contacts, not the number of tokens, because each contact can be reached on either channel.
2. Send push for the distinct tokens with an 8-second timeout. A thrown error becomes an empty accepted set with `pushFailure`.
3. Map the accepted tokens back to contacts: a contact counts as reached by push only when its own token was accepted in this attempt.
4. Save the push half in the outbox when push failed and tokens exist — before SMS, so a long row of SMS timeouts or a process kill cannot lose it.
5. Run the SMS fallback for every contact not reached by push, including a contact with no token at all.
6. If `delivered == 0` and `attempted > 0`, start the local alarm.
7. Persist `AlertDispatchResult`. Set `contact_notified` only when at least one push token was accepted; an SMS-only result stays `alert_triggered` because submission is not delivery.

Two guards set `failedReason` without pretending a channel ran: an empty contact list reports `No trusted contacts to notify`, and a dispatch whose contacts have neither a token nor a phone number reports `No contacts with a push token or phone number`. A contact with a token is queued even when Firebase is unavailable, because the next launch can deliver it.

### Known Limitations

- **`attemptedCount` counts contacts, so it can exceed distinct tokens.** Two contacts sharing one FCM token are both credited when that token is accepted, even though they received a single push. This is intentional: the channel did reach both people.
- **SMS is best-effort.** The OS confirming `SMS_SENT` means the radio accepted the message; it is not a carrier delivery receipt, so SMS-only dispatches are not labelled "reached".
- **Queued alerts retry push only.** A phone-only contact cannot have its SMS retried automatically; a second automatic attempt could duplicate a message the OS already submitted.
- **Shared phone numbers are counted once.** Numbers are de-duplicated before sending, so two contacts with the same number produce one SMS and one submission credit; the stored result can therefore look lower than the number of people whose phone may have received the text.
- **The alarm depends on device state.** It cannot override a muted media stream, Do Not Disturb policy, or a user who cannot hear the phone. Android freezes channel sound and name after first creation, so editing the bundled WAV requires uninstalling the app or changing the channel id.
- **A stale cache stays stale.** If SUNO never ran Live with location permission, or location stayed disabled, the cache is empty and alerts report location unavailable. `locationAgeMinutes` makes staleness visible, but does not bound it.

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
<uses-permission android:name="android.permission.SEND_SMS" />
```

---

## Location Handling

### LocationService

- Uses the `geolocator` package
- **Permission flow:** Checks if location services are enabled → requests foreground permission → requests background permission via `permission_handler`
- **Timeout:** 10-second default on user-visible position requests; `bestEffortLocation()` uses 6 seconds and never opens a permission dialog
- Returns `LocationSnapshot` with `latitude`, `longitude`, `capturedAt`, and `isCached`
- Caches every successful fix in Hive (`location_cache` / `last_known`) and can return that cached snapshot when GPS is unavailable
- See [Offline Resilience](#offline-resilience) for the cache lifecycle.

### Location in Detection Pipeline

- `LiveDetectionRepository` refreshes location every **30 seconds** during active monitoring; a detection only uses a fix captured within the last **60 seconds**, otherwise it records no coordinates
- Separately, `MonitoringService` warms the location cache every **30 minutes** while Live is running
- Location is captured at the time of detection and embedded in `DetectionResult`
- Alert dispatch uses `bestEffortLocation()`, so a fresh fix is preferred but the cached fix is accepted — flagged with its age — when GPS cannot produce one
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
| Settings | `/settings` | `SettingsScreen` |
| Language Selection | `/language-selection` | `LanguageSelectionScreen` |
| Language Setup (first run) | `/language-setup` | `LanguageSelectionScreen(isFirstRun: true)` |

### Screen Details

**HomeScreen** — Navy background with SUNO logo (custom `CustomPaint` with gradient). Long-press on logo triggers Silent SOS bottom sheet. Primary "START MONITORING" button navigates to monitoring. "Trusted Contacts" button navigates to contacts setup. History icon in app bar, settings icon opens the language settings. Before a language is chosen, the app starts at the first-run language picker.

**SettingsScreen** — Shows the current language and opens the language picker. The choice is persisted and applies immediately, including right-to-left layout for Arabic and Urdu.

**LanguageSelectionScreen** — First-run picker and the settings entry point for changing language. Eight languages: English, Chinese, Hindi, Spanish, French, Urdu, Arabic, and Bengali.

**MonitoringScreen** — The most complex screen. Toggle between Demo and Live mode. Demo mode shows scenario chips (LOW/MEDIUM/CRITICAL) and a simulate button. Live mode initializes the full ML pipeline, starts the foreground service, and shows real-time waveform visualization (23 bars with RMS amplitude). When backgrounded during live monitoring, shows a full-screen intent notification. On detection, stops live mode and navigates to safety check or emergency alert.

**SafetyCheckScreen** — 45-second animated countdown ring that vibrates once on arrival. Two action buttons: "I AM SAFE" and "CAN'T RESPOND".

**EmergencyAlertScreen** — Shows event type, risk score, confidence, location, inline map preview. Displays the dispatch result with push and SMS counts and partial-failure detail. Reactive via `ListenableBuilder` — updates in real time when a contact response arrives.

**AlertReceivedScreen** — Displayed when an FCM alert is received from another user's device. Shows event details, time, risk badge, map preview. Three response buttons: "I AM CHECKING ON THEM", "THEY ARE SAFE", "UNABLE TO CONTACT". Responses are relayed back via the Supabase edge function.

**HistoryScreen** — Filter bar (All/Alerts/Canceled). Dismissible cards with swipe-to-delete. Clear all button. Shows incident type, event, risk score, status badge, time (12-hour format), and origin for received alerts.

**ContactsSetupScreen** — Displays the user's own FCM token with a copy button. Lists contacts with popup menu (edit/delete/test). Test sends a silent FCM data-only ping. Add/edit form with fields: name, phone, relationship, FCM token. Saving a contact with a phone number asks for `SEND_SMS` once; denial is warned about but does not block the save.

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
                → bestEffortLocation (6s fresh fix → cached last-known fix)
                → SafetyCheckEngine (45s countdown for medium risk)
                  → dispatchIncident
                    → FcmAlertService → Supabase Edge Function → FCM API → Contact devices
                      → if push reached fewer contacts than attempted:
                        → SmsFallbackService → SmsNativeBridge → SmsSender.kt
                          → carrier SMS → contact phones
                      → if neither channel reached anyone (attempted > 0):
                        → LocalAlarmService → looping alarm on the sender's phone
                    → AlertReceivedScreen (contact responds)
                      → Supabase Edge Function (relay) → Sender's device
```

---

## CI/CD Pipeline

Two GitHub Actions workflows split fast verification from the heavy APK build.

### Release build (`.github/workflows/build-apk.yml`)

- **Triggers:** Push to `main` or `feat/integration`, and manual `workflow_dispatch`
- **Runner:** Ubuntu latest, 30-minute job timeout
- **Secrets:** `SUNO_RELAY_AUTH_KEY` (required) and `MAPTILER_KEY` (optional; a warning is emitted and OSM tiles are used without it)

**Steps:**
1. Checkout code
2. Set up Java 17 (Temurin) and Flutter stable with pub caching
3. `flutter pub get`
4. Upload the resolved `pubspec.lock` as `pubspec-lock` (7-day retention). There is no Flutter SDK in the development environment used for this repo, so CI is how the lockfile gets refreshed and committed after a dependency change.
5. **Gradle patch (tflite):** rewrites tflite_flutter's gradle file to JVM 17
6. **Gradle patch (vibration):** raises the `vibration` plugin's `compileSdk` from 33 to 36; the plugin pins android-33 while its androidx dependencies require 34+. The same patch is documented in `SETUP_INSTRUCTIONS.md` for local builds.
7. `flutter analyze --no-fatal-infos --no-fatal-warnings`
8. `flutter test`
9. **Build release APK:** `flutter build apk --release` with dart-defines:
   - `SUNO_ALERT_RELAY_URL=https://uxqthxlgcyybbrpmfevk.supabase.co/functions/v1/send-alert`
   - `SUNO_RELAY_AUTH_KEY=${{ secrets.SUNO_RELAY_AUTH_KEY }}`
   - `MAPTILER_KEY=${{ secrets.MAPTILER_KEY }}`
10. Copy the output to `SUNO-final.apk`
11. Upload `SUNO-final-apk` (30-day retention)

The build step fails if `SUNO_RELAY_AUTH_KEY` is missing, because an APK built without it cannot dispatch alerts.

### Branch verification (`.github/workflows/test-branch.yml`)

- **Triggers:** Push to any `fix/**` branch, and manual `workflow_dispatch`
- **Runner:** Ubuntu latest, no Android SDK or APK build
- **Steps:** checkout → Flutter stable → `flutter pub get` → `flutter analyze --no-fatal-infos --no-fatal-warnings` → targeted `persistence_test.dart` → two named `widget_test.dart` checks → full `flutter test --timeout 90s`
- Each test step has its own timeout and `if: always()`, and output is tee-ed to a log; `test-logs` is uploaded even when a step fails, so a hanging test is attributed instead of consuming the whole job.

### Local verification

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

The analyze command is deliberately non-fatal for infos and warnings; it currently reports a handful of pre-existing findings (dead code in the safety screen, an unused catch stack, an unused test import, and initializing-formals suggestions). None of them fail the build.

---

## Testing

| Test File | Coverage |
|---|---|
| `risk_engine_test.dart` | Risk scoring logic, boundary conditions |
| `suno_audio_classifier_contract_test.dart` | ML model contract: labels metadata and bundled model asset |
| `suno_runtime_service_test.dart` | Incident lifecycle, safety deadlines, responses, payload contents, SMS fallback, saved-alert retry and the countdown/local alarms |
| `audio_pipeline_test.dart` | Resampling across uneven chunks, reset, debounce, motion consumption and sensor failure |
| `location_service_test.dart` | Permission/disabled/timeout handling, fix caching, `bestEffortLocation`, quiet refresh |
| `sms_fallback_service_test.dart` | Number cleaning/deduplication, OS-acceptance counting, GSM-7 message content, cached-fix age |
| `fcm_alert_service_test.dart` | Token normalization/batching, acceptance accounting, oversized/invalid relay responses |
| `alert_surfacing_test.dart` | Which received critical alert is surfaced, selection window, payload for the alert screen |
| `persistence_test.dart` | Hive round-trips (incidents and the queued-alert outbox) and corrupt inbox messages |
| `locale_controller_test.dart` | First-run language choice, persistence, bad codes, reply language |
| `language_selection_test.dart` | First-run Continue and tile selection both persist the chosen language |
| `l10n_arb_parity_test.dart` | All eight ARB files have exactly the English key set |
| `localized_render_test.dart` | All eight languages render without overflow, including RTL |
| `time_format_test.dart` | Localized digits and dates, shared ASCII helpers |
| `display_name_test.dart` | Display-name sanitizing: control characters, length, Unicode |
| `map_preview_test.dart` | External map-launch failure stays on screen with a message |
| `widget_test.dart` | End-to-end flows: home, detection scenarios, safety check, emergency alert, history, contacts, responses, service bridge, phone-size layouts |
| `helpers/test_app.dart` | Shared widget-test harness (not a test file) |

The relay has its own Deno unit tests in `supabase/functions/send-alert/index_test.ts`. The Flutter suite is 166 tests at the time of writing; `flutter test` is the single command CI runs.

---

## Configuration

### Compile-Time Configuration

Values injected via `--dart-define` at build time:

| Key | Purpose | Default |
|---|---|---|
| `SUNO_ALERT_RELAY_URL` | Supabase edge function URL | Hardcoded in `app_config.dart` |
| `SUNO_RELAY_AUTH_KEY` | Authentication key for the relay | No default; supplied as a GitHub secret or `--dart-define` |
| `MAPTILER_KEY` | MapTiler raster tiles | Unset → OpenStreetMap tiles |

### Offline and Dispatch Constants

| Constant | Value | Where |
|---|---|---|
| Location cache refresh | 30 minutes | `MonitoringService` |
| Fresh fix before falling back to cache | 6 seconds | `LocationService.bestEffortLocation()` |
| Detection location freshness | 60 seconds | `LiveDetectionRepository` |
| Push dispatch timeout | 8 seconds | `SunoRuntimeService._dispatch()` |
| SMS bridge timeout per number | 9 seconds (Dart) / 6 seconds (native `SMS_SENT` wait) | `SmsNativeBridge`, `SmsSender.kt` |
| Relay limits | 10 tokens, 16 payload keys, 16 KiB body, 256-character text | `send-alert/index.ts` |
| Local alarm channel / notification id | `suno_local_alarm_v3` / `0x50A0` | `detection_notification_service.dart`, `local_alarm_service.dart`, `AlarmPlayer.kt` |

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
- **Secrets:** `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` (the service account fields), plus `SUNO_RELAY_AUTH_KEY` for request authentication
