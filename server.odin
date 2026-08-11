package main

import "base:runtime"
import "core:fmt"
import "core:net"
import "core:sync"
import "core:thread"
import "core:sys/posix"

MAX_SERVER_CLIENTS :: 16

Server_State :: struct {
	mutex:   sync.Mutex,
	clients: [MAX_SERVER_CLIENTS]Server_Client,
	next_id: u64,
}

Server_Client :: struct {
	state:    ^Server_State,
	socket:   net.TCP_Socket,
	endpoint: net.Endpoint,
	id:       u64,
	active:   bool,
}

server_disconnect_locked :: proc(client: ^Server_Client, reason: string) {
	if !client.active {
		return
	}
	client.active = false
	_ = net.shutdown(client.socket, .Both)
	net.close(client.socket)
	fmt.printfln("server: client %d disconnected (%s)", client.id, reason)
}

server_broadcast :: proc(sender: ^Server_Client, event: Playback_Event) {
	state := sender.state
	sync.mutex_lock(&state.mutex)
	defer sync.mutex_unlock(&state.mutex)
	if !sender.active {
		return
	}
	outbound_event := event
	outbound_event.client_id = sender.id
	log_playback_event("server", sender.id, outbound_event)
	line := encode_protocol_event(outbound_event)
	defer delete(line)

	for &client in state.clients {
		if !client.active || client.id == sender.id {
			continue
		}
		written, send_err := net.send_tcp(client.socket, transmute([]byte)line)
		if send_err != nil || written != len(line) {
			server_disconnect_locked(&client, "send failed")
		}
	}
}

server_client_loop :: proc(data: rawptr) {
	defer runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data)
	client := cast(^Server_Client)data
	framer: Line_Framer
	framer_init(&framer)
	defer framer_destroy(&framer)
	buf: [2048]byte
	disconnect_reason := "connection closed"

	for {
		count, recv_err := net.recv_tcp(client.socket, buf[:])
		if recv_err != nil {
			disconnect_reason = "receive failed"
			break
		}
		if count == 0 {
			break
		}

		frames, frame_err := framer_push(&framer, buf[:count])
		if frame_err != .None {
			destroy_frames(frames)
			disconnect_reason = "oversized message"
			break
		}

		valid := true
		for frame in frames {
			if len(frame) == 0 {
				continue
			}
			event, protocol_err := parse_protocol_event(transmute([]byte)frame)
			if protocol_err != .None {
				fmt.printfln(
					"server: client %d sent invalid message: %s",
					client.id,
					protocol_error_string(protocol_err),
				)
				disconnect_reason = "invalid message"
				valid = false
				break
			}
			server_broadcast(client, event)
		}
		destroy_frames(frames)
		if !valid {
			break
		}
	}

	sync.mutex_lock(&client.state.mutex)
	server_disconnect_locked(client, disconnect_reason)
	sync.mutex_unlock(&client.state.mutex)
}

run_server :: proc(options: Options) -> bool {
	address, ok := net.parse_ip4_address(options.host)
	if !ok {
		fmt.eprintfln("server: host must be an IPv4 address: %s", options.host)
		return false
	}
	listener, listen_err := net.listen_tcp(net.Endpoint{address = address, port = options.port})
	if listen_err != nil {
		fmt.eprintfln("server: could not listen on %s:%d: %v", options.host, options.port, listen_err)
		return false
	}
	register_server_listener(posix.FD(net.Socket(listener)))
	defer clear_server_listener()

	state := new(Server_State)
	fmt.printfln("server: listening on %s:%d", options.host, options.port)

	for {
		socket, endpoint, accept_err := net.accept_tcp(listener)
		if accept_err != nil {
			if should_shutdown() {
				fmt.println("server: shutdown requested")
				return true
			}
			fmt.eprintfln("server: accept failed: %v", accept_err)
			net.close(listener)
			return false
		}

		client: ^Server_Client
		client_ready := false
		sync.mutex_lock(&state.mutex)
		for &candidate in state.clients {
			if !candidate.active {
				client = &candidate
				break
			}
		}
		if client != nil {
			state.next_id += 1
			client^ = Server_Client{
				state = state,
				socket = socket,
				endpoint = endpoint,
				id = state.next_id,
				active = true,
			}
			welcome := encode_welcome(client.id)
			welcome_length := len(welcome)
			written, welcome_err := net.send_tcp(client.socket, transmute([]byte)welcome)
			delete(welcome)
			if welcome_err == nil && written == welcome_length {
				client_ready = true
			} else {
				server_disconnect_locked(client, "could not send welcome")
			}
		}
		sync.mutex_unlock(&state.mutex)

		if client == nil {
			fmt.eprintln("server: connection rejected: client limit reached")
			net.close(socket)
			continue
		}
		if !client_ready {
			continue
		}

		remote := net.endpoint_to_string(endpoint)
		fmt.printfln("server: client %d connected from %s", client.id, remote)
		if thread.create_and_start_with_data(
			rawptr(client),
			server_client_loop,
			init_context = context,
			self_cleanup = true,
		) == nil {
			sync.mutex_lock(&state.mutex)
			server_disconnect_locked(client, "could not start client thread")
			sync.mutex_unlock(&state.mutex)
		}
	}
}
