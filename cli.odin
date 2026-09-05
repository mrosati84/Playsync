package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

DEFAULT_SERVER_HOST :: "0.0.0.0"
DEFAULT_SOCKET_PATH :: "/tmp/mpv-socket"

when ODIN_OS == .Darwin {
	DEFAULT_MPV_PATH :: "/Applications/mpv.app/Contents/MacOS/mpv"
} else {
	// Linux ships mpv as a plain command; resolve it through PATH.
	DEFAULT_MPV_PATH :: "mpv"
}

Command_Kind :: enum {
	None,
	Server,
	Client,
	Help,
}

Options :: struct {
	command:     Command_Kind,
	host:        string,
	port:        int,
	mpv_path:    string,
	socket_path: string,
	movie_path:  string,
}

usage :: proc() {
	fmt.println("playsync - synchronize basic mpv playback events")
	fmt.println("")
	fmt.println("Usage:")
	fmt.println("  playsync server --port <port> [--host 0.0.0.0]")
	fmt.println("  playsync client --host <host> --port <port> [--mpv <path>] [--socket <path>] <movie>")
}

parse_cli :: proc(args: []string) -> (options: Options, error_message: string) {
	options.mpv_path = DEFAULT_MPV_PATH
	options.socket_path = DEFAULT_SOCKET_PATH

	if len(args) < 2 {
		return options, "expected server or client subcommand"
	}
	switch args[1] {
	case "server":
		options.command = .Server
		options.host = DEFAULT_SERVER_HOST
	case "client":
		options.command = .Client
	case "help", "--help", "-h":
		options.command = .Help
		return options, ""
	case:
		return options, fmt.tprintf("unknown subcommand %q", args[1])
	}

	i := 2
	for i < len(args) {
		arg := args[i]
		if strings.has_prefix(arg, "--") {
			if i+1 >= len(args) {
				return options, fmt.tprintf("missing value for %s", arg)
			}
			value := args[i+1]
			switch arg {
			case "--host":
				options.host = value
			case "--port":
				port, ok := strconv.parse_int(value)
				if !ok || port < 1 || port > 65535 {
					return options, "port must be an integer from 1 to 65535"
				}
				options.port = port
			case "--mpv":
				if options.command != .Client {
					return options, "--mpv is only valid for client"
				}
				options.mpv_path = value
			case "--socket":
				if options.command != .Client {
					return options, "--socket is only valid for client"
				}
				options.socket_path = value
			case:
				return options, fmt.tprintf("unknown option %s", arg)
			}
			i += 2
			continue
		}

		if options.command != .Client || options.movie_path != "" {
			return options, fmt.tprintf("unexpected positional argument %q", arg)
		}
		options.movie_path = arg
		i += 1
	}

	if options.port == 0 {
		return options, "--port is required"
	}
	if options.command == .Client {
		if options.host == "" {
			return options, "--host is required for client"
		}
		if options.movie_path == "" {
			return options, "movie path is required"
		}
	}
	return options, ""
}

// resolve_executable locates an executable and returns a freshly allocated path
// the caller owns. A value that contains a slash is checked as-is; a bare command
// name is looked up in PATH, matching how os.process_start locates the program.
resolve_executable :: proc(name: string, allocator := context.allocator) -> (resolved: string, ok: bool) {
	if name == "" {
		return "", false
	}
	if strings.index_byte(name, '/') >= 0 {
		if os.is_file(name) {
			return strings.clone(name, allocator), true
		}
		return "", false
	}

	path_env := os.get_env("PATH", context.temp_allocator)
	for dir in strings.split_iterator(&path_env, ":") {
		if dir == "" {
			continue
		}
		candidate := fmt.tprintf("%s/%s", dir, name)
		if os.is_file(candidate) {
			return strings.clone(candidate, allocator), true
		}
	}
	return "", false
}

validate_client_paths :: proc(options: ^Options) -> (error_message: string) {
	if _, err := os.stat(options.movie_path, context.temp_allocator); err != nil {
		return fmt.tprintf("movie does not exist: %s", options.movie_path)
	}
	resolved_mpv, mpv_ok := resolve_executable(options.mpv_path)
	if !mpv_ok {
		if strings.index_byte(options.mpv_path, '/') >= 0 {
			return fmt.tprintf("mpv does not exist: %s", options.mpv_path)
		}
		return fmt.tprintf("mpv not found on PATH: %s", options.mpv_path)
	}
	options.mpv_path = resolved_mpv
	if _, err := os.stat(options.socket_path, context.temp_allocator); err == nil {
		return fmt.tprintf("socket path already exists: %s", options.socket_path)
	}
	return ""
}
