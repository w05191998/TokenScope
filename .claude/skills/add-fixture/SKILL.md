---
name: add-fixture
description: Add a parser test fixture for a new or changed Claude Code / Codex log format in TokenScope. Use when logs stop parsing, a provider changes its log schema, or a new edge case needs regression coverage.
---

# Add a parser fixture

TokenScope's parsers are guarded by JSONL/JSON fixtures. Every format change gets a fixture line plus a test assertion, so regressions are caught by CI.

## Steps

1. **Capture the real shape.** Get a sanitized sample of the new log line(s) from `~/.claude/projects/**/*.jsonl` (Claude) or `~/.codex/sessions/**` (Codex). Replace all personal data: paths become `/Users/example/work/<name>`, session ids become descriptive fakes (`claude-<case>`), timestamps keep their exact FORMAT but use dates around `2026-07-10`.

2. **Pick the fixture file** under `fixtures/`:
   - `claude/session-usage.jsonl` — happy-path usage records
   - `claude/edge-cases.jsonl` — malformed/partial/unusual lines
   - `claude/tool-events.jsonl` — tool_use/tool_result events
   - `codex/…` — same split for Codex (`session-usage.json`, `rollout-edge-cases.jsonl`, `rollout-tool-events.jsonl`)
   Update the fixture directory's `README.md` describing the new case.

3. **Add the test** in `tests/ParserTests/ClaudeParserTests.swift` or `CodexParserTests.swift`: load via the existing `fixturePath(_:)` helper, assert record counts and every parsed field of the new case. If the parser must change to handle the format, follow `docs/PARSER_SPEC.md`; malformed lines must be skipped deterministically, never crash.

4. **Document** the format in `docs/SUPPORTED_FORMATS.md` (field table + example line).

5. **Verify**: `swift test` green locally. Timestamps: any new date format MUST be parseable by the custom ISO 8601 strategy in `src/Parsers/Claude/ClaudeParser.swift` (accepts with/without fractional seconds) — extend that strategy rather than `.iso8601` (older Foundation rejects fractional seconds; this bug shipped once already).

## Edge cases

- Fixture lines are position-sensitive in some tests (`result.records[0]`…) — append rather than insert, or update indices deliberately.
- Keep fixtures small: one line per behavior, not a full session dump.
- Never commit real usage data, even partial — check with `grep -i "$(whoami)" fixtures/ -r`.
