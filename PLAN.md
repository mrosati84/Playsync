# Sync play for MPV

Goal: write an Odin application to sync playback between remote viewers via a small Odin program.

The program will be called `syncplay`. The player is called `mpv`. `syncplay` is a single executable that can be run by clients, and is also executable in a remote server that functions as events dispatcher. The server is required.

Use case: two friends want to see the same movie using MPV, and they want synchronized playback. If one pauses, the video pauses for the other viewer. If one seeks to xx:xx:xx, also the other player seeks to xx:xx:xx.

**Server**

```sh
./syncplay server --port <port> --host 0.0.0.0
```

**Client**

```sh
./syncplay client --port <port> --host <remote-ip> \
  [--mpv <mpv-path>] [--socket <socket-path>] <movie>
```

Supported operations:

- play
- pause
- seek

On macOS, the client launches MPV with a JSON IPC UNIX socket. `syncplay`
connects to that socket, observes pause changes and seek events, and sends JSON
commands to apply events received from the relay server.

The TCP protocol is newline-delimited JSON. There is one global session, no
authentication, and no server-held playback state. Messages are absolute state
changes:

```json
{"version":1,"type":"welcome","client_id":1}
{"version":1,"type":"pause","paused":true}
{"version":1,"type":"pause","paused":false}
{"version":1,"type":"seek","position":123.456}
```

The server assigns a numeric ID when a client connects and includes the
triggering ID in every relayed event. Both server and client terminals log each
play, pause, and seek action with that client ID.

Clients start paused at `00:00:00` and are assumed to use the same movie. There
is no clock synchronization or drift correction. If a connection is lost,
playback continues locally and the event is logged; clients do not reconnect.

**Example flow**:

0. Someone starts `syncplay` on a remote server.
1. User A starts `syncplay`. The program starts and runs the `mpv` player.
2. Then it connects to the remote `syncplay` instance.
3. `syncplay` observes pause and seek events reported by MPV over JSON IPC.
4. `syncplay` translates supported local events and sends them to the server.
5. The server will stream to all connected clients the same event.
6. Any connected client receives the event and sends the corresponding JSON IPC
   command to its local MPV instance.

Remote seeks use a serialized, acknowledged transaction: disable delivery of
the `seek` event for the IPC connection, apply an `absolute+exact` seek, then
re-enable the event even when the seek fails. This prevents remote seeks from
being reported as new local seeks and looping through the server.

**Example cli command to run MPV**

Pay attention to the socket path. That, along with the MPV path must likely be constants in the Odin program.

```sh
/Applications/mpv.app/Contents/MacOS/mpv \
  --force-window=yes \
  --idle=yes \
  --pause=yes \
  --start=0 \
  --hr-seek=always \
  --keep-open=always \
  --keep-open-pause=yes \
  --input-ipc-server=/tmp/mpv-socket \
  --input-terminal=no \
  --terminal=no
```
