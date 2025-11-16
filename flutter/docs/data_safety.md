# Quick Click Match – Data Safety Summary

Use this document when filling the Google Play Data Safety questionnaire.

## 1. Data Collection Matrix
| Data Type | Collected? | Shared? | Purpose | Notes |
| --- | --- | --- | --- | --- |
| Name / Display name | Yes | With multiplayer backend only | Account management, matchmaking | Stored in secure storage/SharedPreferences and synced via WebSockets |
| Email address | Yes | With AWS Cognito | Account creation, sign-in, recovery | Required for login; not exposed to other players |
| User IDs / tokens | Yes | AWS Cognito & backend | Authentication, fraud prevention | Cognito ID token, anonymous device ID |
| Gameplay data (deck, invites, match events) | Yes | Multiplayer backend | Core functionality | Real-time events sent over TLS WebSockets |
| Device identifiers (server IP override) | Yes (optional) | No | Debugging/custom endpoints | Stored locally only |
| Diagnostics / crash logs | No | — | — | Crashlytics not integrated yet |
| Financial data | No | — | — | App is free, no payments |
| Location, Contacts, Photos/Media | No | — | — | Features do not request these permissions |

## 2. Data Handling Declarations
- **Collection:** Required to operate multiplayer and authentication features.
- **Sharing:** Data is shared only with AWS Cognito and the Quick Click Match backend under BN Studio control.
- **Encryption:** All data in transit uses HTTPS/TLS. Sensitive tokens use encrypted storage on supported platforms.
- **Deletion:** Users can sign out to clear local data and request account deletion via support@quickclickmatch.com.
- **Child safety:** Targeted to ages 13+; no special child data collection.

## 3. User Controls & Disclosures
- Provide an in-app link (Settings → Privacy) to the [privacy policy](privacy_policy.md).
- Display a short disclosure before multiplayer sign-in outlining that account data is stored with AWS Cognito and gameplay events are transmitted to our secure servers.
- Offer contact instructions for deletion/appeals.

Keep this document updated when features change or new analytics are added.
