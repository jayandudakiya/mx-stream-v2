# MX-Stream Quick Build Reference

## Smallest Release APK Build (with `.env`)

To produce the smallest possible release APKs (~35–45 MB) configured with compile-time environment variables:

```powershell
# 1. Ultra-Compact Split-per-ABI APKs (Recommended)
fvm flutter build apk --split-per-abi --release --obfuscate --split-debug-info=build/app/outputs/symbols --dart-define-from-file=.env

# 2. Modern 64-bit Phones & Android TVs only (arm64-v8a)
fvm flutter build apk --target-platform android-arm64 --release --obfuscate --split-debug-info=build/app/outputs/symbols --dart-define-from-file=.env

# 3. Without FVM
flutter build apk --split-per-abi --release --obfuscate --split-debug-info=build/app/outputs/symbols --dart-define-from-file=.env
```

### Output Artifacts
- **arm64-v8a (99% of modern phones & TV devices)**:  
  `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- **armeabi-v7a (Older 32-bit devices)**:  
  `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- **x86_64 (Emulators/x86 devices)**:  
  `build/app/outputs/flutter-apk/app-x86_64-release.apk`

---

For the full multi-platform guide (iOS, Android, Windows, and signing), see [BUILD_GUIDE.md](BUILD_GUIDE.md).
