# Quick Click Match

Fast-paced deck matching for friends and families. Quick Click Match combines online multiplayer (AWS Cognito + WebSockets), hot-seat, and local training modes with customizable decks.

## Table of Contents
1. [Features](#features)
2. [Tech Stack](#tech-stack)
3. [Development Setup](#development-setup)
4. [Environment & Secrets](#environment--secrets)
5. [Testing](#testing)
6. [Release Checklist](#release-checklist)
7. [Privacy & Data Safety](#privacy--data-safety)

## Features
- **Game Modes**: Training, hot-seat, and friend lobbies with invitations.
- **Multiplayer backend**: AWS Cognito authentication and secure WebSocket matchmaking service.
- **Deck management**: Import default decks at first launch, download custom decks, and edit via the web debug tool.
- **Audio & Localization**: Sound cues managed by `SoundService`, localized strings for multiple languages via `LocalizationService`.

## Tech Stack
- Flutter 3.x (Material + custom widgets)
- AWS Cognito (auth) and custom WebSocket backend (matchmaking)
- Flutter Secure Storage / SharedPreferences for persistent data

## Development Setup
1. Install Flutter 3.22.3+ and Dart SDK.
2. Clone the repo and fetch dependencies:
   ```bash
   cd QuickClickMatch/flutter
   flutter pub get
   ```
3. Run the app with dev defines (example):
   ```bash
   flutter run \
     --dart-define=COGNITO_USER_POOL_ID=... \
     --dart-define=COGNITO_CLIENT_ID=... \
     --dart-define=AWS_REGION=us-east-1 \
     --dart-define=BACKEND_ADDRESS=wss://match.steinmetzbnaya.com/ws
   ```

## Environment & Secrets
- Required defines: `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID`, `AWS_REGION`, `BACKEND_ADDRESS`.
- Local release builds can use the `flutter_release.sh` stub (copy + fill with real values).
- Configure GitHub Actions secrets with the same keys for CI.

## Testing
- Run `flutter analyze` and `flutter test`. CI executes these automatically.
- Widget tests cover initial menu rendering; service tests cover config persistence and WebSocket URL logic.

## Release Checklist
1. Bump `pubspec.yaml` version (and Gradle picks it up).
2. Ensure `key.properties` points to your release keystore (see `android/key.properties.sample`).
3. Update environment secrets and run `flutter build appbundle` via CI or `flutter_release.sh`.
4. Download the CI artifact (`quick-click-match-aab`) for QA/Play upload.
5. Update screenshots, store listing copy, and verify links to privacy policy.

## Privacy & Data Safety
- Policy and data declarations live in `docs/privacy_policy.md` and `docs/data_safety.md`.
- Host the policy publicly and link it inside the app (Settings → Privacy) before publishing.
