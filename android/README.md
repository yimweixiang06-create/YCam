# YCam Android — native camera foundation (preview)

This directory contains a **real, installable Android application** written in
Java with Android CameraX. It is **not** the iOS SwiftUI/AVFoundation application
converted into an APK, and it does not claim iOS feature or color parity.

## Implemented now

- Live CameraX viewfinder with touch-to-focus and pinch-to-zoom
- High-resolution JPEG capture saved via Android MediaStore to Pictures/YCam
- MP4 video recording saved to Movies/YCam (microphone optional)
- Photo/video switching, front/back camera, flash/torch, open last capture
- Native per-app English/Simplified Chinese selection (Android 13+)
- Permission handling, camera pipeline fallback, basic Java unit tests
- CI: Android lint, unit tests, APK archive integrity, Android emulator install/launch

## Not yet implemented — do not pretend these exist

- 28 YCam iOS Photographic Styles and their LUTs
- 10 Apple-style live-preview photo filters
- iOS 27 matching controls, native Live Photos and iOS portrait lighting
- YCam's custom dotted palette color processing and original artwork
- Full video effects, filter accuracy measurements, comprehensive real-device QA

**Do not use a placeholder filter, fake preview, or an empty button to mark one
of these features as complete.** Android and iOS use different native camera
frameworks and need separate per-device image processing and testing.

## Build

Requirements: Android SDK 35, Java 17, Gradle 8.11.1, Android 10+ device.

```sh
cd android
gradle :app:lintDebug :app:testDebugUnitTest :app:assembleDebug
```

Install `app/build/outputs/apk/debug/app-debug.apk` on an Android device.
The APK is **debug-signed** for QA, not a Play Store production package.

## CI and release policy

The repository's Android and iOS GitHub Actions build from the same Git commit
when camera or Android sources change. iOS continues to create its *unsigned*
IPA; Android builds a debug APK artifact. The Android artifact is not promoted
to an official cross-platform release unless full feature and device validation
is completed. Compiling or launching on an emulator is not a zero-bug guarantee.

Real-device checklist: camera and microphone permission; rear/front camera;
photo saves/open; video with and without mic; interrupted recording; low light;
flash availability; rotate; pinch zoom; Android 10 and Android 15; system and
per-app languages; performance and battery; empty storage and revoked permissions.
