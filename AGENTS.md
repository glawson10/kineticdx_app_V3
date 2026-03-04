# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

KineticDx V3 is a multi-tenant, clinic-scoped clinical platform built with:
- **Flutter client** (root `pubspec.yaml`, Dart SDK >=3.3.0 <4.0.0) — web, Android, iOS, macOS, Windows, Linux
- **Firebase Cloud Functions** (`functions/`, Node.js 20, TypeScript)

Architecture rules are defined in `1. ARCHITECTURE.md` and `docs/ARCHITECTURE_V3.md`. See also `docs/CURSOR_HOUSE_RULES.md` for coding conventions.

### Services and commands

| Component | Install deps | Lint / Analyze | Build | Run (dev) |
|---|---|---|---|---|
| Flutter app | `flutter pub get` | `flutter analyze` | `flutter build web --dart-define=FIREBASE_ENV=dev` | `flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0 --dart-define=FIREBASE_ENV=dev` |
| Cloud Functions | `npm install` (in `functions/`) | N/A (TypeScript strict mode) | `npm run build` (in `functions/`) | `npm run serve` (in `functions/`, requires Firebase CLI) |
| Flutter tests | — | — | — | `flutter test` |

### Environment requirements

- **Flutter SDK 3.29.x** installed at `/opt/flutter`, added to `PATH` via `~/.bashrc`.
- **Node.js 20** via nvm, activated in `~/.bashrc` (`nvm use 20`).
- The root `package.json` is a duplicate of `functions/package.json`; the canonical Functions project is at `functions/`.
- Firebase config files: `firebase_options_dev.dart` and `firebase_options_prod.dart` in `lib/`. Default dev project: `kineticdx-v3-dev`.

### Non-obvious caveats

- The Flutter app requires `--dart-define=FIREBASE_ENV=dev` (or `prod`) to select the Firebase project. Without it, defaults to `prod`.
- Cloud Functions compile from `functions/src/` → `functions/lib/` via `tsc`. Always run `npm run build` in `functions/` before deploying or testing.
- There is no Firebase Emulator configuration in `firebase.json`; development runs against the live `kineticdx-v3-dev` project.
- The root-level `package.json` has slightly different dependency versions than `functions/package.json`; always use `functions/` as the canonical npm project.
- Pre-existing compilation errors exist on `main` (broken import in `soap_note_pdf_generator.dart`, missing `BodyRegion` class, deprecated `initialValue` parameter on `DropdownButtonFormField`, and `PathEffect`/`pathEffect` not available). These prevent `flutter build web` and `flutter run` from completing. They must be fixed before the Flutter app can be built or run.
