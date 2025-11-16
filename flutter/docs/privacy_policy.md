# Quick Click Match Privacy Policy

_Last updated: $(date +%Y-%m-%d)_

## 1. Overview
Quick Click Match ("the App") is published by BN Studio. This policy explains what information the App collects, how it is used and shared, and which choices you have. By using the App you agree to this policy. If you disagree, please discontinue use.

## 2. Information We Collect
| Category | Details | Source |
| --- | --- | --- |
| Account identifiers | Display name, Cognito username, email address, Cognito ID token | Provided by you when signing up or signing in via AWS Cognito |
| Gameplay identifiers | Randomly generated user ID, selected deck, lobby status, invites | Generated on device and synced with the multiplayer backend |
| Device data | IP address/domain for the multiplayer server override, general diagnostics | Stored locally in SharedPreferences when you configure the server settings |
| Usage & telemetry | Real-time gameplay events (matchmaking, invite responses, readiness) transmitted over TLS WebSockets | Produced while you interact with the lobby/matchmaking features |

The App does **not** request precise location, contacts, camera, or microphone access.

## 3. How We Use Information
- Authenticate accounts via AWS Cognito and maintain secure sessions.
- Store your preferred server endpoint and display name locally so you do not re-enter them each launch.
- Synchronize multiplayer state (friends, invites, readiness, deck metadata) with the backend via secure WebSockets.
- Troubleshoot performance issues and enforce anti-spam/abuse protections.

## 4. Storage & Security
- Cognito tokens and user IDs are stored in Flutter Secure Storage on Android (encrypted SharedPreferences) and in SharedPreferences on other platforms.
- Multiplayer server overrides and localization settings live in SharedPreferences.
- Network traffic to the backend uses HTTPS/TLS (`wss://match.steinmetzbnaya.com/ws`).
- We limit data collection to what is necessary to provide gameplay and apply least-privilege access on backend services. No payment data is collected.

## 5. Sharing & Third Parties
We share data only with:
- **AWS Cognito** for authentication and password resets.
- **Quick Click Match multiplayer backend (WebSocket service)** for gameplay synchronization.
No personal information is sold or shared with advertisers.

## 6. Children's Privacy
The App targets general audiences aged 13+ and does not knowingly collect information from children under 13. If you believe a child provided data without consent, contact us to delete it.

## 7. Your Choices & Rights
- **Access/Deletion:** Email us (see Section 9) to request access to or deletion of your data.
- **Sign-out:** You can sign out in Settings → Account to clear stored tokens.
- **Data retention:** We keep account data as long as your account is active. Local preferences stay on your device until you uninstall or clear app data.

## 8. Updates to this Policy
We may revise this policy from time to time. Updates will be posted in the repository and inside the app (Settings → Privacy). Continued use after changes indicates acceptance.

## 9. Contact
For privacy questions or requests, contact **support@quickclickmatch.com**.
