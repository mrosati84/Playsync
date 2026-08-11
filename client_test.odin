package main

import "core:testing"

@(test)
remote_pause_notification_is_suppressed :: proc(t: ^testing.T) {
	client := Client_State{
		remote_pause_pending = true,
		remote_pause_value = true,
	}
	client_on_pause_change(&client, true)
	testing.expect_value(t, client.remote_pause_pending, false)
	testing.expect_value(t, client.have_last_pause, true)
	testing.expect_value(t, client.last_pause, true)
}

@(test)
initial_pause_notification_is_baseline_only :: proc(t: ^testing.T) {
	client := Client_State{ignore_initial_pause = true}
	client_on_pause_change(&client, true)
	testing.expect_value(t, client.ignore_initial_pause, false)
	testing.expect_value(t, client.have_last_pause, true)
}
