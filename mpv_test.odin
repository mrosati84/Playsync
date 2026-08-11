package main

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:sys/posix"
import "core:testing"
import "core:thread"

Fake_Mpv :: struct {
	fd:       posix.FD,
	received: [3]string,
	fail_seek: bool,
	enable_before_restart: bool,
}

fake_mpv_read_line :: proc(fd: posix.FD, buffer: []byte) -> (line: string, ok: bool) {
	length := 0
	for length < len(buffer) {
		count := posix.recv(fd, raw_data(buffer[length:]), 1, {})
		if count != 1 {
			return "", false
		}
		if buffer[length] == '\n' {
			return string(buffer[:length]), true
		}
		length += 1
	}
	return "", false
}

fake_mpv_loop :: proc(data: rawptr) {
	defer runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data)
	fake := cast(^Fake_Mpv)data
	buffer: [512]byte
	for index in 0..<3 {
		line, ok := fake_mpv_read_line(fake.fd, buffer[:])
		if !ok {
			return
		}
		fake.received[index] = strings.clone(line)
		error_name := "failure" if fake.fail_seek && index == 1 else "success"
		response := fmt.aprintf(
			"{{\"error\":\"%s\",\"request_id\":%d}}\n",
			error_name,
			index+1,
		)
		_ = mpv_send_all(fake.fd, response)
		delete(response)
		if index == 1 && error_name == "success" {
			poll_fd := posix.pollfd {
				fd     = fake.fd,
				events = {.IN},
			}
			fake.enable_before_restart = posix.poll(&poll_fd, 1, 50) > 0
			_ = mpv_send_all(fake.fd, "{\"event\":\"playback-restart\"}\n")
		}
	}
}

run_fake_seek_transaction :: proc(t: ^testing.T, fail_seek: bool) -> (ok: bool, fake: Fake_Mpv) {
	fds: [2]posix.FD
	testing.expect_value(t, posix.socketpair(.UNIX, .STREAM, .IP, &fds), posix.result.OK)

	mpv := Mpv_Connection{fd = fds[0]}
	reader := mpv_start_reader(&mpv)
	testing.expect(t, reader != nil)
	fake = Fake_Mpv{fd = fds[1], fail_seek = fail_seek}
	fake_thread := thread.create_and_start_with_data(
		rawptr(&fake),
		fake_mpv_loop,
		init_context = context,
		self_cleanup = false,
	)
	testing.expect(t, fake_thread != nil)

	ok = mpv_apply_remote_seek(&mpv, 42.5)
	thread.join(fake_thread)
	thread.destroy(fake_thread)
	mpv_close(&mpv)
	thread.join(reader)
	thread.destroy(reader)
	_ = posix.close(fake.fd)
	return
}

@(test)
remote_seek_masks_and_restores_seek_events :: proc(t: ^testing.T) {
	ok, fake := run_fake_seek_transaction(t, false)
	testing.expect(t, ok)

	testing.expect(t, strings.contains(fake.received[0], `"disable_event","seek"`))
	testing.expect(t, strings.contains(fake.received[1], `"seek",42.500000,"absolute+exact"`))
	testing.expect(t, strings.contains(fake.received[2], `"enable_event","seek"`))
	testing.expect(t, !fake.enable_before_restart)
	for line in fake.received {
		delete(line)
	}
}

@(test)
remote_seek_restores_events_after_seek_failure :: proc(t: ^testing.T) {
	ok, fake := run_fake_seek_transaction(t, true)
	testing.expect(t, !ok)
	testing.expect(t, strings.contains(fake.received[0], `"disable_event","seek"`))
	testing.expect(t, strings.contains(fake.received[2], `"enable_event","seek"`))
	for line in fake.received {
		delete(line)
	}
}
