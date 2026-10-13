package main

// Phrase normalization for a skill session: inside an open session Alice forwards everything the
// user says, including «Алиса, …» and the skill name, so commands must match without them.

import (
	"regexp"
	"strings"
)

var namePrefix = regexp.MustCompile(`^(?:алиса\s+)?(?:(?:спроси|попроси|скажи|передай)(?:\s+у)?\s+)?(?:супер\s?интеллект\S*|суперинтендант\S*|чат\s?(?:джи\s?пи\s?ти|джипити|гпт)\S*)\s*|^алиса(?:\s+|$)`)

var exitWords = map[string]bool{
	"хватит": true, "стоп": true, "выйти": true, "выход": true, "вернись": true, "закончить": true,
	"закончи": true, "выключись": true, "пока": true, "до свидания": true, "хватит спасибо": true,
	"выйди из навыка": true, "выйти из навыка": true, "закрой навык": true,
}

// stripPrefix removes «алиса», «спроси у супер интеллект» and similar from the start.
func stripPrefix(cmd string) string {
	return strings.TrimSpace(namePrefix.ReplaceAllString(cmd, ""))
}

// leaveFor is a request meant for Alice herself (music, volume, alarms…): leave the skill so the
// next phrase reaches her.
func leaveFor(cmd string) bool {
	for _, p := range []string{"включи музыку", "включи радио", "поставь будильник", "громче", "тише",
		"какая погода", "выключи", "включи свет", "поставь таймер"} {
		if strings.HasPrefix(cmd, p) {
			return true
		}
	}
	return false
}

func isActivation(cmd string) bool {
	c := strings.ReplaceAll(cmd, "супер интеллект", "суперинтеллект")
	return strings.Contains(c, "навык суперинтеллект") || c == "суперинтеллект" || c == "суперинтеллекта"
}
