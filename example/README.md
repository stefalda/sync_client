# sync_client Example — Todo App

This Flutter example demonstrates the `sync_client` library by running three SQLite todo-list databases side-by-side:

- **`primaryDB`** — uses HTTP-based sync (via `SQLiteWrapperSync`)
- **`secondaryDB`** — also HTTP-based sync, registered as a second device
- **`grpcDB`** — uses gRPC sync (via `SQLiteWrapperSyncGRPC` through an Envoy proxy)

Each column lets you add, toggle (tap), and delete (long-press) todo items, then configure and sync with the sync server.

## Prerequisites

- Flutter SDK 3.x (compatible with Dart SDK `>=2.17.0 <4.0.0`)
- Docker & Docker Compose (for the sync server backend)

## Getting Started

### 1. Ensure the root library dependency resolves

The `sync_client` library (at the parent directory) depends on `sqlite_wrapper`. If you encounter dependency resolution errors, make sure the constraint in `sync_client/pubspec.yaml` uses a version that exists on pub.dev:

```yaml
dependencies:
  sqlite_wrapper: ^0.4.0
```

### 2. Start the backend services

The sync server, PostgreSQL database, gRPC wrapper server, and Envoy proxy all run in Docker:

```bash
cd server
docker compose up -d
```

This starts:
- **PostgreSQL** on port `5432`
- **sync_server** (REST API) on port `3000`
- **sqlite_wrapper_server** (gRPC) on port `50051`
- **Envoy proxy** (gRPC gateway) on port `50052`

### 3. Run the app

```bash
flutter pub get
flutter run
```

Target macOS, iOS, Android, Linux, or Windows. Web is also supported but requires `sqflite_common_ffi_web` (run `dart run sqflite_common_ffi_web:setup --force` first).

### 4. Use the app

1. Tap **"Add new Todo"** to insert items in any column.
2. Tap a todo to toggle its done/undone state.
3. Long-press a todo to delete it.
4. Tap **"Register"** (bottom center) to register both HTTP databases with the sync server.
5. Tap **"Configure"** / **"Sync"** per column to register and sync that database individually.

Each column operates on its own SQLite file stored in the platform's documents directory.
