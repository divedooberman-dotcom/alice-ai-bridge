# alice-ai-bridge — shared agent instructions

## Project boundary

This Go service is the current Yandex Alice voice frontend for Ruslan's project.
It calls the sibling `../alice-gpt` Python gateway through the OpenAI-compatible
POST `/v1/chat/completions` endpoint. That gateway owns subscription/API routing,
long-term memory, archive, MCP, and Telegram duplicates.

- `main.go`: webhook, generation lifecycle, sentence paging, streamed HTTP client.
- `prefs.go`, `tutorial.go`, `phrases.go`: voice preferences and response text.
- `relay.go`, `contrib/relay-agent/agent.py`: unfinished local-speaker relay work.
- `deploy/vps/README.md`: fork-specific topology, skill names, and deployment.
- The rest of README.md contains generic upstream installation examples.

Keep this repository separate from `alice-gpt`. Inspect both sides when changing
the streaming contract. The deployed service is `/opt/alice-ai-bridge`, systemd
`alice-ai-bridge.service`, listening on localhost:8790 behind Caddy.

## Preserve the working tree

Inspect `git status --short` and existing diffs first. At the 2026-10-13 handoff,
`main.go` was modified and `relay.go`, `relay_test.go`, and `contrib/` were untracked.
Preserve that work. Do not reset/clean, delete untracked files, replace it with an
upstream checkout, or commit unrelated edits without the user's instruction.

Use rg for targeted code searches and read the relevant source before editing.
Docs, configs, and shell scripts may be searched directly.

## Validation

```sh
gofmt -w <changed-go-files>
go test -race ./...
go vet ./...
```

Tests should use synthetic requests and fake HTTP transports. Do not send live
webhooks, wake speakers, or use real credentials as part of the default test run.
For gateway contract changes also run the Python tests in `../alice-gpt`.

Before each live microphone or wake-word test, ask the user whether the MacBook
is beside the station under test and whether it may play one quiet test phrase
now. Wait for confirmation of both. Play the phrase through the MacBook's built-in
speakers and check the station's logs for its response. Never play the test phrase
through the station itself. Ask again before repeating it or raising the volume.

A streamed error or EOF without `[DONE]` is a failed generation. Never report a
partial response as successfully complete. Keep progressive voice delivery,
Russian user-facing messages, and the existing relay/paging behavior intact.

## Operations

Keep `.env`, bearer secrets, Yandex tokens, private webhook URLs, and conversation
data out of commits and tool output. Codex login does not replace the gateway's
runtime credentials. `LLM_API_KEY` here authenticates to the local gateway in this
deployment; use the deployment notes before interpreting generic upstream examples.

The two services deploy separately. Preserve secrets and persisted preferences.
The current migration explicitly excludes deployment: do not build over the local
release binary, copy files to the VPS, restart services, or launch the relay agent.
Report local tests separately from VPS and physical-speaker verification.

## Codex and Claude Code collaboration

- Read HANDOFF.md at the start; verify its branch, commit and test evidence against the checkout.
- One agent owns edits in a checkout at a time. A reviewer reports findings without editing,
  switching branches, committing, or formatting files. Transfer ownership explicitly.
- Use separate worktrees for concurrent implementation. For cross-service work keep matching
  alice-ai-bridge and alice-gpt checkouts adjacent, and verify both paths before editing.
- Update HANDOFF.md when handing off: task, owner, commits, changed files, validation,
  unresolved issues and next step. Keep secrets and conversation data out of it.
- CLAUDE.md imports this file; keep shared rules here rather than duplicating them.
- MCP connections and permissions are configured separately in each tool.
- No deployment, service restart or speaker-control action without authorization for that action.
