# SUNO — AI Safety Companion

> It listens for danger, not conversations.

SUNO is an Android-first Flutter prototype that uses on-device audio AI to detect potential emergencies — distress sounds, alarms, and impact noises — and guides the user through a private, local-first safety flow.

## What it does

- **Real-time audio monitoring** using the device microphone.
- **On-device sound classification** with YAMNet embeddings + a custom 4-class SUNO classifier.
- **Risk scoring engine** that combines audio class confidence with motion sensors (impact / stillness).
- **Safety Check countdown** for medium-risk events — user can confirm they are safe.
- **Emergency Alert** for critical risk, with location and event details.
- **Trusted Contact notifications** via Firebase Cloud Messaging (FCM relay through Supabase Edge Functions).
- **Two-way contact responses** — contacts who receive an alert can tap *I AM CHECKING ON THEM*, *THEY ARE SAFE*, or *UNABLE TO CONTACT*, and the response is relayed back to the sender's device.
- **Silent SOS** manual trigger for situations where the user cannot make a sound.
- **Incident history** persisted locally with Hive, with swipe-to-dismiss and clear-all support.
- **Map preview** of incident location using OpenStreetMap, with one-tap open in Google Maps.
- **Contact token testing** — send a silent test and record FCM acceptance. Acceptance does not prove the other phone displayed or received a notification.

## On-device ML pipeline

1. **Microphone capture (Live only)** — 44.1 kHz mono PCM, continuously resampled to 16 kHz for inference.
2. **YAMNet** (pretrained TF Lite, ~16 MB) converts audio into 1,024-dimensional embeddings.
3. **SUNO classifier head** (custom TF Lite, ~1.2 MB) classifies each embedding into one of four classes:
   - `ambient_safe`
   - `distress_voice`
   - `alarm_siren`
   - `breaking_crash`
4. **Risk engine** converts the audio class + motion context into a 0–100 risk score.
5. **Decision**:
   - **Low (0–39)** — keep monitoring.
   - **Medium (40–69)** — show Safety Check countdown.
   - **Critical (70–100)** — trigger Emergency Alert and notify trusted contacts.

The classifier was retrained on a cleaned dataset of 243 balanced audio clips and reaches ~79% validation accuracy on the four-class task.

## Architecture

```
lib/
├── backend/
│   ├── alerts/            # FCM alert service
│   ├── audio/             # Microphone capture + preprocessing
│   ├── contacts/          # Trusted contact repository contracts
│   ├── detection/         # YAMNet/classifier adapters + detection repository
│   ├── incidents/         # Incident repository contracts
│   ├── location/          # GPS location service
│   ├── ml/                # Continuous audio detector + YAMNet stage
│   ├── motion/            # Accelerometer impact/stillness detector
│   ├── persistence/       # Hive-backed repositories
│   ├── risk/              # Risk scoring engine
│   └── services/          # Android foreground service bridge
├── models/                # DetectionResult, Incident, TrustedContact
├── screens/               # Home, Monitoring, Safety Check, Emergency Alert, etc.
├── services/              # SunoRuntimeService — app-level coordinator
└── widgets/               # Reusable UI components
```

`SunoRuntimeService` is a Flutter `ChangeNotifier` coordinating persisted incidents, per-incident responses, dispatch results, and safety deadlines independently of screens. Repositories can be injected for tests. `MonitoringService` owns the Live audio pipeline; Android uses a single retained Flutter engine rather than a second Hive-writing runtime. Background FCM callbacks write an atomic inbox that the main runtime drains.

## Tech stack

- Flutter / Dart
- TensorFlow Lite via `tflite_flutter`
- YAMNet (TF Hub) + custom Keras classifier head
- Hive for local persistence
- Firebase Core + Firebase Cloud Messaging
- Supabase Edge Functions for the FCM relay
- OpenStreetMap via `flutter_map`
- `geolocator`, `sensors_plus`, `permission_handler`, `record`
- `flutter_local_notifications`, `url_launcher`

## Setup

See [`SETUP_INSTRUCTIONS.md`](SETUP_INSTRUCTIONS.md) for full Flutter environment setup, model download, Firebase configuration, Supabase deploy, and build commands.

Quick start after setup:

```bash
git clone https://github.com/rayyanzoffice-ux/SUNO-AI.git
cd SUNO-AI
git checkout feat/integration
flutter pub get --enforce-lockfile
flutter run --dart-define=SUNO_RELAY_AUTH_KEY="YOUR_DEMO_KEY"
```

## Demo flow

1. Configure the relay and consenting test contacts, then open **Start Monitoring → Demo Mode**.
2. Allow GPS. Demo never listens or loads inference models.
3. Select **LOW**, **MEDIUM**, or **CRITICAL** and press **Demo: Simulate Distress**. Only the danger input is simulated; GPS, storage, countdown and contact sends are real.
4. Low creates no incident. Medium starts a persisted ten-second safety deadline immediately; **I AM SAFE** cancels and **CAN'T RESPOND** escalates. Timeout does not depend on keeping the safety screen open. Critical dispatches immediately.
5. The alert stores one location snapshot, used in the contact payload and maps. Pan/zoom the map or use **OPEN** externally; this is location at alert time, not continuous remote tracking.
6. Check the saved FCM acceptance/partial-failure result. On the other phone, visibly verify the notification and send a response; the sender updates the referenced incident, not an unrelated active alert.
7. Reopen history to verify persistence. Separately test **Silent SOS** and **Live Mode**, which alone activates microphone capture and on-device inference.

Source checks do not establish device readiness. Before a regional demo, deploy the reviewed relay separately and verify two consenting Android phones: GPS/map opening, medium safe/timeout, critical, SOS, response routing, offline/denied-permission recovery and foreground/background/cold-start notifications. Live task removal, screen-off operation, reopening and explicit stop require checks on the actual devices. Force-stop, process death, reboot and arbitrary OEM restrictions are not covered by a background-survival guarantee.

## Privacy

SUNO is designed to be privacy-first:

- All audio classification runs on the device.
- Raw audio never leaves the phone.
- Only incident metadata (event type, risk score, location coordinates, timestamp) is sent to trusted contacts when an alert is triggered.
- Contact responses (responder name, chosen status, short message) are relayed back to the original sender through the same FCM relay; no response data is stored on Supabase.

## License

Hackathon prototype — provided as-is for demonstration and educational use.
