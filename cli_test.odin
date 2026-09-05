package main

import "core:strings"
import "core:testing"

@(test)
cli_parses_server :: proc(t: ^testing.T) {
	args := []string{"playsync", "server", "--port", "9000"}
	options, err := parse_cli(args)
	testing.expect_value(t, err, "")
	testing.expect_value(t, options.command, Command_Kind.Server)
	testing.expect_value(t, options.host, DEFAULT_SERVER_HOST)
	testing.expect_value(t, options.port, 9000)
}

@(test)
cli_parses_client :: proc(t: ^testing.T) {
	args := []string{"playsync", "client", "--host", "example.test", "--port", "9000", "movie.mkv"}
	options, err := parse_cli(args)
	testing.expect_value(t, err, "")
	testing.expect_value(t, options.command, Command_Kind.Client)
	testing.expect_value(t, options.host, "example.test")
	testing.expect_value(t, options.movie_path, "movie.mkv")
}

@(test)
cli_client_uses_platform_default_mpv_path :: proc(t: ^testing.T) {
	args := []string{"playsync", "client", "--host", "example.test", "--port", "9000", "movie.mkv"}
	options, err := parse_cli(args)
	testing.expect_value(t, err, "")
	testing.expect_value(t, options.mpv_path, DEFAULT_MPV_PATH)
	when ODIN_OS == .Linux {
		testing.expect_value(t, options.mpv_path, "mpv")
	}
}

@(test)
cli_client_mpv_override_is_respected :: proc(t: ^testing.T) {
	args := []string{
		"playsync", "client", "--host", "example.test", "--port", "9000",
		"--mpv", "/custom/mpv", "--socket", "/tmp/custom-socket", "movie.mkv",
	}
	options, err := parse_cli(args)
	testing.expect_value(t, err, "")
	testing.expect_value(t, options.mpv_path, "/custom/mpv")
	testing.expect_value(t, options.socket_path, "/tmp/custom-socket")
}

@(test)
cli_rejects_bad_port :: proc(t: ^testing.T) {
	args := []string{"playsync", "server", "--port", "70000"}
	_, err := parse_cli(args)
	testing.expect(t, err != "")
}

@(test)
resolve_executable_looks_up_bare_name_on_path :: proc(t: ^testing.T) {
	resolved, ok := resolve_executable("sh")
	defer delete(resolved)
	testing.expect(t, ok)
	testing.expect(t, strings.has_suffix(resolved, "/sh"))
}

@(test)
resolve_executable_uses_slashed_path_verbatim :: proc(t: ^testing.T) {
	resolved, ok := resolve_executable("/bin/sh")
	defer delete(resolved)
	testing.expect(t, ok)
	testing.expect_value(t, resolved, "/bin/sh")
}

@(test)
resolve_executable_rejects_missing_command :: proc(t: ^testing.T) {
	_, ok := resolve_executable("playsync-no-such-binary-xyzzy")
	testing.expect(t, !ok)
}
