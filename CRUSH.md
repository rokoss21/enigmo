# Enigmo Development Guide

## Build Commands
- `make setup` - Install dependencies for both app and server
- `make test` - Run all tests with coverage
- `make lint` - Run static analysis (dart analyze/flutter analyze)
- `make format` - Format all code (dart format)
- `make build-server` - Build server executable
- `make dev-server` - Start server in dev mode
- `make dev-app-ios/android/web` - Run Flutter app

## Test Commands
- `cd enigmo_server && dart test path/to/test.dart` - Run single server test
- `cd enigmo_app && flutter test path/to/test.dart` - Run single app test
- `make test-server` - Run all server tests
- `make test-app` - Run all app tests

## Code Style Guidelines

### Dart/Flutter
- Use `dart format` for consistent formatting (configured in analysis_options.yaml)
- Follow effective_dart lint rules (flutter_lints for app, lints for server)
- Use single quotes for strings
- Private members use underscore prefix: `_privateVariable`
- Classes use PascalCase: `MyClass`
- Variables and functions use camelCase: `myVariable`, `myFunction`
- Constants use UPPER_SNAKE_CASE: `MY_CONSTANT`

### Imports
- Import order: dart:*, package:*, relative imports
- Use show/hide for selective imports
- Group related imports together

### Error Handling
- Use try-catch for async operations
- Log errors with appropriate levels (severe for critical, warning for expected)
- Provide meaningful error messages in API responses
- Use custom exceptions for domain-specific errors

### Architecture
- Server: Clean architecture with services, models, routers
- App: Flutter best practices - widgets, screens, services, models
- Keep business logic separate from UI/presentation
- Use dependency injection where appropriate

## Audio Calls Implementation Plan

### Dependencies
- Add `flutter_webrtc: ^0.9.36` to pubspec.yaml
- Required permissions in AndroidManifest.xml:
  - RECORD_AUDIO
  - MODIFY_AUDIO_SETTINGS
  - BLUETOOTH (optional)
- Required permissions in Info.plist:
  - NSMicrophoneUsageDescription

### Client Architecture
```
lib/
├── services/
│   ├── audio_call_service.dart     # Main WebRTC orchestration
│   ├── call_notification_service.dart # Incoming call handling
│   └── webrtc_signaling_service.dart # Signal exchange with server
├── screens/
│   └── audio_call_screen.dart      # Call UI (dialer/incoming/call)
├── widgets/
│   ├── call_controls.dart          # Mute, speaker, hangup buttons
│   └── call_status_indicator.dart  # Connection status display
└── models/
    └── call.dart                   # Call state model
```

### Server Modifications
- Add WebSocket endpoints for signaling:
  - `/ws/call/initiate` - Start call
  - `/ws/call/accept` - Accept incoming call
  - `/ws/call/offer` - SDP offer exchange
  - `/ws/call/answer` - SDP answer exchange
  - `/ws/call/candidate` - ICE candidate exchange
  - `/ws/call/end` - Terminate call
- Add call state management in memory or database
- Integrate with existing notification system for incoming calls

### Integration Points
- Use existing crypto_engine for E2E encryption of signaling messages
- Leverage notification_service for incoming call alerts
- Maintain key_manager for identity verification during calls
- Extend network_service for WebRTC signaling channel