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
- **Contact reachability testing** — send a silent FCM test message and mark contacts as verified when delivery succeeds.

## On-device ML pipeline

1. **Microphone capture** — 16 kHz mono PCM.
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

`SunoRuntimeService` is the central coordinator. It is framework-free and wired to either in-memory or Hive-backed repositories, making the UI testable without a real database.

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
git checkout feature/day2-integration
flutter pub get
flutter run
```

## Demo flow

1. Open SUNO.
2. Tap **Start Monitoring**.
3. SUNO listens in the background with a foreground service notification.
4. On a detected distress/impact event:
   - **Medium risk** → Safety Check countdown (tap *I AM SAFE* to cancel).
   - **Critical risk** → Emergency Alert is triggered immediately.
5. Emergency Alert shows event type, risk score, and location.
6. Trusted contacts with a saved FCM token receive a push notification and can respond back to the sender.
7. The sender sees the contact's response on the Emergency Alert screen.
8. Incident is saved to local history.

## Privacy

SUNO is designed to be privacy-first:

- All audio classification runs on the device.
- Raw audio never leaves the phone.
- Only incident metadata (event type, risk score, location coordinates, timestamp) is sent to trusted contacts when an alert is triggered.
- Contact responses (responder name, chosen status, short message) are relayed back to the original sender through the same FCM relay; no response data is stored on Supabase.

## License

Hackathon prototype — provided as-is for demonstration and educational use.
