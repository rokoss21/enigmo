# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Enigmo is an enterprise-grade secure messaging platform built with Flutter (client) and Dart (server). It implements end-to-end encryption using Ed25519 digital signatures and X25519 ECDH key exchange with ChaCha20-Poly1305 AEAD encryption. The architecture follows a zero-trust model where the server never has access to plaintext messages.

## Monorepo Structure

- `enigmo_app/` - Flutter cross-platform client (iOS, Android, Web)
- `enigmo_server/` - Lightweight Dart WebSocket/REST server
- Root level contains build automation, documentation, and deployment scripts

## Common Development Commands

### Setup and Dependencies
```bash
# Install all dependencies (preferred method)
make setup

# Manual setup
cd enigmo_server && dart pub get
cd enigmo_app && flutter pub get
```

### Development Servers
```bash
# Start Dart server (development mode)
make dev-server
# Or manually: cd enigmo_server && dart run bin/anongram_server.dart --host localhost --port 8081 --debug

# Start Flutter app
make dev-app-ios      # iOS simulator
make dev-app-android  # Android emulator  
make dev-app-web      # Web browser
```

### Testing
```bash
make test           # Run all tests with coverage
make test-server    # Server tests only
make test-app       # Flutter app tests only
```

### Code Quality
```bash
make lint           # Static analysis for both projects
make format         # Code formatting for both projects
```

### Building
```bash
make build-server              # Compile server executable
make build-app-android        # Android APK
make build-app-android-bundle # Android App Bundle (preferred for Play Store)
make build-app-ios            # iOS app
make build-app-web            # Web app
```

### Health Monitoring
```bash
make health-check   # Check if server is running
make stats         # Display server statistics
```

## Architecture Highlights

### Client-Side Architecture (enigmo_app/)
- **CryptoEngine** (`lib/services/crypto_engine.dart`) - Core E2EE implementation using Ed25519/X25519/ChaCha20-Poly1305
- **NetworkService** (`lib/services/network_service.dart`) - WebSocket client and message handling
- **KeyManager** (`lib/services/key_manager.dart`) - Secure key storage using flutter_secure_storage
- **AudioCallService** (`lib/services/audio_call_service.dart`) - WebRTC voice calling implementation

### Server-Side Architecture (enigmo_server/)
- **WebSocketHandler** (`lib/services/websocket_handler.dart`) - Real-time message routing and call signaling
- **UserManager** (`lib/services/user_manager.dart`) - Public key directory and user session management
- **MessageManager** (`lib/services/message_manager.dart`) - Zero-knowledge message forwarding
- **AuthService** (`lib/services/auth_service.dart`) - Token-based authentication

## Key Implementation Details

### Cryptographic Flow
1. Users generate Ed25519 (signing) and X25519 (encryption) key pairs locally
2. Public keys are registered with server for peer discovery
3. ECDH is performed to derive shared secrets for symmetric encryption
4. Messages are encrypted with ChaCha20-Poly1305 and signed with Ed25519
5. Server routes encrypted messages without decryption capability

### WebSocket Message Protocol
The server handles these message types:
- `auth` - User authentication with public key registration
- `send_message` - Encrypted message routing
- `get_users` - Public key directory lookup
- `call_*` - WebRTC signaling for voice calls

### Voice Calling System
- WebRTC peer-to-peer connections with STUN server support
- Call signaling through WebSocket server
- Audio-only implementation with noise suppression and echo cancellation
- Platform-specific notification handling for incoming calls

## Testing Strategy

### Client Tests (`enigmo_app/test/`)
- **Unit tests** - Core crypto operations, key management, network service
- **Widget tests** - UI components and screens
- **Integration tests** - End-to-end message flow and WebRTC calling
- **Security tests** - Cryptographic implementation validation

### Server Tests (`enigmo_server/test/`)
- **Unit tests** - User management, message routing, WebSocket handling
- **Integration tests** - Client-server communication flows
- **Performance tests** - Message throughput and connection handling

## Development Notes

### Flutter Specific
- Uses `flutter_secure_storage` for key persistence
- WebRTC implementation via `flutter_webrtc` package
- Cross-platform support for iOS, Android, and Web
- Notification system with `flutter_local_notifications`

### Dart Server Specific  
- Built with Shelf framework for HTTP/WebSocket handling
- Stateless design for horizontal scaling
- In-memory user sessions (production would use Redis/database)
- CORS enabled for web client compatibility

### Cryptography Dependencies
- Client: `cryptography` and `pointycastle` packages
- Server: `cryptography` and native `crypto` packages
- All crypto operations use modern, audited algorithms

## Production Considerations

- Server runs on configurable host/port (default: 0.0.0.0:8081)
- Health endpoint: `/api/health` 
- Statistics endpoint: `/api/stats`
- WebSocket endpoint: `/ws`
- Docker support via included `docker-compose.yml`
- SSL/TLS termination handled by reverse proxy (nginx/traefik)

## Security Notes

- Zero-knowledge server architecture - server cannot decrypt messages
- Perfect forward secrecy via ephemeral key exchanges
- Message authenticity through digital signatures
- Client-side key generation and secure storage
- Replay protection via nonces and timestamp validation