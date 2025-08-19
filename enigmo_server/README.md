# Enigmo Server

Lightweight Dart server for the Enigmo secure messaging platform. Provides REST health/stats and a WebSocket endpoint for real-time messaging. See `bin/anongram_server.dart` for the entrypoint and CLI options.

## Prerequisites
- Dart SDK (stable)

## Setup
```bash
dart pub get
```

## Run
```bash
dart run bin/anongram_server.dart --host localhost --port 8080
```
CLI options (from `ArgParser`):
- `--host, -h` (default: `localhost`)
- `--port, -p` (default: `8080`)
- `--help`

## Test
```bash
dart test
```

## Endpoints
- Health: `GET /api/health` (JSON status)
- Stats: `GET /api/stats` (server/users/messages)
- WebSocket: `GET /ws`

Logs include startup info and endpoints. Press Ctrl+C to stop.
