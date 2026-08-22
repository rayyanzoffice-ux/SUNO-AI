# Backend / Logic Tasks - Person 2

## Day 1

| Order | Task |
|---:|---|
| 1 | Pull latest repo |
| 2 | Create backend branch |
| 3 | Create backend / logic folder structure |
| 4 | Create DetectionResult model |
| 5 | Create RiskLevel enum |
| 6 | Create Incident model |
| 7 | Create TrustedContact model |
| 8 | Create mock detection service |
| 9 | Create RiskEngine |
| 10 | Add LOW 0-39 logic |
| 11 | Add MEDIUM 40-69 logic |
| 12 | Add HIGH / CRITICAL 70-100 logic |
| 13 | Create safety-check service |
| 14 | Create emergency incident service |
| 15 | Create in-memory history service |
| 16 | Push backend branch |

## Day 2

| Order | Task |
|---:|---|
| 1 | Pull frontend updates |
| 2 | Connect DetectionResult to frontend |
| 3 | Connect risk score to frontend |
| 4 | Connect safety-check trigger |
| 5 | Connect no-response emergency trigger |
| 6 | Connect I AM SAFE cancellation |
| 7 | Connect incident creation |
| 8 | Connect trusted-contact alert data |
| 9 | Connect trusted-contact response status |
| 10 | Connect history retrieval |
| 11 | Push integration changes |

## Day 3

| Order | Task |
|---:|---|
| 1 | Fix integration bugs |
| 2 | Replace some mock logic with real sensor data if possible |
| 3 | Add location capture if possible |
| 4 | Add local storage if possible |
| 5 | Test LOW flow |
| 6 | Test MEDIUM flow |
| 7 | Test CRITICAL flow |
| 8 | Test full demo flow |
| 9 | Prepare fallback mock mode |
| 10 | Final cleanup |

## Backend Priority

The backend must first return a working DetectionResult. Real AI can be added later only if time remains.

```json
{
  "eventType": "Distress Sound + Impact",
  "confidence": 0.96,
  "impactDetected": true,
  "stillnessDetected": true,
  "riskScore": 96,
  "riskLevel": "critical",
  "status": "alert_triggered"
}
```
