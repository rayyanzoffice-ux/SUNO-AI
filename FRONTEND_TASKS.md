# Frontend Tasks - Person 1

## Day 1

| Order | Task |
|---:|---|
| 1 | Pull latest repo |
| 2 | Create frontend branch |
| 3 | Create app folder/project |
| 4 | Create folder structure |
| 5 | Create app theme |
| 6 | Create route/navigation setup |
| 7 | Create reusable status card widget |
| 8 | Create reusable action button widget |
| 9 | Create Home screen |
| 10 | Create Monitoring screen |
| 11 | Create Safety Check screen |
| 12 | Create Emergency Alert screen |
| 13 | Create Trusted Contact View screen |
| 14 | Create History screen |
| 15 | Add mock data file |
| 16 | Connect full mock demo flow |
| 17 | Push frontend branch |

## Day 2

| Order | Task |
|---:|---|
| 1 | Pull backend updates |
| 2 | Match UI with DetectionResult model |
| 3 | Replace mock risk score with backend result |
| 4 | Replace mock event type with backend result |
| 5 | Connect LOW / MEDIUM / HIGH UI states |
| 6 | Connect Safety Check trigger |
| 7 | Connect I AM SAFE action |
| 8 | Connect CAN'T RESPOND action |
| 9 | Connect Emergency Alert data |
| 10 | Connect Trusted Contact data |
| 11 | Connect History data |
| 12 | Push integration changes |

## Day 3

| Order | Task |
|---:|---|
| 1 | Fix UI bugs |
| 2 | Fix navigation bugs |
| 3 | Improve spacing and responsive layout |
| 4 | Add simple monitoring animation |
| 5 | Add countdown visual polish |
| 6 | Polish emergency screen |
| 7 | Polish trusted-contact screen |
| 8 | Test on Android phone |
| 9 | Record/demo full flow |
| 10 | Build final APK |

## Frontend Must Not Wait For Backend

Use this mock object until backend is ready:

```json
{
  "eventType": "Distress Sound + Impact",
  "confidence": 0.96,
  "impactDetected": true,
  "stillnessDetected": true,
  "riskScore": 96,
  "riskLevel": "critical",
  "locationText": "Lahore, Pakistan",
  "status": "alert_triggered"
}
```
