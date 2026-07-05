package main

import "testing"

func TestGameIDFromURL(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		want string
	}{
		{
			name: "encounter play url",
			raw:  "https://moscow.en.cx/gameengines/encounter/play/82420?json=1&lang=ru",
			want: "82420",
		},
		{
			name: "mobile encounter play url",
			raw:  "https://m.svk.en.cx/gameengines/encounter/play/82448?lang=ru",
			want: "82448",
		},
		{
			name: "missing game id",
			raw:  "https://svk.en.cx/home/?json=1",
			want: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := gameIDFromURL(tt.raw); got != tt.want {
				t.Fatalf("gameIDFromURL(%q) = %q, want %q", tt.raw, got, tt.want)
			}
		})
	}
}

func TestSanitizeFilename(t *testing.T) {
	got := sanitizeFilename("2026-07-05 21:48:10_moscow.en.cx_game-82420_id/with spaces")
	want := "2026-07-05-21-48-10_moscow.en.cx_game-82420_id-with-spaces"
	if got != want {
		t.Fatalf("sanitizeFilename() = %q, want %q", got, want)
	}
}
