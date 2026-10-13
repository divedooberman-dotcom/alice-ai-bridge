package main

// Voice menu: per-user model, reasoning effort, speaker voice and effect, switched by voice.
//
// Model and effort go to the LLM request (model / reasoning_effort). Voice and effect go into
// response.tts as <speaker ...> tags: effects are documented by Yandex Dialogs (they work for all
// voices except Alice's); <speaker voice="..."> comes from the same SpeechKit markup but is not
// documented for skills, so it may be ignored by Alice — the skill voice set in the console stays.

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
)

type prefs struct {
	Model  string `json:"model,omitempty"`
	Effort string `json:"effort,omitempty"`
	Voice  string `json:"voice,omitempty"`
	Effect string `json:"effect,omitempty"`
}

type option struct{ key, title string }

var (
	// spoken names → model id; the first one is what LLM_MODEL usually is
	models = []struct {
		id    string
		words []string
		title string
	}{
		{"gpt-6-luna", []string{"быстрая", "быструю", "луна"}, "быстрая"},
		{"gpt-6.1-sol", []string{"умная", "умную", "сол", "соль"}, "умная"},
		{"gpt-6-astra", []string{"астра", "самая умная", "самую умную"}, "астра"},
	}
	efforts = []struct {
		id    string
		words []string
		title string
	}{
		{"none", []string{"минимальная", "минимальную", "без рассуждений"}, "минимальная"},
		{"low", []string{"низкая", "низкую"}, "низкая"},
		{"medium", []string{"средняя", "среднюю"}, "средняя"},
		{"high", []string{"высокая", "высокую"}, "высокая"},
		{"xhigh", []string{"максимальная", "максимальную"}, "максимальная"},
		{"", []string{"автоматическая", "автоматическую", "обычная", "обычную"}, "автоматическая"},
	}
	voices = map[string]string{
		"захар": "zahar", "алена": "alena", "филипп": "filipp", "эрмил": "ermil",
		"джейн": "jane", "омаж": "omazh", "мадирус": "madirus", "даша": "dasha", "юля": "julia",
		"лера": "lera", "маша": "masha", "марина": "marina", "александр": "alexander",
		"кирилл": "kirill", "антон": "anton",
	}
	effects = map[string]string{
		"мегафон": "megaphone", "из за стены": "behind_the_wall", "стена": "behind_the_wall",
		"хомяк": "hamster", "низкий": "pitch_down", "психоделический": "psychodelic",
		"пульс": "pulse", "вокзал": "train_announce",
	}
	menu = "Голосовое меню. Модели: «быстрая модель», «умная модель», «модель астра». " +
		"Сила рассуждений: «сила минимальная», «низкая», «средняя», «высокая», «максимальная». " +
		"Голос: «голос Алена», «голос Филипп», «голос Эрмил», «голос Захар» и другие, «голос по умолчанию». " +
		"Эффект: «эффект мегафон», «хомяк», «из-за стены», «вокзал», «без эффекта». " +
		"«Какие настройки» — что включено сейчас. «Как пользоваться суперинтеллектом» — обучение с примерами голосов."

	prefsMu   sync.Mutex
	userPrefs = map[string]prefs{}
	prefsFile = getenv("PREFS_FILE", "")
)

type prefsKeyT struct{}

var prefsKey prefsKeyT

func loadPrefs() {
	if prefsFile == "" {
		return
	}
	if b, err := os.ReadFile(prefsFile); err == nil {
		prefsMu.Lock()
		_ = json.Unmarshal(b, &userPrefs)
		prefsMu.Unlock()
	}
}

func savePrefsLocked() {
	if prefsFile == "" {
		return
	}
	b, _ := json.Marshal(userPrefs)
	tmp := prefsFile + ".tmp"
	if err := os.MkdirAll(filepath.Dir(prefsFile), 0o750); err == nil {
		if err = os.WriteFile(tmp, b, 0o640); err == nil {
			err = os.Rename(tmp, prefsFile)
		}
		if err != nil {
			log.Println("prefs save:", err)
		}
	}
}

func prefsOf(uid string) prefs {
	prefsMu.Lock()
	defer prefsMu.Unlock()
	return userPrefs[uid]
}

func updatePrefs(uid string, f func(*prefs)) prefs {
	prefsMu.Lock()
	defer prefsMu.Unlock()
	p := userPrefs[uid]
	f(&p)
	userPrefs[uid] = p
	savePrefsLocked()
	return p
}

func describe(p prefs) string {
	m := "быстрая"
	for _, x := range models {
		if x.id == p.Model {
			m = x.title
		}
	}
	e := "автоматическая"
	for _, x := range efforts {
		if x.id == p.Effort && p.Effort != "" {
			e = x.title
		}
	}
	v := "как в настройках навыка"
	for name, id := range voices {
		if id == p.Voice {
			v = name
		}
	}
	fx := "нет"
	for name, id := range effects {
		if id == p.Effect {
			fx = name
		}
	}
	return fmt.Sprintf("Сейчас: модель %s, сила рассуждений %s, голос %s, эффект %s.", m, e, v, fx)
}

func hasAny(cmd string, words []string) bool {
	return slices.ContainsFunc(words, func(w string) bool { return strings.Contains(" "+cmd+" ", " "+w+" ") })
}

// voiceMenu handles menu commands; ok=false means the phrase is a question for the model.
func voiceMenu(uid, cmd string) (string, bool) {
	words := strings.Fields(cmd)
	if len(words) == 0 || len(words) > 7 {
		return "", false
	}
	switch cmd {
	case "меню", "голосовое меню", "настройки", "помощь", "что ты умеешь", "какие команды":
		return menu, true
	case "какие настройки", "какой режим", "какая модель", "какой голос", "текущие настройки":
		return describe(prefsOf(uid)), true
	case "голос по умолчанию", "обычный голос", "стандартный голос":
		return "Хорошо. " + describe(updatePrefs(uid, func(p *prefs) { p.Voice = "" })), true
	case "без эффекта", "убери эффект", "эффект выключить":
		return "Хорошо. " + describe(updatePrefs(uid, func(p *prefs) { p.Effect = "" })), true
	}
	switch {
	case strings.HasPrefix(cmd, "модель ") || strings.HasSuffix(cmd, " модель") || strings.Contains(cmd, " модель "):
		for _, m := range models {
			if hasAny(cmd, m.words) {
				id := m.id
				return "Включаю модель " + m.title + ". " + describe(updatePrefs(uid, func(p *prefs) { p.Model = id })), true
			}
		}
	case words[0] == "сила" || strings.Contains(cmd, "рассуждени"):
		for _, e := range efforts {
			if hasAny(cmd, e.words) {
				id := e.id
				return "Хорошо. " + describe(updatePrefs(uid, func(p *prefs) { p.Effort = id })), true
			}
		}
	case words[0] == "голос" && len(words) >= 2:
		if id, ok := voices[strings.Join(words[1:], " ")]; ok {
			return "Хорошо. Так звучит новый голос. " + describe(updatePrefs(uid, func(p *prefs) { p.Voice = id })), true
		}
		return "Не знаю такого голоса. Скажи «меню», чтобы услышать варианты.", true
	case words[0] == "эффект" && len(words) >= 2:
		if id, ok := effects[strings.Join(words[1:], " ")]; ok {
			return "Хорошо. " + describe(updatePrefs(uid, func(p *prefs) { p.Effect = id })), true
		}
		return "Не знаю такого эффекта. Скажи «меню», чтобы услышать варианты.", true
	}
	return "", false
}

// tts wraps the spoken text in the user's voice and effect tags.
func tts(text string, p prefs) string {
	if p.Voice != "" {
		text = `<speaker voice="` + p.Voice + `">` + text
	}
	if p.Effect != "" {
		text = `<speaker effect="` + p.Effect + `">` + text
	}
	return text
}

func withPrefs(ctx context.Context, p prefs) context.Context {
	return context.WithValue(ctx, prefsKey, p)
}

// requestModel returns the model and reasoning effort for this request (user's or defaults).
func requestModel(ctx context.Context) (string, string) {
	p, _ := ctx.Value(prefsKey).(prefs)
	m, e := model, reasoning
	if p.Model != "" {
		m = p.Model
	}
	if p.Effort != "" {
		e = p.Effort
	}
	return m, e
}

func userID(in *aliceReq) string {
	if in.Session.UserID != "" {
		return in.Session.UserID
	}
	return in.Session.Application.ApplicationID
}
