package main

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:sync"
import "core:sys/posix"
import "core:thread"
import "core:time"

MPV_COMMAND_TIMEOUT :: 5*time.Second

Mpv_Command_Result :: struct {
	success:  bool,
	has_data: bool,
	data:     f64,
}

Mpv_Connection :: struct {
	fd: posix.FD,

	command_mutex: sync.Mutex,
	response_mutex: sync.Mutex,
	response_cond:  sync.Cond,
	next_request_id: i64,
	pending_id:      i64,
	pending_done:    bool,
	pending_result:  Mpv_Command_Result,
	closed:          bool,

	client: ^Client_State,
}

connect_unix_socket :: proc(path: string) -> (fd: posix.FD, ok: bool) {
	if len(path) == 0 {
		return -1, false
	}
	address: posix.sockaddr_un
	if len(path) >= len(address.sun_path) {
		return -1, false
	}
	address.sun_family = .UNIX
	when ODIN_OS == .Darwin {
		address.sun_len = u8(size_of(address))
	}
	for byte_value, index in transmute([]byte)path {
		address.sun_path[index] = auto_cast byte_value
	}
	address.sun_path[len(path)] = 0

	fd = posix.socket(.UNIX, .STREAM)
	if fd < 0 {
		return -1, false
	}
	if posix.connect(fd, (^posix.sockaddr)(&address), posix.socklen_t(size_of(address))) != .OK {
		_ = posix.close(fd)
		return -1, false
	}
	return fd, true
}

mpv_send_all :: proc(fd: posix.FD, message: string) -> bool {
	bytes := transmute([]byte)message
	written: int = 0
	for written < len(bytes) {
		remaining := len(bytes)-written
		count := posix.send(fd, raw_data(bytes[written:]), auto_cast remaining, {.NOSIGNAL})
		if count <= 0 {
			return false
		}
		written += int(count)
	}
	return true
}

mpv_command_locked :: proc(mpv: ^Mpv_Connection, command_json: string) -> Mpv_Command_Result {
	sync.mutex_lock(&mpv.response_mutex)
	if mpv.closed {
		sync.mutex_unlock(&mpv.response_mutex)
		return {}
	}
	mpv.next_request_id += 1
	request_id := mpv.next_request_id
	mpv.pending_id = request_id
	mpv.pending_done = false
	mpv.pending_result = {}
	sync.mutex_unlock(&mpv.response_mutex)

	message := fmt.aprintf("{{\"command\":%s,\"request_id\":%d}}\n", command_json, request_id)
	defer delete(message)
	if !mpv_send_all(mpv.fd, message) {
		return {}
	}

	sync.mutex_lock(&mpv.response_mutex)
	defer sync.mutex_unlock(&mpv.response_mutex)
	deadline_remaining := MPV_COMMAND_TIMEOUT
	for !mpv.pending_done && !mpv.closed {
		start := time.now()
		if !sync.cond_wait_with_timeout(&mpv.response_cond, &mpv.response_mutex, deadline_remaining) {
			break
		}
		elapsed := time.since(start)
		if elapsed >= deadline_remaining {
			break
		}
		deadline_remaining -= elapsed
	}
	if !mpv.pending_done || mpv.pending_id != request_id {
		return {}
	}
	return mpv.pending_result
}

mpv_command :: proc(mpv: ^Mpv_Connection, command_json: string) -> Mpv_Command_Result {
	sync.mutex_lock(&mpv.command_mutex)
	defer sync.mutex_unlock(&mpv.command_mutex)
	return mpv_command_locked(mpv, command_json)
}

mpv_apply_remote_seek :: proc(mpv: ^Mpv_Connection, position: f64) -> bool {
	sync.mutex_lock(&mpv.command_mutex)
	defer sync.mutex_unlock(&mpv.command_mutex)

	disabled := mpv_command_locked(mpv, `["disable_event","seek"]`)
	if !disabled.success {
		return false
	}
	reenabled := false
	defer if !reenabled {
		result := mpv_command_locked(mpv, `["enable_event","seek"]`)
		if !result.success {
			fmt.eprintln("client: failed to re-enable mpv seek events")
		}
	}

	seek_command := fmt.aprintf(`["seek",%.6f,"absolute+exact"]`, position)
	defer delete(seek_command)
	seek_result := mpv_command_locked(mpv, seek_command)
	enable_result := mpv_command_locked(mpv, `["enable_event","seek"]`)
	reenabled = enable_result.success
	return seek_result.success && enable_result.success
}

mpv_set_pause :: proc(mpv: ^Mpv_Connection, paused: bool) -> bool {
	command := fmt.aprintf(
		`["set_property","pause",%s]`,
		"true" if paused else "false",
	)
	defer delete(command)
	return mpv_command(mpv, command).success
}

mpv_get_time_position :: proc(mpv: ^Mpv_Connection) -> (f64, bool) {
	result := mpv_command(mpv, `["get_property","time-pos"]`)
	return result.data, result.success && result.has_data
}

mpv_observe_pause :: proc(mpv: ^Mpv_Connection) -> bool {
	return mpv_command(mpv, `["observe_property",1,"pause"]`).success
}

mpv_parse_response :: proc(mpv: ^Mpv_Connection, object: json.Object) -> bool {
	id_value, has_id := object["request_id"]
	if !has_id {
		return false
	}
	id, id_ok := id_value.(json.Integer)
	if !id_ok {
		return false
	}
	error_value, has_error := object["error"]
	if !has_error {
		return false
	}
	error_name, error_ok := error_value.(json.String)
	if !error_ok {
		return false
	}

	result := Mpv_Command_Result{success = string(error_name) == "success"}
	if data_value, has_data := object["data"]; has_data {
		#partial switch value in data_value {
		case json.Integer:
			result.has_data = true
			result.data = f64(value)
		case json.Float:
			result.has_data = true
			result.data = f64(value)
		}
	}

	sync.mutex_lock(&mpv.response_mutex)
	if i64(id) == mpv.pending_id {
		mpv.pending_result = result
		mpv.pending_done = true
		sync.cond_signal(&mpv.response_cond)
	}
	sync.mutex_unlock(&mpv.response_mutex)
	return true
}

mpv_handle_line :: proc(mpv: ^Mpv_Connection, line: string) {
	root: json.Value
	if json.unmarshal(transmute([]byte)line, &root, spec = .JSON) != nil {
		fmt.eprintln("client: received malformed JSON from mpv")
		return
	}
	defer json.destroy_value(root)
	object, ok := root.(json.Object)
	if !ok {
		return
	}
	if mpv_parse_response(mpv, object) {
		return
	}

	event_value, has_event := object["event"]
	if !has_event {
		return
	}
	event_name, event_ok := event_value.(json.String)
	if !event_ok {
		return
	}
	if mpv.client != nil {
		client_on_mpv_event(mpv.client, string(event_name), object)
	}
}

mpv_reader_loop :: proc(data: rawptr) {
	defer runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data)
	mpv := cast(^Mpv_Connection)data
	framer: Line_Framer
	framer_init(&framer)
	defer framer_destroy(&framer)
	buffer: [2048]byte

	for {
		count := posix.recv(mpv.fd, raw_data(buffer[:]), len(buffer), {})
		if count <= 0 {
			break
		}
		frames, frame_err := framer_push(&framer, buffer[:int(count)])
		if frame_err != .None {
			destroy_frames(frames)
			break
		}
		for frame in frames {
			if len(frame) > 0 {
				mpv_handle_line(mpv, frame)
			}
		}
		destroy_frames(frames)
	}

	sync.mutex_lock(&mpv.response_mutex)
	mpv.closed = true
	sync.cond_broadcast(&mpv.response_cond)
	sync.mutex_unlock(&mpv.response_mutex)
	if mpv.client != nil {
		client_on_mpv_disconnect(mpv.client)
	}
}

mpv_start_reader :: proc(mpv: ^Mpv_Connection) -> ^thread.Thread {
	return thread.create_and_start_with_data(
		rawptr(mpv),
		mpv_reader_loop,
		init_context = context,
		self_cleanup = false,
	)
}

mpv_close :: proc(mpv: ^Mpv_Connection) {
	if mpv.fd >= 0 {
		_ = posix.shutdown(mpv.fd, .RDWR)
		_ = posix.close(mpv.fd)
		mpv.fd = -1
	}
}
