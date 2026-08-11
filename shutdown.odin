package main

import "base:intrinsics"
import "core:c"
import "core:c/libc"
import "core:sys/posix"

shutdown_requested: libc.sig_atomic_t
server_listener_fd: libc.sig_atomic_t = -1

shutdown_signal_handler :: proc "c" (signal: c.int) {
	intrinsics.atomic_store(&shutdown_requested, 1)
	fd := intrinsics.atomic_exchange(&server_listener_fd, libc.sig_atomic_t(-1))
	if fd >= 0 {
		_ = posix.close(posix.FD(fd))
	}
}

register_server_listener :: proc(fd: posix.FD) {
	intrinsics.atomic_store(&server_listener_fd, libc.sig_atomic_t(fd))
}

clear_server_listener :: proc() {
	intrinsics.atomic_store(&server_listener_fd, libc.sig_atomic_t(-1))
}

install_shutdown_handlers :: proc() {
	libc.signal(libc.SIGINT, shutdown_signal_handler)
	libc.signal(libc.SIGTERM, shutdown_signal_handler)
}

should_shutdown :: proc() -> bool {
	return intrinsics.atomic_load(&shutdown_requested) == 1
}
