package main

import "core:strings"
import "core:testing"

@(test)
protocol_round_trip_pause :: proc(t: ^testing.T) {
	line := encode_protocol_event(Playback_Event{kind = .Pause, paused = true})
	defer delete(line)
	event, err := parse_protocol_event(transmute([]byte)strings.trim_space(line))
	testing.expect_value(t, err, Protocol_Error.None)
	testing.expect_value(t, event.kind, Event_Kind.Pause)
	testing.expect_value(t, event.paused, true)
}

@(test)
protocol_round_trip_seek :: proc(t: ^testing.T) {
	line := encode_protocol_event(Playback_Event{kind = .Seek, position = 123.456})
	defer delete(line)
	event, err := parse_protocol_event(transmute([]byte)strings.trim_space(line))
	testing.expect_value(t, err, Protocol_Error.None)
	testing.expect_value(t, event.kind, Event_Kind.Seek)
	testing.expect(t, event.position > 123.455 && event.position < 123.457)
}

@(test)
protocol_rejects_invalid_messages :: proc(t: ^testing.T) {
	missing_pause: string = `{"version":1,"type":"pause"}`
	bad_version: string = `{"version":2,"type":"pause","paused":true}`
	bad_position: string = `{"version":1,"type":"seek","position":-1}`
	_, err := parse_protocol_event(transmute([]byte)missing_pause)
	testing.expect_value(t, err, Protocol_Error.Missing_Paused)
	_, err = parse_protocol_event(transmute([]byte)bad_version)
	testing.expect_value(t, err, Protocol_Error.Unsupported_Version)
	_, err = parse_protocol_event(transmute([]byte)bad_position)
	testing.expect_value(t, err, Protocol_Error.Invalid_Position)
}

@(test)
protocol_round_trip_sourced_event :: proc(t: ^testing.T) {
	line := encode_protocol_event(Playback_Event{
		kind = .Seek,
		position = 9.25,
		client_id = 7,
	})
	defer delete(line)
	event, err := parse_protocol_event(transmute([]byte)strings.trim_space(line))
	testing.expect_value(t, err, Protocol_Error.None)
	testing.expect_value(t, event.client_id, u64(7))
}

@(test)
protocol_parses_welcome :: proc(t: ^testing.T) {
	line := encode_welcome(12)
	defer delete(line)
	client_id, matched, err := parse_welcome(transmute([]byte)strings.trim_space(line))
	testing.expect(t, matched)
	testing.expect_value(t, err, Protocol_Error.None)
	testing.expect_value(t, client_id, u64(12))
}

@(test)
playback_logs_identify_client_and_action :: proc(t: ^testing.T) {
	paused := format_playback_log("server", 2, Playback_Event{kind = .Pause, paused = true})
	defer delete(paused)
	played := format_playback_log("client", 3, Playback_Event{kind = .Pause}, is_local = true)
	defer delete(played)
	sought := format_playback_log("client", 4, Playback_Event{kind = .Seek, position = 65.125})
	defer delete(sought)
	testing.expect_value(t, paused, "server: client 2 paused")
	testing.expect_value(t, played, "client: client 3 (you) played")
	testing.expect_value(t, sought, "client: client 4 sought to 65.125 seconds")
}
