# seek issue

When seeking (when video is paused, or being played) the video stutters and has clearly some feedback loop between clients.
Analyze the code and find a fix.

# client output

```sh
client: client 1 sought to 1766.848 seconds
client: client 2 (you) sought to 1766.848 seconds
client: client 1 sought to 1766.848 seconds
client: client 2 (you) sought to 1766.848 seconds
client: client 1 sought to 1766.848 seconds
client: client 2 (you) sought to 1766.848 seconds
client: client 1 sought to 1766.848 seconds
client: client 2 (you) sought to 1766.848 seconds
client: client 1 sought to 1766.848 seconds
client: client 2 (you) sought to 1766.848 seconds
client: client 1 sought to 1766.848 seconds
client: client 2 (you) sought to 1766.848 seconds
client: client 1 sought to 1766.848 seconds
client: client 2 (you) sought to 1766.848 seconds
client: client 1 sought to 1766.848 seconds
client: client 2 (you) sought to 1766.848 seconds
client: client 1 sought to 1766.848 seconds
client: client 2 (you) sought to 1766.848 seconds
client: client 1 sought to 1766.848 seconds
client: client 2 (you) sought to 1766.848 seconds
client: client 1 sought to 1766.848 seconds
client: client 2 (you) sought to 1766.848 seconds
client: client 2 (you) played
client: client 1 sought to 1766.848 seconds
client: client 2 (you) sought to 1766.890 seconds
client: client 1 sought to 1766.932 seconds
client: client 2 (you) sought to 1766.974 seconds
client: client 1 sought to 1767.015 seconds
client: client 2 (you) sought to 1767.057 seconds
client: client 1 sought to 1767.099 seconds
client: client 2 (you) sought to 1767.140 seconds
client: client 1 sought to 1767.182 seconds
client: client 2 (you) sought to 1767.224 seconds
client: client 1 sought to 1767.266 seconds
client: client 2 (you) sought to 1767.307 seconds
client: client 1 sought to 1767.349 seconds
client: client 2 (you) paused
client: client 2 (you) played
client: client 2 (you) paused
client: client 2 (you) played
client: client 2 (you) paused
client: mpv IPC connection closed
client: server connection lost (mpv exited); playback will continue
client: mpv exited with status 15
```

# server output

```sh
server: client 2 sought to 1766.848 seconds
server: client 1 sought to 1766.848 seconds
server: client 2 sought to 1766.848 seconds
server: client 1 sought to 1766.848 seconds
server: client 2 sought to 1766.848 seconds
server: client 1 sought to 1766.848 seconds
server: client 2 sought to 1766.848 seconds
server: client 1 sought to 1766.848 seconds
server: client 2 sought to 1766.848 seconds
server: client 1 sought to 1766.848 seconds
server: client 2 sought to 1766.848 seconds
server: client 1 sought to 1766.848 seconds
server: client 2 sought to 1766.848 seconds
server: client 1 sought to 1766.848 seconds
server: client 2 sought to 1766.848 seconds
server: client 1 sought to 1766.848 seconds
server: client 2 sought to 1766.848 seconds
server: client 1 sought to 1766.848 seconds
server: client 2 sought to 1766.848 seconds
server: client 1 sought to 1766.848 seconds
server: client 2 sought to 1766.848 seconds
server: client 1 sought to 1766.848 seconds
server: client 2 sought to 1766.848 seconds
server: client 1 sought to 1766.848 seconds
server: client 2 sought to 1766.848 seconds
server: client 2 played
server: client 1 sought to 1766.848 seconds
server: client 2 sought to 1766.890 seconds
server: client 1 sought to 1766.932 seconds
server: client 2 sought to 1766.974 seconds
server: client 1 sought to 1767.015 seconds
server: client 2 sought to 1767.057 seconds
server: client 1 sought to 1767.099 seconds
server: client 2 sought to 1767.140 seconds
server: client 1 sought to 1767.182 seconds
server: client 2 sought to 1767.224 seconds
server: client 1 sought to 1767.266 seconds
server: client 2 sought to 1767.307 seconds
server: client 1 sought to 1767.349 seconds
server: client 2 paused
server: client 2 played
server: client 2 paused
server: client 2 played
server: client 2 paused
server: client 2 disconnected (connection closed)
server: client 1 disconnected (connection closed)
```
