# Ruslan's deployment (Oracle VPS, Dubai)

Yandex Dialogs → Caddy `https://193-123-85-206.sslip.io/aab/<secret>/alice` → this bridge
(`127.0.0.1:8790`, systemd `alice-ai-bridge`) → `http://127.0.0.1:8787/v1/chat/completions`, an
OpenAI-compatible gateway in [alice-gpt](https://github.com/divedooberman-dotcom/alice-gpt) that
answers with Ruslan's ChatGPT subscription (gpt-6-luna), memory and web search.

Build and deploy from the Mac:

    GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o alice-ai-bridge .
    scp alice-ai-bridge vps:/tmp/ && ssh vps 'sudo install -m755 /tmp/alice-ai-bridge /opt/alice-ai-bridge/ && sudo systemctl restart alice-ai-bridge'

`/opt/alice-ai-bridge/.env` (root:aab 640, not in git): LISTEN_ADDR=127.0.0.1:8790,
WEBHOOK_PATH=/aab/<secret>/alice, ALLOWED_SKILL_ID, TIMEZONE=Asia/Dubai,
LLM_BASE_URL=http://127.0.0.1:8787/v1, LLM_API_KEY=<ALICE_LLM_SECRET>, LLM_MODEL=gpt-6-luna,
LLM_MAX_TOKENS=1200, LLM_TIMEOUT_MS=2800, CHUNK_RUNES=900, HISTORY_TURNS=6.

## Skills
- **Семейный ИИ** (`aeefbe5e-…1959`, private, created 2026-10-13) — main. «Алиса, запусти навык Семейный ИИ».
  Webhook `/aab/<secret>/alice`. Activation phrases: «Семейный ИИ», «Семейный и и», «Семейный искусственный интеллект».
- **Супер интеллект** (`bc04feaa-…3130`) — old; its webhook path is rewritten to this bridge by Caddy.
  Its name collided with other (private) skills: «Американский интеллект» and similar names are already
  registered by someone; Dialogs rejects them with «Это активационное имя уже зарегистрировано».
  Alice's ASR writes «ChatGPT» in Latin, so the Cyrillic «Чат джи пи ти» activation never matches by voice.
- Publishing: «Send to moderation» → «Deploy» (private skills are approved instantly; deploy took ~4 min).
