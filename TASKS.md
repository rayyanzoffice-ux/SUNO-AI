# SUNO-AI Task Division

## Work Order

| Order | Frontend - Person 1 | Backend / Logic - Person 2 |
|---:|---|---|
| 1 | Create frontend app structure | Create backend / logic structure |
| 2 | Create theme and navigation | Create shared models |
| 3 | Create Home screen | Create mock DetectionResult provider |
| 4 | Create Monitoring screen | Create risk level enum |
| 5 | Add Start Monitoring button | Create RiskEngine |
| 6 | Add Simulate Detection button | Create fake detection event |
| 7 | Create Safety Check screen | Create safety-check trigger logic |
| 8 | Add 10-second countdown UI | Create countdown state logic |
| 9 | Add I AM SAFE action | Handle safe user response |
| 10 | Add CAN'T RESPOND action | Handle no-response / emergency trigger |
| 11 | Create Emergency Alert screen | Create incident model |
| 12 | Show risk score and event type | Create emergency incident service |
| 13 | Create Trusted Contact View screen | Create trusted contact model |
| 14 | Add contact action buttons | Handle trusted-contact response status |
| 15 | Create History screen | Create incident history storage |
| 16 | Connect screens with mock data | Expose data to frontend |
| 17 | Replace mock data with backend result | Connect detection result to frontend |
| 18 | Polish UI for demo | Fix backend integration issues |
| 19 | Test full user flow | Test full backend flow |
| 20 | Build demo APK | Final integration and demo test |

## Final Demo Flow

Home → Monitoring → Simulate Detection → Safety Check → Emergency Alert → Trusted Contact View → History

## Must Finish First

1. Home screen
2. Monitoring screen
3. Safety Check screen
4. Emergency Alert screen
5. Mock DetectionResult
6. RiskEngine
7. Full mock flow

## Do Later Only If Time Remains

1. Login/signup
2. Real maps
3. Real push notification
4. Real AI sound model
5. Advanced settings
6. Live tracking
7. SMS/call fallback
