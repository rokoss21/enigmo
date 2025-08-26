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