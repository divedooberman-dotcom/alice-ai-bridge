package main

import (
	"context"
	"testing"
	"time"
)

func TestGraceWaitsForFirstSentence(t *testing.T) {
	old := grace
	grace = 800 * time.Millisecond
	defer func() { grace = old }()
	a := &answer{changed: make(chan struct{}), finished: make(chan struct{})}
	go func() {
		time.Sleep(300 * time.Millisecond)
		a.append("Сорок два.")
		time.Sleep(50 * time.Millisecond)
		a.append(" Дальше идёт длинное продолжение")
	}()
	start := time.Now()
	chunk, more, _ := a.next(context.Background(), 100*time.Millisecond)
	if chunk != "Сорок два." || !more {
		t.Fatalf("chunk=%q more=%v", chunk, more)
	}
	if el := time.Since(start); el > 700*time.Millisecond {
		t.Fatalf("waited %v, should stop at the first sentence", el)
	}
}
