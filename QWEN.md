# Anongram Project Context for Qwen Code

## Project Overview

This repository contains the **Anongram** secure messaging platform, split into two main components:

1.  **`enigmo_app`**: A Flutter-based mobile client application.
2.  **`enigmo_server`**: (Directory exists, content not yet analyzed) Presumably the backend server.

### Anongram App (`enigmo_app`)

*   **Type**: Mobile Application
*   **Framework**: Flutter (Dart)
*   **Purpose**: Client for the Anongram secure messaging platform. It implements client-side cryptographic identity management and end-to-end encrypted messaging.
*   **Communication**: Uses REST and WebSocket for communication with the `enigmo_server`.
*   **Key Features**:
    *   Ephemeral Identity: Generates a new cryptographic identity and user ID on each app launch.
    *   End-to-End Encryption (E2EE): Uses X25519 for key exchange, ChaCha20-Poly1305 for symmetric encryption, and Ed25519 for message signing.
    *   Offline Messaging: Queues messages locally when a recipient is offline and sends them when the recipient comes online.
    *   Secure Storage: Uses `flutter_secure_storage` to store sensitive information like private keys.

## Project Structure (Analyzed Parts)

```
anongram/
├── enigmo_app/                 # Flutter client application
│   ├── lib/
│   │   ├── main.dart           # Entry point of the application
│   │   ├── models/             # Data models (e.g., Chat, Message)
│   │   ├── screens/            # UI Screens (e.g., ChatListScreen, ChatScreen)
│   │   ├── services/           # Core logic (e.g., NetworkService, CryptoEngine, KeyManager)
│   │   └── widgets/            # Reusable UI components
│   ├── pubspec.yaml            # Project dependencies and metadata
│   └── README.md               # Client-specific README
└── enigmo_server/              # (Structure/contents not yet analyzed)
```

## Key Technologies (Client - `enigmo_app`)

*   **Flutter**: UI Framework.
*   **Dart**: Programming language.
*   **`cryptography`**: Dart package for cryptographic operations (X25519, ChaCha20-Poly1305, Ed25519).
*   **`web_socket_channel`**: For WebSocket communication.
*   **`flutter_secure_storage`**: For securely storing keys.
*   **`pointycastle`**: Lower-level cryptographic primitives (used by `cryptography`).

## Building and Running (Client - `enigmo_app`)

These commands are based on the `enigmo_app/README.md`:

*   **Setup**: `flutter pub get`
*   **Run**: `flutter run`
*   **Test**: `flutter test`
*   **Build (Android)**: `flutter build apk` or `flutter build appbundle`
*   **Build (iOS)**: `flutter build ios` (requires Xcode signing setup)

## Development Conventions (Inferred)

*   **Architecture**: The client follows a structure separating UI (`screens`, `widgets`), data (`models`), and business logic (`services`).
*   **State Management**: Uses Flutter's built-in `StatefulWidget` for managing screen state (as seen in `ChatListScreen`).
*   **Networking**: Centralized in `NetworkService`, handling WebSocket connection, authentication, message sending/receiving, and user discovery.
*   **Cryptography**: Centralized in `CryptoEngine` and `KeyManager` services.
*   **UI**: Uses Flutter's Material Design components (`MaterialApp`, `Scaffold`, `AppBar`, etc.).
*   **Ephemeral Identity**: The client is designed to generate a new identity on each launch, meaning user IDs are not persistent across sessions unless explicitly managed by the user (e.g., by manually copying and sharing their ID each time).
