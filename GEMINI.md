# GEMINI.md - Enigmo Project

This file provides a comprehensive overview of the Enigmo project, its architecture, and development workflows.

## Project Overview

Enigmo is an enterprise-grade secure messaging platform with a strong focus on privacy and end-to-end encryption (E2EE). It follows a zero-knowledge architecture, ensuring that the server never has access to plaintext message content.

The project is structured as a monorepo containing two main components:

*   **`enigmo_app`**: A cross-platform mobile and web client built with Flutter. It is responsible for managing user keys, handling all cryptographic operations (encryption/decryption, digital signatures), and providing the user interface.
*   **`enigmo_server`**: A lightweight, high-performance server built with Dart. It manages user public keys, routes encrypted messages between clients using WebSockets, and provides health and statistics endpoints.

### Key Technologies

*   **Frontend (Client)**: Flutter, Dart
*   **Backend (Server)**: Dart, Shelf, WebSockets
*   **Cryptography**:
    *   **Digital Signatures**: Ed25519
    *   **Key Exchange**: X25519 (ECDH)
    *   **Authenticated Encryption**: AEAD (ChaCha20-Poly1305)

## Building and Running

The project includes a `Makefile` that simplifies common development tasks.

### Prerequisites

*   Flutter SDK (stable channel)
*   Dart SDK (included with Flutter)

### Setup

To install all dependencies for both the client and server, run:

```bash
make setup
```

### Development

**1. Start the Server:**

```bash
make dev-server
```

The server will start on `http://localhost:8081` by default.

*   **WebSocket Endpoint**: `ws://localhost:8081/ws`
*   **Health Check**: `http://localhost:8081/api/health`
*   **Statistics**: `http://localhost:8081/api/stats`

**2. Start the Flutter App:**

You can run the app on iOS, Android, or Web:

```bash
# iOS
make dev-app-ios

# Android
make dev-app-android

# Web
make dev-app-web
```

### Testing

To run all unit and integration tests for both the client and server:

```bash
make test
```

You can also run tests for each component individually:

```bash
# Server tests
make test-server

# App tests
make test-app
```

### Production Builds

The `Makefile` also provides commands for creating production builds:

```bash
# Build the server executable
make build-server

# Build the Android app (APK)
make build-app-android

# Build the Android App Bundle
make build-app-android-bundle

# Build the iOS app
make build-app-ios

# Build the web app
make build-app-web

# Build all components
make build-all
```

## Development Conventions

### Code Style

The project uses the standard Dart and Flutter formatting guidelines. To format all code, run:

```bash
make format
```

### Static Analysis

Static analysis is used to identify potential issues and enforce coding standards. To run the analyzer on both the client and server code, use:

```bash
make lint
```

### Key Files and Directories

*   `enigmo_app/lib/main.dart`: The entry point for the Flutter application.
*   `enigmo_app/lib/services/crypto_engine.dart`: Contains the core client-side cryptographic logic.
*   `enigmo_app/lib/services/network_service.dart`: Manages WebSocket and REST API communication.
*   `enigmo_server/bin/anongram_server.dart`: The entry point for the Dart server.
*   `enigmo_server/lib/services/websocket_handler.dart`: Handles WebSocket connections and message routing.
*   `enigmo_server/lib/services/user_manager.dart`: Manages user sessions and public keys.
*   `Makefile`: Contains all the build, run, and test commands.
*   `README.md`: The main project README with detailed information about the architecture and security model.
