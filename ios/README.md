# ios

## Overview
The `ios` component package encompasses the native iOS application wrapper, Xcode build configurations, application delegate lifecycle coordinators, and asset catalogs for deploying the Flutter application to iOS and iPadOS. It wires the Flutter engine lifecycle, registers generated Flutter plugins through implicit engine bridging, coordinates UIWindowScene multi-window delegates, and specifies app security/privacy declarations such as photo library access for administrative media uploads.

## Interface
- **Native Lifecycle Delegates:**
  - `[ios/Runner/AppDelegate.swift:AppDelegate]`: Application delegate subclassing `FlutterAppDelegate` and implementing `FlutterImplicitEngineDelegate`:
    - `[ios/Runner/AppDelegate.swift:application(_:didFinishLaunchingWithOptions:)]`: Standard iOS app launch entry point passing control to Flutter's superclass.
    - `[ios/Runner/AppDelegate.swift:didInitializeImplicitFlutterEngine]`: Registers Flutter plugins with the engine using `GeneratedPluginRegistrant.register(with:)`.
  - `[ios/Runner/SceneDelegate.swift:SceneDelegate]`: Window scene delegate subclassing `FlutterSceneDelegate` managing multi-window / scene lifecycles on iOS 13+.
- **Configuration & Assets:**
  - `[ios/Runner/Info.plist]`: Information property list declaring bundle identification, launch storyboard (`LaunchScreen`), device orientations, scene manifests, and privacy permission rationale (`NSPhotoLibraryUsageDescription`).
  - `[ios/Runner/Assets.xcassets]`: Asset catalog containing app icon sets (`AppIcon.appiconset`) and launch screen images (`LaunchImage.imageset`).
  - `[ios/Runner.xcodeproj]`: Xcode project defining compilation targets, build configurations (`Debug.xcconfig`, `Release.xcconfig`, `Generated.xcconfig`), and scheme definitions.
- **Subdirectories & Boundaries:**
  - `./Flutter`: Generated xcconfig files and Flutter framework build environment helpers.
  - `./Runner`: Swift source files, storyboard layouts, and asset catalogs.
  - `./Runner.xcodeproj`: Xcode project container and configuration settings.
  - `./Runner.xcworkspace`: Xcode workspace combining the project and dependency targets.
  - `./RunnerTests`: Unit testing harness for iOS runner targets (`RunnerTests.swift`).

## Invariants
- `[ios/Runner/AppDelegate.swift:didInitializeImplicitFlutterEngine]`: Plugin registration must be executed via `GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)` inside `didInitializeImplicitFlutterEngine`.
- `[ios/Runner/Info.plist]`: Privacy descriptions (`NSPhotoLibraryUsageDescription`) must clearly declare administrative use for priest, saint, activity, and announcement card photos to prevent App Store rejection.
- `[ios/Runner/Info.plist:UIApplicationSceneManifest]`: Scene configurations must link `SceneDelegate` as the `UISceneDelegateClassName` under `UIWindowSceneSessionRoleApplication`.

## Side Effects
- Initializes the iOS Flutter runtime engine.
- Requests access to the iOS photo library when an admin selects an image.
- Manages iOS UIWindow and status bar appearance during orientation changes.

## Verification
- Run: `flutter build ios --no-codesign`
