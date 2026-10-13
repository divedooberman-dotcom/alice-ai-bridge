package main

// Tutorial: «как пользоваться суперинтеллектом» walks through every voice command and plays one
// phrase in different voices and effects. One step per reply (Alice speaks ≤1024 chars at a time),
// «дальше»/«да» for the next step, «стоп обучение» to leave.

import (
	"strings"
	"sync"
)

type step struct{ text, tts string }

const sample = "Привет, Руслан! Я Супер интеллект."

func voiceDemo() step {
	// Alice drops a reply that contains <speaker voice="…"> (tested on the Midi, Oct 2026):
	// the voice is a skill setting in the Dialogs console, so this step only explains it.
	text := "Шаг 3. Голос. Голос навыка один, он выбирается в настройках навыка в консоли Яндекса: " +
		"переключить его голосом нельзя, Яндекс это не поддерживает. Зато можно менять эффекты — " +
		"об этом следующий шаг. Дальше?"
	return step{text: text}
}

func effectDemo() step {
	return step{text: "Шаг 4. Голос и эффекты. Яндекс не озвучивает в этом навыке смену голоса и эффекты: " +
		"такой ответ колонка просто проглатывает. Поэтому я говорю одним голосом, который задан в настройках навыка. Дальше?"}
}

var tutorialSteps = []step{
	{text: "Обучение Супер интеллекту, шесть коротких шагов. Говори «дальше», чтобы перейти к следующему, " +
		"или «стоп обучение», чтобы выйти. Шаг 1. Как спрашивать. Запусти навык фразой «Алиса, запусти навык " +
		"Супер интеллект» и просто задавай вопросы, как человеку. Короткий ответ прозвучит сразу. Длинный — частями: " +
		"после части я спрошу «Продолжить?», а ты скажи «дальше» или «да». Если прозвучало «Ещё думаю» — тоже скажи " +
		"«дальше». Новый вопрос прерывает старый ответ. Дальше?"},
	{text: "Шаг 2. Модели и сила. «Быстрая модель» — отвечает быстрее всех, для обычных вопросов. «Умная модель» — " +
		"думает глубже, но дольше. «Модель астра» — ещё одна сильная модель. Сила рассуждений: «сила минимальная», " +
		"«низкая», «средняя», «высокая», «максимальная» или «сила автоматическая». Чем сильнее думаю, тем чаще " +
		"придётся сказать «дальше». Дальше?"},
	voiceDemo(),
	effectDemo(),
	{text: "Шаг 5. Полезное. «Какие настройки» — что включено сейчас. «Меню» — короткий список команд. «Забудь» или " +
		"«новый диалог» — начать разговор с чистого листа. «Хватит» — выйти из навыка. Я ищу в интернете, когда " +
		"спрашиваешь о свежем: новости, курс, погода. Я помню факты о тебе, а все вопросы и ответы дублируются в " +
		"Телеграм. Дальше?"},
	{text: "Шаг 6. Что важно знать. Некоторые фразы Алиса забирает себе и мне не передаёт: «Алиса, громче», " +
		"«тише», «Алиса, хватит», «Алиса, вернись». Если колонка говорит «навык не отвечает» — повтори вопрос. " +
		"Если «у меня такого навыка нет» — Руслан, это сбой у Яндекса, напиши мне в Claude. Обучение закончено. " +
		"Задавай вопрос!"},
}

var (
	tutMu  sync.Mutex
	tutPos = map[string]int{} // session -> next step index
	tutTTS sync.Map           // session -> tts override for the reply being built
)

func isTutorialStart(cmd string) bool {
	c := strings.ReplaceAll(cmd, "супер интеллект", "суперинтеллект")
	words := strings.Fields(c)
	return len(words) <= 6 && (strings.Contains(c, "как пользоваться") || strings.Contains(c, "инструкци") ||
		strings.Contains(c, "обучени") || strings.Contains(c, "научи меня"))
}

// tutorial returns the next tutorial reply for this session; ok=false when not in a tutorial.
func tutorial(sid, cmd string) (string, bool) {
	tutMu.Lock()
	defer tutMu.Unlock()
	pos, active := tutPos[sid]
	switch {
	case isTutorialStart(cmd):
		pos, active = 0, true
	case !active:
		return "", false
	case cmd == "стоп обучение" || cmd == "выйти из обучения" || cmd == "хватит обучение":
		delete(tutPos, sid)
		return "Обучение закончено. Задавай вопрос!", true
	case cmd == "дальше" || cmd == "да" || cmd == "давай" || cmd == "продолжи" || cmd == "продолжай" || cmd == "ещё" || cmd == "еще":
	case cmd == "повтори":
		pos = max(pos-1, 0)
	default:
		delete(tutPos, sid) // any other phrase: leave the tutorial and handle it normally
		return "", false
	}
	s := tutorialSteps[pos]
	if pos+1 < len(tutorialSteps) {
		tutPos[sid] = pos + 1
	} else {
		delete(tutPos, sid)
	}
	if s.tts != "" {
		tutTTS.Store(sid, s.tts)
	}
	return s.text, true
}

// takeTTS returns (and clears) a tts override set while building this session's reply.
func takeTTS(sid string) (string, bool) {
	v, ok := tutTTS.LoadAndDelete(sid)
	if !ok {
		return "", false
	}
	return v.(string), true
}
