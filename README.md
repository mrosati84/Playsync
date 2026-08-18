# playsync

`playsync` is a small Odin program that relays play, pause, and seek actions
between a few trusted mpv users. One executable provides both the TCP relay
server and the macOS client.

## Requirements

- Odin 2026-07 or newer
- macOS for client mode
- macOS or Linux for server mode
- mpv installed on every client
- The same media file (including the same cut) on every client

## Build and test

```sh
odin check .
odin test .
odin build . -out:playsync
```

## Run

Start one relay server:

```sh
./playsync server --host 0.0.0.0 --port 9000
```

Then each viewer starts a client with their local copy of the movie:

```sh
./playsync client \
  --host server.example.test \
  --port 9000 \
  /path/to/movie.mkv
```

The macOS defaults can be overridden:

```sh
./playsync client \
  --host server.example.test \
  --port 9000 \
  --mpv /custom/path/to/mpv \
  --socket /tmp/custom-mpv-socket \
  /path/to/movie.mkv
```

The client starts at `00:00:00` in the paused state. Closing mpv closes the
client. Interrupting the client terminates the mpv process it launched. If the
server connection is lost after startup, mpv continues normally and the client
logs that synchronization has stopped.

## Protocol

The trusted-network protocol is newline-delimited JSON over TCP:

```json
{"version":1,"type":"welcome","client_id":1}
{"version":1,"type":"pause","paused":true}
{"version":1,"type":"pause","paused":false}
{"version":1,"type":"seek","position":3723.125}
```

Messages are limited to 4096 bytes. The server validates and re-encodes every
message, preserves processing order, and broadcasts it to every connection
except its sender. It assigns each connection a numeric client ID and adds the
triggering ID to relayed events. Server and client terminals log play, pause,
and seek actions with that ID; the triggering client is marked with `(you)` in
its own terminal.

Remote seeks are applied using an mpv IPC transaction: seek event delivery is
disabled for this IPC connection, an exact absolute seek is sent, and the
client waits for mpv's `playback-restart` completion event before restoring
seek event delivery. A command reply can arrive before the seek effects, so it
is not sufficient as the end of the suppression window. Event delivery is
still restored if the operation fails. This prevents a remote seek from being
mistaken for a new local seek and sent back indefinitely.

## Prototype limitations

- One global session; no rooms or late-join state snapshot
- No authentication, encryption, or Internet-facing security
- No automatic reconnection
- No media identity checking
- No clock synchronization or drift correction
- mpv can report internally generated operations as seek events
- A local seek made during the brief remote-seek suppression transaction may
  not be relayed because mpv events do not identify their origin
