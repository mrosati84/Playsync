package main

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"

PROTOCOL_VERSION :: 1
MAX_FRAME_BYTES  :: 4096

Event_Kind :: enum {
	Pause,
	Seek,
}

Playback_Event :: struct {
	kind:     Event_Kind,
	paused:   bool,
	position: f64,
	client_id: u64,
}

Protocol_Error :: enum {
	None,
	Invalid_JSON,
	Expected_Object,
	Missing_Version,
	Unsupported_Version,
	Missing_Type,
	Unknown_Type,
	Missing_Paused,
	Invalid_Paused,
	Missing_Position,
	Invalid_Position,
	Missing_Client_ID,
	Invalid_Client_ID,
}

protocol_error_string :: proc(err: Protocol_Error) -> string {
	switch err {
	case .None:                return "no error"
	case .Invalid_JSON:        return "invalid JSON"
	case .Expected_Object:     return "expected a JSON object"
	case .Missing_Version:     return "missing integer version"
	case .Unsupported_Version: return "unsupported protocol version"
	case .Missing_Type:        return "missing string type"
	case .Unknown_Type:        return "unknown event type"
	case .Missing_Paused:      return "missing paused field"
	case .Invalid_Paused:      return "paused must be a boolean"
	case .Missing_Position:    return "missing position field"
	case .Invalid_Position:    return "position must be a finite non-negative number"
	case .Missing_Client_ID:   return "missing client_id field"
	case .Invalid_Client_ID:   return "client_id must be a positive integer"
	}
	return "unknown protocol error"
}

parse_protocol_event :: proc(data: []byte) -> (event: Playback_Event, err: Protocol_Error) {
	root: json.Value
	if json.unmarshal(data, &root, spec = .JSON) != nil {
		return {}, .Invalid_JSON
	}
	defer json.destroy_value(root)

	object, ok := root.(json.Object)
	if !ok {
		return {}, .Expected_Object
	}

	version_value, found := object["version"]
	if !found {
		return {}, .Missing_Version
	}
	version, version_ok := version_value.(json.Integer)
	if !version_ok {
		return {}, .Missing_Version
	}
	if version != PROTOCOL_VERSION {
		return {}, .Unsupported_Version
	}

	type_value, type_found := object["type"]
	if !type_found {
		return {}, .Missing_Type
	}
	type_name, type_ok := type_value.(json.String)
	if !type_ok {
		return {}, .Missing_Type
	}

	client_id: u64
	if client_id_value, client_id_found := object["client_id"]; client_id_found {
		parsed_id, client_id_ok := client_id_value.(json.Integer)
		if !client_id_ok || parsed_id <= 0 {
			return {}, .Invalid_Client_ID
		}
		client_id = u64(parsed_id)
	}

	switch string(type_name) {
	case "pause":
		paused_value, paused_found := object["paused"]
		if !paused_found {
			return {}, .Missing_Paused
		}
		paused, paused_ok := paused_value.(json.Boolean)
		if !paused_ok {
			return {}, .Invalid_Paused
		}
		return Playback_Event{kind = .Pause, paused = bool(paused), client_id = client_id}, .None

	case "seek":
		position_value, position_found := object["position"]
		if !position_found {
			return {}, .Missing_Position
		}
		position: f64
		#partial switch value in position_value {
		case json.Integer:
			position = f64(value)
		case json.Float:
			position = f64(value)
		case:
			return {}, .Invalid_Position
		}
		if position < 0 || math.is_nan(position) || math.is_inf(position) {
			return {}, .Invalid_Position
		}
		return Playback_Event{kind = .Seek, position = position, client_id = client_id}, .None
	}

	return {}, .Unknown_Type
}

encode_protocol_event :: proc(event: Playback_Event, allocator := context.allocator) -> (line: string) {
	switch event.kind {
	case .Pause:
		if event.client_id > 0 {
			return fmt.aprintf(
				"{{\"version\":%d,\"type\":\"pause\",\"paused\":%s,\"client_id\":%d}}\n",
				PROTOCOL_VERSION,
				"true" if event.paused else "false",
				event.client_id,
				allocator = allocator,
			)
		}
		return fmt.aprintf(
			"{{\"version\":%d,\"type\":\"pause\",\"paused\":%s}}\n",
			PROTOCOL_VERSION,
			"true" if event.paused else "false",
			allocator = allocator,
		)
	case .Seek:
		if event.client_id > 0 {
			return fmt.aprintf(
				"{{\"version\":%d,\"type\":\"seek\",\"position\":%.6f,\"client_id\":%d}}\n",
				PROTOCOL_VERSION,
				event.position,
				event.client_id,
				allocator = allocator,
			)
		}
		return fmt.aprintf(
			"{{\"version\":%d,\"type\":\"seek\",\"position\":%.6f}}\n",
			PROTOCOL_VERSION,
			event.position,
			allocator = allocator,
		)
	}
	return strings.clone("", allocator)
}

encode_welcome :: proc(client_id: u64, allocator := context.allocator) -> string {
	return fmt.aprintf(
		"{{\"version\":%d,\"type\":\"welcome\",\"client_id\":%d}}\n",
		PROTOCOL_VERSION,
		client_id,
		allocator = allocator,
	)
}

parse_welcome :: proc(data: []byte) -> (client_id: u64, matched: bool, err: Protocol_Error) {
	root: json.Value
	if json.unmarshal(data, &root, spec = .JSON) != nil {
		return 0, false, .Invalid_JSON
	}
	defer json.destroy_value(root)
	object, object_ok := root.(json.Object)
	if !object_ok {
		return 0, false, .Expected_Object
	}
	type_value, type_found := object["type"]
	if !type_found {
		return 0, false, .Missing_Type
	}
	type_name, type_ok := type_value.(json.String)
	if !type_ok {
		return 0, false, .Missing_Type
	}
	if string(type_name) != "welcome" {
		return 0, false, .None
	}
	matched = true
	version_value, version_found := object["version"]
	if !version_found {
		return 0, true, .Missing_Version
	}
	version, version_ok := version_value.(json.Integer)
	if !version_ok {
		return 0, true, .Missing_Version
	}
	if version != PROTOCOL_VERSION {
		return 0, true, .Unsupported_Version
	}
	client_id_value, client_id_found := object["client_id"]
	if !client_id_found {
		return 0, true, .Missing_Client_ID
	}
	parsed_id, client_id_ok := client_id_value.(json.Integer)
	if !client_id_ok || parsed_id <= 0 {
		return 0, true, .Invalid_Client_ID
	}
	return u64(parsed_id), true, .None
}

format_playback_log :: proc(
	scope: string,
	client_id: u64,
	event: Playback_Event,
	is_local := false,
	allocator := context.allocator,
) -> string {
	if is_local {
		switch event.kind {
		case .Pause:
			return fmt.aprintf(
				"%s: client %d (you) %s",
				scope,
				client_id,
				"paused" if event.paused else "played",
				allocator = allocator,
			)
		case .Seek:
			return fmt.aprintf(
				"%s: client %d (you) sought to %.3f seconds",
				scope,
				client_id,
				event.position,
				allocator = allocator,
			)
		}
	}
	switch event.kind {
	case .Pause:
		return fmt.aprintf(
			"%s: client %d %s",
			scope,
			client_id,
			"paused" if event.paused else "played",
			allocator = allocator,
		)
	case .Seek:
		return fmt.aprintf(
			"%s: client %d sought to %.3f seconds",
			scope,
			client_id,
			event.position,
			allocator = allocator,
		)
	}
	return strings.clone("", allocator)
}

log_playback_event :: proc(scope: string, client_id: u64, event: Playback_Event, is_local := false) {
	line := format_playback_log(scope, client_id, event, is_local)
	defer delete(line)
	fmt.println(line)
}
