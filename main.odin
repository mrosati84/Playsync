package main

import "core:fmt"
import "core:os"

main :: proc() {
	install_shutdown_handlers()
	options, cli_error := parse_cli(os.args)
	if cli_error != "" {
		fmt.eprintln("playsync:", cli_error)
		usage()
		os.exit(2)
	}
	if options.command == .Help {
		usage()
		return
	}

	#partial switch options.command {
	case .Server:
		if !run_server(options) {
			os.exit(1)
		}
	case .Client:
		if path_error := validate_client_paths(&options); path_error != "" {
			fmt.eprintln("playsync:", path_error)
			os.exit(1)
		}
		if !run_client(options) {
			os.exit(1)
		}
	case:
		unreachable()
	}
}
