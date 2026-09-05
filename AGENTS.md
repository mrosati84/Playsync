# Repository Guidelines

## Project Structure & Module Organization

PlaySync is a single-package Odin application; all `.odin` files live at the repository root. `main.odin` dispatches the CLI, while `cli.odin`, `server.odin`, and `client.odin` implement the main execution paths. Protocol encoding and TCP framing are isolated in `protocol.odin` and `framing.odin`; `mpv.odin` owns mpv JSON IPC, and `shutdown.odin` handles signals. Tests sit beside their implementation as `*_test.odin`. Design notes and known constraints are documented in `README.md`, `PLAN.md`, `CLARIFY.md`, and `SEEK.md`.

## Build, Test, and Development Commands

Use Odin 2026-07 or newer:

```sh
odin check .                 # Type-check the package
odin test .                  # Run all @(test) procedures
odin build . -out:playsync   # Build the server/client executable
./playsync server --host 0.0.0.0 --port 9000
```

Client and server modes both support macOS and Linux, and the client needs mpv (the `mpv.app` bundle on macOS, `mpv` from `PATH` on Linux). See `README.md` for client launch examples and optional mpv/socket paths.

## Coding Style & Naming Conventions

Follow the existing Odin style: tabs for indentation, lowercase `snake_case` for procedures and fields, `Pascal_Case` for types and enum members, and uppercase `SNAKE_CASE` for constants. Keep imports grouped at the top and sourced from Odin's `base` or `core` libraries when possible. Prefer small procedures with explicit ownership; pair allocations with `defer delete(...)` or a dedicated destroy procedure. Run `odin check .` before submitting changes.

## Testing Guidelines

Use `core:testing` and mark tests with `@(test)`. Name tests as behavior statements, such as `framer_rejects_oversized_message`. Add or update the matching `*_test.odin` file for protocol, framing, CLI, client-state, and mpv IPC changes. There is no configured coverage threshold; regression tests are expected for bug fixes. Run `odin test .` locally.

## Commit & Pull Request Guidelines

History uses short, plain commit subjects (for example, `Rename syncplay to playsync` and `fix seek issue`) without mandatory prefixes. Keep each commit focused and use an imperative, descriptive subject. Pull requests should explain behavior changes, list verification commands, and call out platform-specific testing. Link relevant issues and include terminal output when CLI behavior or synchronization logs change.

## Security & Protocol Constraints

Treat the relay as trusted-network software: it has no authentication or encryption. Do not present it as Internet-safe without adding and documenting those controls. Preserve the 4096-byte frame limit, protocol version validation, and remote-seek suppression transaction.
