# SUNO UI Design Reference

This document is the visual source of truth for the `feature/frontend-ui-redesign` branch when the original workflow PDF cannot be attached to Codex Cloud.

## Brand direction

- Product: **SUNO — AI Safety Companion**
- Tagline: **“It listens for danger, not conversations.”**
- Visual identity: compact mobile safety product, not a generic Material demo.
- Primary brand feel: dark navy/black + purple/indigo SUNO identity, with green/orange/red for safety state semantics.
- SUNO mark should resemble the reference: a purple/pink/orange listening/ear/sound-wave symbol. Do not use the current generic shield icon.

## Core mobile screens

### 1. Home

Reference composition:
- dark navy / near-black background
- SUNO listening logo centered prominently
- large `SUNO` title
- tagline below: `It listens for danger, not conversations.`
- compact mobile spacing; avoid oversized empty desktop-like gaps
- strong primary CTA near lower portion: `START MONITORING`
- trusted contacts can remain as a secondary action but must not compete with the main CTA

### 2. Monitoring

Reference composition:
- white / very light background
- large green microphone/listening indicator with a soft glow/ring
- green title: `SUNO is Active`
- subtitle: `Listening privately on this device`
- waveform visualization
- compact sensor/status row instead of large stacked dark cards:
  - Sound — Normal
  - Motion — Stable
  - Connection — Active
- bottom action: `STOP MONITORING`, white/light with red outline or red text
- keep demo functionality such as simulated distress detection, but visually de-emphasize it so it does not dominate the production UI

### 3. Safety Check

Reference composition:
- white / light background
- red/orange warning copy: `Possible emergency detected`
- prompt: `Are you safe?`
- large circular countdown with a prominent number
- green primary button: `I AM SAFE`
- red/orange button: `CAN'T RESPOND`
- centered, urgent, uncluttered layout

### 4. Emergency Alert

Reference composition:
- white / light background
- large red alert/bell visual with strong emergency emphasis
- heading: `Emergency Alert Activated`
- event detail section
- risk score section (critical shown in red)
- location section
- large bottom CTA: `VIEW LOCATION`, red rounded button

### 5. Trusted Contact View

Reference composition:
- white / light background
- person name and message like `[Name] may be in danger`
- critical risk prominently shown
- event detail + timestamp
- location card / map-style preview
- location text in the reference uses a live-location presentation, e.g. `Main Boulevard, Gulberg, Lahore, Pakistan`
- actions:
  - orange: `I AM CHECKING ON THEM`
  - green: `THEY ARE SAFE`
- preserve escalation/status actions already implemented

### 6. History

Reference composition:
- white / light background
- compact app bar
- top filters/tabs: `All`, `Alerts`, `Canceled`
- clean incident list/timeline
- event names, timestamps, status icons
- red/orange for alerts; green for safe/canceled/closed outcomes

## Risk semantics

Use the workflow thresholds consistently:

- **LOW 0–39** → green → keep monitoring
- **MEDIUM 40–69** → orange → ask `Are you safe?`
- **HIGH / CRITICAL 70–100** → red → auto alert immediately

Reference example risk score: **96/100**.

Reference scoring example:
- Distress sound (high confidence): +50
- Strong impact detected: +30
- Phone remains still: +15
- No user response: +20

## System flow to preserve

The UI must continue to support this product flow:

`Home → Monitoring → detection/risk evaluation → Safety Check for medium risk OR Emergency Alert for critical risk → Trusted Contact View → History`

The implementation already has mock services and navigation. Redesign presentation only; preserve the working behavior.

## Visual standards

- Target mobile widths: 360–412 px
- Primary visual review size: 412 × 915
- Secondary review size: 390 × 844
- Horizontal page padding: ~20–24 px
- Card radii: ~16–24 px
- Button radii: ~20–30 px
- Use consistent spacing rhythm: 8 / 12 / 16 / 24 / 32
- Avoid overflow and hard-coded desktop widths
- Prefer `SafeArea`, `Expanded`, `Flexible`, `LayoutBuilder`, and `MediaQuery` where appropriate

## Color semantics

- Home: dark navy / near-black
- SUNO branding: purple / indigo, with pink/orange accents where needed
- Safe / active / normal: green
- Warning / checking: orange
- Critical / emergency: red
- Operational screens (Monitoring, Safety Check, Emergency Alert, Trusted Contact View, History): white / light backgrounds

## Functional constraints

Do **not** change:
- core models
- service contracts
- routes
- mock detection behavior
- incident behavior
- API contract

Do **not** remove tests just to make the redesign pass.

After redesign, run:

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
```

## Final visual acceptance checklist

- Home resembles the reference and uses SUNO branding rather than a generic shield
- Monitoring is white/green and compact
- Safety Check has the countdown warning layout
- Emergency Alert is visibly critical and uses the red alert composition
- Trusted Contact View includes location/map presentation and orange/green actions
- History has filters and a polished incident list
- Branding is consistent across all screens
- Existing functional flow still works
