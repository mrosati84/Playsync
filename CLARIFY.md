## Missing specifications that block implementation

1.  Media selection

The client command has no movie argument. It is unclear whether the user:

- passes a file to syncplay;
- opens a file afterward through mpv;
- or launches mpv separately.

ANSWER: passes a file to syncplay

2.  Session model

The server broadcasts to “all connected clients,” but it does not say whether there is exactly one global viewing session or whether named rooms are required.

ANSWER: no rooms. one global viewing session. This program is intended to be run by people that know each other, and maximum 2-3 persons.

3. Joining behavior

A newly connected client needs an initial state: current position, paused/playing status, and possibly media identity. A pure event dispatcher cannot provide that unless another client republishes its state.

ANSWER: `syncplay` starts and has a movie specified. The initial state is paused and at 00:00:00.

4. Authoritative state

There is no rule for simultaneous or conflicting actions. For example, A pauses while B seeks or immediately presses play. The server needs an ordering rule, even if it is only “last event received wins.”

ANSWER: even if the movie is paused, users can still seek. This is how normally the video player works. So there is no reason why a user could seek while the player is paused. Agree?

5. Network protocol

The plan does not specify:

- TCP, WebSocket, or another transport;
- message framing;
- message schema;
- protocol versioning;
- connection handshake; - keepalive or timeout behavior.

ANSWER: TCP preferrable, but pick the easiest option. For all other above points i have no answer, pick sensible defaults.

3.  Feedback-loop prevention

Remotely applying pause or seek causes mpv events locally. The plan does not define how clients recognize and suppress those echoed changes.

ANSWER: i don't understand where is the issue. The event is firts applied locally (i.e. pause). Then that same event is sent to the server for the other clients to pick it up.

4.  Meaning of synchronization

Relaying play, pause, and seek operations does not maintain close synchronization during uninterrupted playback. Independent players can gradually drift, and network latency makes “play now” happen at different times.
The plan must say whether the prototype only mirrors user actions or also periodically measures and corrects drift.

ANSWER: I don't care about the exact synchronization or drifting. If drifting happens, the users can still seek and all other clients will receive the event.

5.  Seek semantics

“Seek to xx:xx:xx” suggests absolute seconds, but the protocol needs to specify:

- absolute versus relative positions;
- precision;
- exact versus keyframe seek;
- behavior when duration differs between clients.

ANSWER: OK.

6.  Source compatibility

There is no requirement that participants load the same media. A position alone is meaningless if files, editions, durations, or opening offsets differ.

ANSWER: it is assumed that the clients pick the same file.

7.  Reconnect behavior

It is unspecified whether a disconnected client retries, exits, keeps playing locally, or resynchronizes after reconnecting.

ANSWER: if a client disconnects, or loses the connection to the server, the playback continues normally. Log the event to the console.

8.  mpv startup lifecycle

The plan does not define:

- how long to wait for the IPC socket;
- what happens if mpv fails to start;
- how stale socket files are handled;
- whether closing mpv terminates syncplay;
- whether closing syncplay terminates mpv.

ANSWERS:

- how long to wait for the IPC socket: I don't understand the question. Use sensible defaults.
- what happens if mpv fails to start: Quit and log the error.
- how stale socket files are handled: Quit and log the error.
- whether closing mpv terminates syncplay: Yes.
- whether closing syncplay terminates mpv: Yes.

9.  Platform scope

/Applications/mpv.app/... is macOS-specific, while Unix sockets suggest macOS/Linux. Supported client platforms and executable discovery need to be explicit.

ANSWER: Support only MacOS and Linux (Linux only for server) with the defaults i have provided.

10. Configuration

Hard-coding /tmp/mpv-socket prevents multiple local instances and risks collision with a stale or unrelated socket. The mpv executable and socket should at least be overrideable, even if defaults are provided.

ANSWER: I don't care about multiple local instances. Only one is expected. Provide `--socket` and `--mpv` cli options to override defaults.

11. Security boundary

A server bound to 0.0.0.0 permits anyone who can reach it to control every connected player unless authentication or network-level trust is assumed. The plan needs to state whether an unauthenticated trusted-network prototype is acceptable.

ANSWER: I don't care about security or authentication. This is expected to run on a trusted environment by a few people.

12. Failure handling and limits

Missing behavior includes malformed messages, slow clients, disconnected sockets, oversized messages, and server capacity.

ANSWER: TCP or WebSocket should deal with malformed messages already. IDC about slow clients, we are talking about very small packets. Oversized messages and server capacity are not a concern for all answers above.

13. Prototype acceptance criteria

There is no concrete test defining “up and running”: supported OS, number of clients, acceptable latency/drift, reconnect expectations, and required automated tests.

ANSWER: supported OS: MacOS and Linux (Linux server only). I said already IDC about drifting. Write automated unit tests in Odin where applicable. I don't need end-to-end testing.

## Internal inconsistencies or misleading details

- The IPC socket path is supplied to mpv, but mpv creates/listens on it; syncplay does not create a shared read/write command stream. ANSWER IDK, pick defaults.
- “Every interaction with MPV will write in the socket” is incorrect; explicit property observation and event handling are needed. ANSWER IDK, pick defaults.
- The example contains --input-terminal=no twice. ANSWER: remove the duplicate option, it is a typo.
- “The socket path and mpv path must likely be constants” conflicts with portability and safe concurrent use. ANSWER: we provide overrides via cli options.
- Calling the server only an “events dispatcher” conflicts with seamless late joining, which requires either server-held state or a designated client supplying a snapshot. ANSWER: IDC about late joining. If someone joins late, a seek event from any client will fix the drift.
- “Synchronized playback” implies clock/drift synchronization, while the listed behavior only promises event replication. ANSWER IDC about clock/drift sync.
