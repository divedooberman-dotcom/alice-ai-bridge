package main

import (
	"strings"
	"testing"
	"unicode/utf8"
)

func TestTutorialWalksAllStepsWithinAliceLimits(t *testing.T) {
	sid := "s1"
	text, ok := tutorial(sid, "как пользоваться суперинтеллектом")
	if !ok || !strings.HasPrefix(text, "Обучение") {
		t.Fatalf("start: %q %v", text, ok)
	}
	n := 1
	for {
		if tts, ok := takeTTS(sid); ok && utf8.RuneCountInString(tts) > 1024 {
			t.Fatalf("step %d tts is %d chars", n, utf8.RuneCountInString(tts))
		}
		if utf8.RuneCountInString(text) > 1024 {
			t.Fatalf("step %d text is %d chars", n, utf8.RuneCountInString(text))
		}
		if !strings.HasSuffix(text, "Дальше?") {
			break
		}
		text, ok = tutorial(sid, "дальше")
		if !ok {
			t.Fatalf("step %d: tutorial ended early", n)
		}
		n++
	}
	if n != len(tutorialSteps) {
		t.Fatalf("walked %d steps, want %d", n, len(tutorialSteps))
	}
	if _, ok := tutorial(sid, "дальше"); ok {
		t.Fatal("after the last step «дальше» belongs to answers again")
	}
	tutorial(sid, "обучение")
	if _, ok := tutorial(sid, "сколько будет два плюс два"); ok {
		t.Fatal("a question leaves the tutorial")
	}
	if !isTutorialStart("расскажи инструкцию") || isTutorialStart("найди инструкцию к ноутбуку сёрфейс лэптоп ультра пожалуйста") {
		t.Fatal("instruction phrases")
	}
	if !isTutorialStart("как пользоваться супер интеллектом") {
		t.Fatal("two-word name must start the tutorial")
	}
}
