# SUNO-AI

SUNO is a cost-free hackathon prototype for an AI Safety Companion.

The prototype flow is:

1. Home
2. Monitoring
3. Detection Result
4. Safety Check
5. Emergency Alert
6. Trusted Contact View
7. History

## Hackathon Scope

Build a working demo in 3 days, not a production app.

## Team Split

- Person 1: Frontend
- Person 2: Backend / Logic

## Main Documents

- `TASKS.md` — complete ordered task division
- `FRONTEND_TASKS.md` — Person 1 work order
- `BACKEND_TASKS.md` — Person 2 work order
- `API_CONTRACT.md` — shared data contract between frontend and backend
- `DAY_PLAN.md` — 3-day execution plan

## Important Rule

Frontend must not wait for backend. Use mock data first, then replace mock data with backend result after integration.

## Flutter Frontend

The Android-first Flutter prototype is committed at the repository root. Its
implementation is organized under `lib/` into models, mock services, screens,
and reusable widgets; Android runner files live under `android/` and widget
tests live under `test/`.

Run the local mock demo with:

```bash
flutter pub get
flutter run
```

The primary demo path is Home → Monitoring → Simulate Detection → Emergency
Alert → Trusted Contact View → History. All detection, location, contact, and
incident behavior is local mock data; the prototype does not contact external
or emergency services.
