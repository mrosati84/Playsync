package main

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:os"
import "core:sync"
import "core:sys/posix"
import "core:thread"
import "core:time"

Client_State :: struct {
	mutex: sync.Mutex,
	client_id: u64,

	network_socket: net.TCP_Socket,
	network_active: bool,
	network_write_mutex: sync.Mutex,

	mpv:     ^Mpv_Connection,
	process: os.Process,
	stopping: bool,

	ignore_initial_pause: bool,
	remote_pause_pending: bool,
	remote_pause_value:   bool,
	have_last_pause:      bool,
	last_pause:           bool,
	local_seek_pending:   bool,
}

client_close_network :: proc(client: ^Client_State, reason: string) {
	sync.mutex_lock(&client.mutex)
	if !client.network_active {
		sync.mutex_unlock(&client.mutex)
		return
	}
	client.network_active = false
	socket := client.network_socket
	sync.mutex_unlock(&client.mutex)

	_ = net.shutdown(socket, .Both)
	net.close(socket)
	fmt.printfln("client: server connection lost (%s); playback will continue", reason)
}

client_send_event :: proc(client: ^Client_State, event: Playback_Event) -> bool {
	line := encode_protocol_event(event)
	defer delete(line)

	sync.mutex_lock(&client.network_write_mutex)
	defer sync.mutex_unlock(&client.network_write_mutex)
	sync.mutex_lock(&client.mutex)
	active := client.network_active
	socket := client.network_socket
	client_id := client.client_id
	sync.mutex_unlock(&client.mutex)
	log_playback_event("client", client_id, event, is_local = true)
	if !active {
		return false
	}

	written, send_err := net.send_tcp(socket, transmute([]byte)line)
	if send_err != nil || written != len(line) {
		client_close_network(client, "send failed")
		return false
	}
	return true
}

client_position_worker :: proc(data: rawptr) {
	defer runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data)
	client := cast(^Client_State)data
	position, ok := mpv_get_time_position(client.mpv)
	if ok {
		client_send_event(client, Playback_Event{kind = .Seek, position = position})
	} else {
		fmt.eprintln("client: could not read position after local seek")
	}
}

client_on_pause_change :: proc(client: ^Client_State, paused: bool) {
	should_send := false
	sync.mutex_lock(&client.mutex)
	if client.ignore_initial_pause {
		client.ignore_initial_pause = false
		client.have_last_pause = true
		client.last_pause = paused
	} else if client.remote_pause_pending && paused == client.remote_pause_value {
		client.remote_pause_pending = false
		client.have_last_pause = true
		client.last_pause = paused
	} else {
		client.remote_pause_pending = false
		if !client.have_last_pause || paused != client.last_pause {
			client.have_last_pause = true
			client.last_pause = paused
			should_send = true
		}
	}
	sync.mutex_unlock(&client.mutex)

	if should_send {
		client_send_event(client, Playback_Event{kind = .Pause, paused = paused})
	}
}

client_on_mpv_event :: proc(client: ^Client_State, event_name: string, object: json.Object) {
	switch event_name {
	case "property-change":
		name_value, has_name := object["name"]
		data_value, has_data := object["data"]
		if !has_name || !has_data {
			return
		}
		name, name_ok := name_value.(json.String)
		paused, pause_ok := data_value.(json.Boolean)
		if name_ok && pause_ok && string(name) == "pause" {
			client_on_pause_change(client, bool(paused))
		}

	case "seek":
		sync.mutex_lock(&client.mutex)
		client.local_seek_pending = true
		sync.mutex_unlock(&client.mutex)

	case "playback-restart":
		should_query := false
		sync.mutex_lock(&client.mutex)
		if client.local_seek_pending {
			client.local_seek_pending = false
			should_query = true
		}
		sync.mutex_unlock(&client.mutex)
		if should_query {
			_ = thread.create_and_start_with_data(
				rawptr(client),
				client_position_worker,
				init_context = context,
				self_cleanup = true,
			)
		}
	}
}

client_on_mpv_disconnect :: proc(client: ^Client_State) {
	sync.mutex_lock(&client.mutex)
	already_stopping := client.stopping
	client.stopping = true
	sync.mutex_unlock(&client.mutex)
	if !already_stopping {
		fmt.eprintln("client: mpv IPC connection closed")
		_ = os.process_terminate(client.process)
	}
}

client_apply_remote_event :: proc(client: ^Client_State, event: Playback_Event) -> bool {
	switch event.kind {
	case .Pause:
		sync.mutex_lock(&client.mutex)
		client.remote_pause_pending = true
		client.remote_pause_value = event.paused
		sync.mutex_unlock(&client.mutex)
		if !mpv_set_pause(client.mpv, event.paused) {
			fmt.eprintln("client: failed to apply remote pause event")
			return false
		}
		return true
	case .Seek:
		if !mpv_apply_remote_seek(client.mpv, event.position) {
			fmt.eprintln("client: failed to apply remote seek safely")
			return false
		}
		return true
	}
	return false
}

client_network_reader :: proc(data: rawptr) {
	defer runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data)
	client := cast(^Client_State)data
	framer: Line_Framer
	framer_init(&framer)
	defer framer_destroy(&framer)
	buffer: [2048]byte
	reason := "connection closed"

	for {
		count, recv_err := net.recv_tcp(client.network_socket, buffer[:])
		if recv_err != nil {
			reason = "receive failed"
			break
		}
		if count == 0 {
			break
		}
		frames, frame_err := framer_push(&framer, buffer[:count])
		if frame_err != .None {
			destroy_frames(frames)
			reason = "oversized message"
			break
		}
		valid := true
		for frame in frames {
			if len(frame) == 0 {
				continue
			}
			welcome_id, is_welcome, welcome_err := parse_welcome(transmute([]byte)frame)
			if is_welcome {
				if welcome_err != .None {
					fmt.eprintfln("client: invalid welcome message: %s", protocol_error_string(welcome_err))
					reason = "invalid welcome message"
					valid = false
					break
				}
				sync.mutex_lock(&client.mutex)
				client.client_id = welcome_id
				sync.mutex_unlock(&client.mutex)
				fmt.printfln("client: assigned client ID %d", welcome_id)
				continue
			}
			_ = welcome_err

			event, protocol_err := parse_protocol_event(transmute([]byte)frame)
			if protocol_err != .None {
				fmt.eprintfln("client: server sent invalid message: %s", protocol_error_string(protocol_err))
				reason = "invalid server message"
				valid = false
				break
			}
			if event.client_id == 0 {
				fmt.eprintln("client: server event is missing its triggering client ID")
				reason = "event missing client ID"
				valid = false
				break
			}
			if !client_apply_remote_event(client, event) {
				reason = "could not apply remote event"
				valid = false
				break
			}
			log_playback_event("client", event.client_id, event)
		}
		destroy_frames(frames)
		if !valid {
			break
		}
	}
	client_close_network(client, reason)
}

receive_server_welcome :: proc(socket: net.TCP_Socket) -> (client_id: u64, ok: bool) {
	buffer: [MAX_FRAME_BYTES+1]byte
	length := 0
	for length < len(buffer) {
		count, recv_err := net.recv_tcp(socket, buffer[length:length+1])
		if recv_err != nil || count == 0 {
			fmt.eprintln("client: server disconnected before assigning a client ID")
			return 0, false
		}
		if buffer[length] == '\n' {
			end := length
			if end > 0 && buffer[end-1] == '\r' {
				end -= 1
			}
			matched: bool
			protocol_err: Protocol_Error
			client_id, matched, protocol_err = parse_welcome(buffer[:end])
			if !matched || protocol_err != .None {
				fmt.eprintfln("client: invalid server welcome: %s", protocol_error_string(protocol_err))
				return 0, false
			}
			return client_id, true
		}
		length += 1
	}
	fmt.eprintln("client: server welcome exceeded the message limit")
	return 0, false
}

start_mpv_process :: proc(options: Options) -> (process: os.Process, ok: bool) {
	command := []string{
		options.mpv_path,
		"--force-window=yes",
		"--idle=yes",
		"--pause=yes",
		"--start=0",
		"--hr-seek=always",
		"--keep-open=always",
		"--keep-open-pause=yes",
		"--input-terminal=no",
		"--terminal=no",
		fmt.tprintf("--input-ipc-server=%s", options.socket_path),
		options.movie_path,
	}
	process_err: os.Error
	process, process_err = os.process_start(os.Process_Desc{
		command = command,
		stdout = os.stdout,
		stderr = os.stderr,
	})
	if process_err != nil {
		fmt.eprintfln("client: could not start mpv: %v", process_err)
		return {}, false
	}
	return process, true
}

wait_for_mpv_socket :: proc(process: os.Process, path: string) -> (posix_fd: int, ok: bool) {
	deadline := time.time_add(time.now(), 5*time.Second)
	for time.time_to_unix_nano(time.now()) < time.time_to_unix_nano(deadline) {
		fd, connected := connect_unix_socket(path)
		if connected {
			return int(fd), true
		}
		state, wait_err := os.process_wait(process, timeout = 0)
		if wait_err == nil && state.exited {
			fmt.eprintln("client: mpv exited before its IPC socket became ready")
			return -1, false
		}
		time.sleep(50*time.Millisecond)
	}
	fmt.eprintln("client: timed out waiting for mpv IPC socket")
	return -1, false
}

run_client :: proc(options: Options) -> bool {
	when ODIN_OS != .Darwin {
		fmt.eprintln("client: client mode is supported only on macOS")
		return false
	}

	network_socket, dial_err := net.dial_tcp_from_hostname_with_port_override(options.host, options.port)
	if dial_err != nil {
		fmt.eprintfln("client: could not connect to server: %v", dial_err)
		return false
	}
	client_id, welcome_ok := receive_server_welcome(network_socket)
	if !welcome_ok {
		net.close(network_socket)
		return false
	}
	fmt.printfln("client: assigned client ID %d", client_id)

	process, process_ok := start_mpv_process(options)
	if !process_ok {
		net.close(network_socket)
		return false
	}

	fd_value, socket_ok := wait_for_mpv_socket(process, options.socket_path)
	if !socket_ok {
		_ = os.process_terminate(process)
		_, _ = os.process_wait(process)
		net.close(network_socket)
		return false
	}

	client := new(Client_State)
	client.client_id = client_id
	client.network_socket = network_socket
	client.network_active = true
	client.process = process
	client.ignore_initial_pause = true
	mpv := new(Mpv_Connection)
	mpv.fd = posix.FD(fd_value)
	mpv.client = client
	client.mpv = mpv

	mpv_thread := mpv_start_reader(mpv)
	if mpv_thread == nil {
		fmt.eprintln("client: could not start mpv IPC reader")
		mpv_close(mpv)
		client_close_network(client, "startup failed")
		_ = os.process_terminate(process)
		_, _ = os.process_wait(process)
		return false
	}
	if !mpv_observe_pause(mpv) {
		fmt.eprintln("client: could not observe mpv pause state")
		mpv_close(mpv)
		client_close_network(client, "startup failed")
		_ = os.process_terminate(process)
		_, _ = os.process_wait(process)
		thread.join(mpv_thread)
		thread.destroy(mpv_thread)
		return false
	}

	network_thread := thread.create_and_start_with_data(
		rawptr(client),
		client_network_reader,
		init_context = context,
		self_cleanup = false,
	)
	if network_thread == nil {
		fmt.eprintln("client: could not start server reader")
		mpv_close(mpv)
		client_close_network(client, "startup failed")
		_ = os.process_terminate(process)
		_, _ = os.process_wait(process)
		thread.join(mpv_thread)
		thread.destroy(mpv_thread)
		return false
	}

	fmt.println("client: connected; playback starts paused at 00:00:00")
	state: os.Process_State
	wait_err: os.Error
	for {
		state, wait_err = os.process_wait(process, timeout = 100*time.Millisecond)
		if wait_err == nil {
			break
		}
		if should_shutdown() {
			fmt.println("client: shutdown requested; terminating mpv")
			_ = os.process_terminate(process)
			state, wait_err = os.process_wait(process, timeout = 2*time.Second)
			if wait_err != nil {
				_ = os.process_kill(process)
				state, wait_err = os.process_wait(process)
			}
			break
		}
		if wait_err != os.General_Error.Timeout {
			break
		}
	}
	sync.mutex_lock(&client.mutex)
	client.stopping = true
	sync.mutex_unlock(&client.mutex)
	client_close_network(client, "mpv exited")
	mpv_close(mpv)
	thread.join(network_thread)
	thread.destroy(network_thread)
	thread.join(mpv_thread)
	thread.destroy(mpv_thread)
	if wait_err != nil {
		fmt.eprintfln("client: waiting for mpv failed: %v", wait_err)
		return false
	}
	if !state.success {
		fmt.eprintfln("client: mpv exited with status %d", state.exit_code)
		return false
	}
	return true
}
