package main

import "testing"

func TestPhrases(t *testing.T) {
	for in, want := range map[string]string{
		"алиса хватит": "хватит", "спроси у супер интеллект какая погода": "какая погода",
		"суперинтендант сколько времени": "сколько времени", "алиса": "", "почему небо голубое": "почему небо голубое",
	} {
		if got := stripPrefix(in); got != want {
			t.Errorf("stripPrefix(%q) = %q, want %q", in, got, want)
		}
	}
	if !exitWords[stripPrefix("алиса хватит")] || !leaveFor("включи музыку") || leaveFor("почему музыка грустная") {
		t.Fatal("exit / leave")
	}
	if !isActivation("запусти навык чат джи пи ти") || !isActivation("включи навык супер интеллект") || isActivation("что такое суперинтеллект в фантастике") {
		t.Fatal("activation")
	}
}
