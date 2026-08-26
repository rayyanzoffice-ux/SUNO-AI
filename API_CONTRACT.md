# API / Data Contract

This file defines the shared contract between frontend and backend.

## DetectionResult

```json
{
  "eventType": "Distress Sound + Impact",
  "confidence": 0.93,
  "impactDetected": true,
  "stillnessDetected": true,
  "riskScore": 95,
  "riskLevel": "critical",
  "locationText": "Lahore, Pakistan",
  "latitude": 31.5204,
  "longitude": 74.3587,
  "status": "alert_triggered"
}
```

## Risk Levels

| Risk Score | Risk Level | Action |
|---:|---|---|
| 0-39 | low | Keep monitoring |
| 40-69 | medium | Show Safety Check |
| 70-100 | critical | Trigger Emergency Alert |

## Incident Status Values

```text
detected
safety_check
cancelled_by_user
alert_triggered
contact_notified
contact_checking
resolved
```

## Trusted Contact Response Values

```text
they_are_safe
i_am_checking
unable_to_contact
```

## Frontend Rule

Frontend receives DetectionResult and decides which screen to show.

## Backend Rule

Backend / logic layer calculates DetectionResult and does not directly control UI screens.
