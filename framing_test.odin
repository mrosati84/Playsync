package main

import "core:testing"

@(test)
framer_handles_fragmented_and_coalesced_messages :: proc(t: ^testing.T) {
	framer: Line_Framer
	framer_init(&framer)
	defer framer_destroy(&framer)

	first: string = "one\ntw"
	frames, err := framer_push(&framer, transmute([]byte)first)
	defer destroy_frames(frames)
	testing.expect_value(t, err, Frame_Error.None)
	testing.expect_value(t, len(frames), 1)
	testing.expect_value(t, frames[0], "one")

	second: string = "o\r\nthree\n"
	frames2, err2 := framer_push(&framer, transmute([]byte)second)
	defer destroy_frames(frames2)
	testing.expect_value(t, err2, Frame_Error.None)
	testing.expect_value(t, len(frames2), 2)
	testing.expect_value(t, frames2[0], "two")
	testing.expect_value(t, frames2[1], "three")
}

@(test)
framer_rejects_oversized_message :: proc(t: ^testing.T) {
	framer: Line_Framer
	framer_init(&framer)
	defer framer_destroy(&framer)
	data := make([]byte, MAX_FRAME_BYTES+1)
	defer delete(data)
	frames, err := framer_push(&framer, data)
	defer destroy_frames(frames)
	testing.expect_value(t, err, Frame_Error.Too_Large)
}
