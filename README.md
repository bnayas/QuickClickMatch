# QuickClickMatch

Fast-paced educational deck matching built with Flutter and a lightweight Node.js/WebSocket backend. This repository hosts everything needed to build the mobile clients, generate decks, and ship the multiplayer backend/Lambda helper.

## Repository layout
- `flutter/` – the Flutter application (Android, iOS, desktop, and web targets). See `flutter/README.md` for full setup instructions.
- `backend/` – Node.js matchmaking/WebSocket service plus its `package.json` and lock files.
- `lambda-deploy/` & `lambda-deploy.zip` – infrastructure helpers for provisioning and deploying AWS Lambdas used by the backend.
- `scripts/` – Python utilities for generating decks, isolating card symbols, and asset preparation.
- `assets/` – reference decks, textures, and downloadable bundles shared across platforms.
- `docs/` & `flutter/docs/` – privacy/data safety docs, release review notes, and supporting material.

## Getting started
### 1. Flutter client
1. Install Flutter 3.22.3+ and Dart SDK.
2. From the repo root run:
   ```bash
   cd flutter
   flutter pub get
   ```
3. Provide the required defines when running or building:
   ```bash
   flutter run      --dart-define=COGNITO_USER_POOL_ID=...      --dart-define=COGNITO_CLIENT_ID=...      --dart-define=AWS_REGION=us-east-1      --dart-define=BACKEND_ADDRESS=wss://your-backend/ws
   ```
4. Documentation for release prep, privacy, and assets lives under `flutter/docs/`.

### 2. Backend service
1. Install Node.js 18+ (or use pnpm).
2. Configure environment in `backend/.env` (Cognito pool, WebSocket endpoint, etc.).
3. Install dependencies and start the server:
   ```bash
   cd backend
   npm install
   npm start
   ```
   or use `pnpm install && pnpm start` when preferred.

### 3. Asset/scripts workflow
- Python utilities inside `scripts/` generate sample decks (`make_letter_deck.py`), isolate card symbols, and build manifest files.
- Shared decks/textures live in the top-level `assets/` folder so both the client and content pipeline use a single source of truth.

## CI & release automation
GitHub Actions (see `.github/workflows/ci.yml`) run Flutter analyze/tests, enforce `flutter/pubspec.yaml` version bumps, and build/upload an Android App Bundle artifact. Populate the repository secrets `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID`, `AWS_REGION`, and `BACKEND_ADDRESS` before enabling the workflow.

## Additional documentation
- `flutter/README.md` – detailed Flutter app overview, tech stack, and release checklist.
- `flutter/docs/` – privacy policy, data-safety form, and release review.
- `docs/` – extra publisher collateral or policy copies (add as needed).
