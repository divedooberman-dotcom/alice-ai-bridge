package main

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
)

func TestVoiceMenu(t *testing.T) {
	prefsFile = filepath.Join(t.TempDir(), "prefs.json")
	userPrefs = map[string]prefs{}
	cases := []struct{ cmd, want string }{
		{"меню", "Голосовое меню"},
		{"умная модель", "модель умная"},
		{"сила высокая", "сила рассуждений высокая"},
		{"голос алена", "голос алена"},
		{"эффект мегафон", "эффект мегафон"},
		{"какие настройки", "модель умная, сила рассуждений высокая"},
	}
	for _, c := range cases {
		got, ok := voiceMenu("u1", c.cmd)
		if !ok || !strings.Contains(got, c.want) {
			t.Fatalf("%q -> %q (ok=%v), want %q", c.cmd, got, ok, c.want)
		}
	}
	if _, ok := voiceMenu("u1", "какая сила тяжести на луне"); ok {
		t.Fatal("a question must not be a menu command")
	}
	if _, ok := voiceMenu("u1", "расскажи про модель солнечной системы"); ok {
		t.Fatal("a question about a model must go to the LLM")
	}
	p := prefsOf("u1")
	if m, e := requestModel(withPrefs(context.Background(), p)); m != "gpt-6.1-sol" || e != "high" {
		t.Fatalf("requestModel = %s %s", m, e)
	}
	if got := tts("Привет.", p); got != `<speaker effect="megaphone"><speaker voice="alena">Привет.` {
		t.Fatalf("tts = %q", got)
	}
	userPrefs = map[string]prefs{}
	loadPrefs()
	if prefsOf("u1").Voice != "alena" {
		t.Fatal("prefs not persisted")
	}
}
