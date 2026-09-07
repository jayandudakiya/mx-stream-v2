# OrcaBox App v2 — Build & Configuration Guide

This guide details everything needed to set up, configure, build, and release **OrcaBox App v2** across all supported platforms (Android, Android TV, Windows, and iOS).

---

## 📑 Table of Contents

1. [Prerequisites & Environment Setup](#-1-prerequisites--environment-setup)
2. [API Keys & Environment Variables (Dart Defines)](#-2-api-keys--environment-variables-dart-defines)
   - [TMDB API Key Configuration](#tmdb-api-key-configuration-tmdb_api_key)
   - [v3 API Key vs v4 Bearer Token](#v3-api-key-vs-v4-bearer-token-critical)
   - [Other Configurable Dart Defines](#other-configurable-dart-defines)
3. [Supplying API Keys (3 Methods)](#-3-supplying-api-keys-3-methods)
   - [Method 1: Direct Command-Line Define](#method-1-direct-command-line-define)
   - [Method 2: Gitignored JSON File (Recommended)](#method-2-gitignored-json-file-recommended-for-local-dev)
   - [Method 3: VS Code Debug Configuration](#method-3-vs-code-debug-configuration)
4. [Running the App in Development](#-4-running-the-app-in-development)
5. [Building Release Binaries](#-5-building-release-binaries)
   - [Android (APK & Split-per-ABI)](#android-builds)
   - [Android App Bundle (.aab)](#google-play-app-bundle-aab)
   - [Windows Desktop](#windows-desktop)
6. [Version Management & Releases](#-6-version-management--releases)
7. [Clean Builds & Cache Management](#-7-clean-builds--cache-management)
8. [Code Analysis & Verification](#-8-code-analysis--verification)
9. [Architecture Notes & FAQ](#-9-architecture-notes--faq)

---

## ⚡ 1. Prerequisites & Environment Setup

OrcaBox v2 is built with Flutter and uses **FVM (Flutter Version Management)** to pin the exact Flutter SDK version.

### Requirements:
- **Flutter SDK**: `3.38.5` (managed via `.fvmrc`)
- **FVM**: Recommended (`dart pub global activate fvm`)
- **JDK**: Java 17+ (for Android builds)
- **Android SDK**: Build tools 34+, Android SDK API 34+
- **Visual Studio 2022** (with C++ Desktop development workload for Windows builds)

### First-time Setup:
```powershell
# Navigate to the project directory
cd mx-stream-app-v2

# Install the pinned Flutter SDK via FVM
fvm install

# Fetch dependencies
fvm flutter pub get
```

> [!NOTE]
> If you are not using FVM, replace `fvm flutter` with `flutter` in all commands below. Make sure your active Flutter SDK matches version `3.38.5`.

---

## 🔑 2. API Keys & Environment Variables (Dart Defines)

The project uses Flutter's compile-time environment variables (`String.fromEnvironment`) with safe embedded defaults. This allows developers to supply custom, staging, or production keys without ever modifying tracked source code or risking accidental commits.

### TMDB API Key Configuration (`TMDB_API_KEY`)

The Movie Database (TMDB) API powers:
- **Movie/TV Search Autocomplete**
- **YouTube Trailers** ([`TrailerService`](lib/core/trailer/trailer_service.dart))
- **Cast, Crew, and Metadata Enrichment** ([`NativeMetadataBridge`](lib/core/provider/native/native_metadata_bridge.dart))

#### Single Source of Truth
The key is declared in [`lib/core/metadata/tmdb.dart`](lib/core/metadata/tmdb.dart):
```dart
static const String apiKey = String.fromEnvironment(
  'TMDB_API_KEY',
  defaultValue: 'fab792d6c5936a7332045ca4565c7353',
);
```

#### How it works:
- Every TMDB request goes through a unified Dio interceptor wired in [`lib/core/di/injector.dart:365`](lib/core/di/injector.dart).
- The interceptor intercepts requests to `api.themoviedb.org` and attaches `api_key: Tmdb.apiKey` as a query parameter.
- **Graceful degradation:** If no define is set, it safely uses the built-in fallback key. If the key is empty or invalid, the app gracefully falls back to each provider's native metadata without breaking playback or crashing.

> [!IMPORTANT]
> **v3 API Key vs v4 Bearer Token (CRITICAL)**
> You **MUST** use a **TMDB v3 API Key** (a 32-character hexadecimal string), found in your TMDB Account Settings under **API → API Key (v3 auth)**.
> 
> Do **NOT** use a TMDB v4 Read Access Token (JWT bearer token). The app passes the key as an `api_key` query parameter, which TMDB v4 tokens do not support.

> [!NOTE]
> **Build-time vs Runtime:**
> `TMDB_API_KEY` is a build-time compile constant (`const`), not a user-facing settings preference. If dynamic runtime key configuration in Settings is required in the future, the interceptor would read from persistent storage (e.g., `AppPrefs`) rather than a compile constant.

### Other Configurable Dart Defines

| Environment Variable | Location | Purpose | Default |
|---|---|---|---|
| `TMDB_API_KEY` | [`lib/core/metadata/tmdb.dart`](lib/core/metadata/tmdb.dart) | TMDB API v3 key for search/trailers/enrichment | Embedded public fallback |
| `SUPABASE_URL` | [`lib/core/environment.dart`](lib/core/environment.dart) | Supabase project endpoint | OrcaBox public endpoint |
| `SUPABASE_ANON_KEY` | [`lib/core/environment.dart`](lib/core/environment.dart) | Supabase client anon public key | Embedded public anon key |
| `SUBDL_API_KEY` | [`lib/core/playback/subtitle_download_service.dart`](lib/core/playback/subtitle_download_service.dart) | SubDL API key for subtitle downloads | `''` (empty) |
| `EXO_SPIKE` | [`lib/features/player/tv_exo_spike_screen.dart`](lib/features/player/tv_exo_spike_screen.dart) | Enable experimental ExoPlayer spike | `false` |

---

## 🛠️ 3. Supplying API Keys (3 Methods)

### Method 1: Direct Command-Line Define

Pass the define flag directly into `run` or `build`:

```powershell
# Run with custom key
fvm flutter run --dart-define=TMDB_API_KEY=your_32_char_hex_key

# Build release APK with custom key
fvm flutter build apk --release --dart-define=TMDB_API_KEY=your_32_char_hex_key
```

---

### Method 2: Gitignored JSON File (Recommended for Local Dev)

Instead of passing the key in every command or keeping it in terminal history, store it in an environment JSON file.

#### Step 1: Create `tmdb.env.json` in the `mx-stream-app-v2/` root directory:
```json
{
  "TMDB_API_KEY": "your_32_char_hex_key"
}
```

> [!TIP]
> You can also include other defines in this file, such as:
> ```json
> {
>   "TMDB_API_KEY": "your_32_char_hex_key",
>   "SUBDL_API_KEY": "your_subdl_key"
> }
> ```

#### Step 2: Ensure the file is ignored by Git
The project's `.gitignore` already contains:
```gitignore
secrets.json
*.env.json
tmdb.env.json
```
Your keys will **never** be committed to version control.

#### Step 3: Run or build using `--dart-define-from-file`:
```powershell
# Run using the JSON file
fvm flutter run --dart-define-from-file=tmdb.env.json

# Build release APK using the JSON file
fvm flutter build apk --release --dart-define-from-file=tmdb.env.json
```

---

### Method 3: VS Code Debug Configuration

To run and debug directly inside VS Code with your custom TMDB key:

Edit [`.vscode/launch.json`](.vscode/launch.json) and add `toolArgs` to your desired configuration:

#### Option A (Using the JSON file):
```json
{
  "name": "OrcaBox (debug with TMDB)",
  "request": "launch",
  "type": "dart",
  "toolArgs": [
    "--dart-define-from-file=tmdb.env.json"
  ]
}
```

#### Option B (Direct argument):
```json
{
  "name": "OrcaBox (debug · fast arm64)",
  "request": "launch",
  "type": "dart",
  "args": ["--target-platform", "android-arm64"],
  "toolArgs": [
    "--dart-define=TMDB_API_KEY=your_32_char_hex_key"
  ]
}
```

---

## 📱 4. Running the App in Development

Select your target device or emulator and run:

```powershell
# Auto-detect connected device
fvm flutter run --dart-define-from-file=tmdb.env.json

# Target specific Android phone/emulator
fvm flutter run -d <device_id> --dart-define-from-file=tmdb.env.json

# Run on Windows Desktop
fvm flutter run -d windows --dart-define-from-file=tmdb.env.json
```

---

## 📦 5. Building Release Binaries

### Android Builds

#### Option A: Split-per-ABI APKs (Recommended)
Produces separate, highly-optimized APKs for each architecture (~35–50 MB each instead of ~100+ MB universal):
```powershell
fvm flutter build apk --split-per-abi --release --dart-define-from-file=tmdb.env.json
```
**Output artifacts:**
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (For 99% modern phones & TV devices)
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` (For older 32-bit devices)
- `build/app/outputs/flutter-apk/app-x86_64-release.apk` (For x86_64 emulators/devices)

#### Option B: Fat Universal APK
Produces a single APK compatible with all architectures:
```powershell
fvm flutter build apk --release --dart-define-from-file=tmdb.env.json
```
**Output artifact:**
- `build/app/outputs/flutter-apk/app-release.apk`

#### Google Play App Bundle (.aab)
Required if publishing to the Google Play Store:
```powershell
fvm flutter build appbundle --release --dart-define-from-file=tmdb.env.json
```
**Output artifact:**
- `build/app/outputs/bundle/release/app-release.aab`

---

### Windows Desktop

Build release executable for 64-bit Windows:
```powershell
fvm flutter build windows --release --dart-define-from-file=tmdb.env.json
```
**Output folder:**
- `build/windows/x64/runner/Release/`

---

## 🔢 6. Version Management & Releases

App versioning is defined in [`pubspec.yaml`](pubspec.yaml):

```yaml
version: 2.0.0+1
```

### Version Format: `X.Y.Z+B`
- **`X.Y.Z` (Version Name)**: Displayed in the UI and Settings (e.g. `2.0.0`).
  - **Major (`X`)**: Architectural changes / major redesigns.
  - **Minor (`Y`)**: New features, integrations, or provider capabilities.
  - **Patch (`Z`)**: Bug fixes and optimizations.
- **`+B` (Version Code / Build Number)**: Internal Android build number (integer).

> [!CAUTION]
> **CRITICAL ANDROID UPDATE RULE:**
> You **MUST** increment the build number after `+` (e.g., `+1` → `+2` → `+3`) for every new release.
> Android and the in-app auto-updater reject updates if the new APK does not have a strictly higher version code than the installed version.

---

## 🧹 7. Clean Builds & Cache Management

If you encounter unexpected Gradle errors, cached asset mismatches, or build failures after switching branches:

### Standard Clean:
```powershell
fvm flutter clean
fvm flutter pub get
```

### Deep Clean (PowerShell):
```powershell
if (Test-Path build) { Remove-Item -Recurse -Force build }
if (Test-Path .dart_tool) { Remove-Item -Recurse -Force .dart_tool }
if (Test-Path android/.gradle) { Remove-Item -Recurse -Force android/.gradle }
fvm flutter clean
fvm flutter pub get
```

---

## 🧪 8. Code Analysis & Verification

Before submitting code or releasing a build, ensure code quality and integrity:

### Run Dart Analyzer:
```powershell
fvm flutter analyze
```

### Run Automated Unit & Widget Tests:
```powershell
fvm flutter test
```

---

## 🧠 9. Architecture Notes & FAQ

### Where did `kTmdbApiKey` in `app_config.dart` go?
- Previously, a dead constant `kTmdbApiKey` was declared in `lib/core/app_config.dart` that defaulted to empty and was never used by the networking layer.
- Having two constants for the same key created confusion. The dead constant was removed, and [`lib/core/metadata/tmdb.dart`](lib/core/metadata/tmdb.dart) is now the single source of truth.

### How are TMDB rate limits handled?
- TMDB applies rate limits **per IP address**, not per API key.
- A single shared key cleanly scales across all users of the app.
- If TMDB rate limiting (HTTP 429) occurs, requests degrade smoothly without breaking the core media player.

### What if I get a `401 Unauthorized` error when loading trailers or metadata?
- Check that your key is a valid **TMDB v3 API Key** (32 hex characters).
- Make sure you didn't accidentally copy a **v4 Bearer Token** (which starts with `eyJ...` and is much longer).
- Check that your define syntax is correct: `--dart-define=TMDB_API_KEY=<key>` (no quotes or extra whitespace).
