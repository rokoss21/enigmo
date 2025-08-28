# Enigmo Project Context

## Project Overview

Enigmo is an enterprise-grade secure messaging platform with end-to-end encryption, designed for cross-platform use (iOS, Android, Web). It follows a zero-trust architecture where the server never has access to plaintext messages.

### Key Technologies

- **Frontend/Client**: Flutter (Dart) for mobile and web applications
- **Backend/Server**: Dart server using `shelf` for HTTP/WS
- **Cryptography**: 
  - Ed25519 for digital signatures
  - X25519 for ECDH key exchange
  - ChaCha20-Poly1305 for AEAD encryption
- **Infrastructure**: Docker, Docker Compose
- **Testing**: Built-in unit and integration tests for both client and server

### Architecture

The project is structured as a monorepo with two main components:

1. **enigmo_app**: The Flutter client application
2. **enigmo_server**: The Dart backend server

The client handles all cryptographic operations, key management, and user interface. The server acts as a zero-knowledge message router and user directory.

## Development Workflow

### Prerequisites

- Flutter SDK (stable channel)
- Dart SDK (included with Flutter)
- Development environment (VS Code, Android Studio, or Xcode)
- Platform tools (iOS/Android toolchains)

### Setup

```bash
make setup
```

This command installs all dependencies for both the app and server.

### Running Locally

Start the server:
```bash
make dev-server
```

Start the app:
```bash
# iOS
make dev-app-ios

# Android
make dev-app-android

# Web
make dev-app-web
```

### Testing

Run all tests:
```bash
make test
```

Run server tests only:
```bash
make test-server
```

Run app tests only:
```bash
make test-app
```

### Code Quality

Format code:
```bash
make format
```

Run static analysis:
```bash
make lint
```

### Docker

Start development environment:
```bash
make docker-up
```

Stop development environment:
```bash
make docker-down
```

### Building

Build server executable:
```bash
make build-server
```

Build app for different platforms:
```bash
# Android APK
make build-app-android

# Android App Bundle
make build-app-android-bundle

# iOS
make build-app-ios

# Web
make build-app-web

# All platforms
make build-all
```

## Key Components

### Client (enigmo_app)

- **Crypto Engine**: `lib/services/crypto_engine.dart` - Handles all cryptographic operations (E2EE, signing, key derivation)
- **Key Manager**: `lib/services/key_manager.dart` - Manages secure key storage and retrieval
- **Network Service**: `lib/services/network_service.dart` - Handles WebSocket and REST API communication

### Server (enigmo_server)

- **Main Entry Point**: `bin/anongram_server.dart` - Server startup and routing
- **WebSocket Handler**: `lib/services/websocket_handler.dart` - Handles real-time communication and call signaling
- **User Manager**: `lib/services/user_manager.dart` - Manages user directory and connections
- **Message Manager**: `lib/services/message_manager.dart` - Handles message routing logic

## Security Model

- Zero-knowledge server architecture
- End-to-end encryption with perfect forward secrecy
- Message authenticity via digital signatures
- Replay protection with cryptographic nonces
- Secure local key storage

## Roadmap

The project has a detailed roadmap focusing on:
1. Foundation (completed)
2. Resilience (offline messaging, attachments, PWA)
3. Enterprise features (PFS, multi-device, groups)
4. Rich media (voice/video calls)
5. Advanced security (post-quantum crypto)