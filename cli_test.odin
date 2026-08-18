package main

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
cli_rejects_bad_port :: proc(t: ^testing.T) {
	args := []string{"playsync", "server", "--port", "70000"}
	_, err := parse_cli(args)
	testing.expect(t, err != "")
}
