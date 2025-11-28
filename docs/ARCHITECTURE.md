# Dartvel Architecture

Dartvel is a full-stack framework designed for building high-performance, multi-platform applications with Flutter and Dart.

## System Overview

Dartvel consists of four main components:

1.  **Dartvel CLI (`dartvel_cli`)**: The command-line interface for project management, code generation, and development tools.
2.  **Dartvel Core (`dartvel_core`)**: The core library providing essential utilities, types, and abstractions for the framework.
3.  **Dartvel Flutter (`dartvel_flutter`)**: The Flutter package containing widgets, state management, and platform integrations.
4.  **Dartvel Shelf (`dartvel_shelf`)**: The backend server implementation powered by Rust and Actix Web via FFI.

## Component Interactions

### Client-Side (Flutter)

The Flutter client interacts with the backend via generated API clients. The `dartvel_flutter` package provides:

-   **Routing**: File-based routing with `go_router` integration.
-   **State Management**: Built-in state management for data fetching and caching.
-   **Platform Integration**: Abstractions for platform-specific features like SEO and i18n.

### Server-Side (Rust + Dart)

The backend is a hybrid system:

-   **Rust Core**: Handles low-level HTTP parsing, connection management, and heavy lifting (compression, static files).
-   **Dart Logic**: Business logic and API handlers are written in Dart.
-   **FFI Bridge**: Communication between Rust and Dart happens via a high-performance FFI layer.

## FFI Design

The FFI boundary is designed to minimize overhead:

-   **Shared Memory**: Where possible, memory is shared to avoid copying.
-   **Batching**: Operations are batched to reduce the number of FFI calls.
-   **Asynchronous Handling**: Requests are handled asynchronously to prevent blocking the main thread.

## Security

-   **Environment Variables**: Secrets are obfuscated in the client build.
-   **Authentication**: Built-in JWT and session management.
-   **CORS**: Configurable CORS support at the Rust level.
