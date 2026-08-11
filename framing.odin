package main

import "core:strings"

Frame_Error :: enum {
	None,
	Too_Large,
}

Line_Framer :: struct {
	buffer: [dynamic]byte,
}

framer_init :: proc(framer: ^Line_Framer, allocator := context.allocator) {
	framer.buffer = make([dynamic]byte, 0, 256, allocator)
}

framer_destroy :: proc(framer: ^Line_Framer) {
	delete(framer.buffer)
	framer.buffer = nil
}

destroy_frames :: proc(frames: [dynamic]string) {
	for frame in frames {
		delete(frame)
	}
	delete(frames)
}

framer_push :: proc(
	framer: ^Line_Framer,
	data: []byte,
	allocator := context.allocator,
) -> (frames: [dynamic]string, err: Frame_Error) {
	frames = make([dynamic]string, 0, allocator)
	append(&framer.buffer, ..data)

	start := 0
	for i := 0; i < len(framer.buffer); i += 1 {
		if framer.buffer[i] != '\n' {
			if i-start >= MAX_FRAME_BYTES {
				return frames, .Too_Large
			}
			continue
		}

		end := i
		if end > start && framer.buffer[end-1] == '\r' {
			end -= 1
		}
		if end-start > MAX_FRAME_BYTES {
			return frames, .Too_Large
		}
		frame := strings.clone(string(framer.buffer[start:end]), allocator)
		append(&frames, frame)
		start = i+1
	}

	if start > 0 {
		remaining := len(framer.buffer)-start
		if remaining > 0 {
			copy(framer.buffer[:remaining], framer.buffer[start:])
		}
		resize(&framer.buffer, remaining)
	}
	if len(framer.buffer) > MAX_FRAME_BYTES {
		return frames, .Too_Large
	}
	return frames, .None
}
