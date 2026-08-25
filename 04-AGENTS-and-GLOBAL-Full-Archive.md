# 04 — Full Archive of AGENTS.md and GLOBAL.md (Direct Copy-Paste Restore)

> Place AGENTS.md at `/var/minis/shared/AGENTS.md` (read automatically by the agent at the start of each task).
> Place GLOBAL.md at `/var/minis/memory/GLOBAL.md` (maintained by the user, read-only to the agent).

---

## 4.1 AGENTS.md (`/var/minis/shared/AGENTS.md`)

```markdown
# AGENTS.md — Minis Agent Self-Managed Long-Term Instructions (Maintained by Agent)

> At the start of every task, `file_read` this document first. GLOBAL.md is read-only to the agent; this document is the only self-managed contract active on every task.

## Environment Snapshot (2026-08-19)
- Alpine 3.21 aarch64, root, Python 3.12, Node 22, bash installed.
- Toolchain: git jq py3-pip npm tmux vim ripgrep fd sqlite htop curl wget openssh-client file.
- pip is functional (musllinux aarch64 wheels verified OK); package installation priority: `apk search py3-*` first, fall back to pip if unavailable.
- Hard constraints: disk write ~0.85MB/s (slow); CPU is 10–20x slower, no JIT; iOS physical storage is 96% full -> avoid large downloads and large file accumulation; offload heavy tasks to remote servers.

## psh Persistent Shell (`/usr/local/bin/psh`, v3)
- Multi-step tasks requiring cwd/env continuity -> `psh run 'cmd'`. Commands must be **single-line**; write complex logic into a script file first, then run `bash /path/script.sh`.
- Long-running tasks (>10s) -> `psh bg <name> 'cmd'` + `psh wait <name>` + `psh tail <name>`, **never** use blocking `shell_execute` to wait blindly (looks like a hang).
- Fast single-shot commands run directly via `shell_execute` (psh incurs ~2–4s overhead per invocation).
- ⚠️ `pgrep`/`pkill` are unreliable on iSH (`ps` STAT shows non-standard RW; `pgrep` matches stale `/proc` remnants of dead processes). Liveness judgment relies on psh's built-in round-trip probe detection; **never write custom liveness logic depending on pgrep**.
- If a session dies and probe fails, it is automatically rebuilt; after rebuilding, `/proc` may retain traces of dead processes (looks like a leak, but is actually harmless stale metadata with no resource consumption) — do not panic.
- Processes can survive across `shell_execute` calls (verified with `setsid`); but survival is not guaranteed after app suspension, so do not rely on long-running daemon processes.
- Do not send psh commands in parallel (no lock).
- `psh run 'exit ...'` is specially handled = stop; run timeout will kill the session, and the next call will automatically rebuild. Do not include exit/exec in commands.
- **Note: As of 2026-08-23, psh script was confirmed lost (`/root/.local/bin/` missing); rebuild via env-bootstrap when needed.**

## Security Guardrails (`guard`, Active Since 2026-08-21)
- **Before deleting files, forcing git push/reset/clean, overwriting files, or making external POST requests: confirm with user first**, and run `guard run --cmd "..." --yes` only after receiving user consent. Commands without `--yes` will be rejected (exit 3); do not bypass.
- Sensitive output (keys/tokens/passwords) must be masked via `guard redact` or automatically masked by `guard run` before display.
- When in doubt about read/write paths, verify they reside inside `/var/minis` or `/tmp` using `guard path P`; symlink traversal will report outside.
- Details in `/var/minis/shared/harness/guard.py` (selftest: `guard selftest`).
- Note: Guardrails operate as tool-layer self-discipline, not a system sandbox; true sandbox enforcement requires Phase B fork.

## Output Quality / Loop Quality / Resource Norms (Codex Policy, Active Since 2026-08-22)
- **review-before-verify**: Before running `agentverify check`, perform a self-review (spirit of ReviewTask): verify deliverables meet acceptance criteria, check if user requirements were omitted, and ensure results align with the objective. Fix issues before verifying.
- **budget reminder**: run events >= 15 -> run `agentcompact summarize --save` to compress history first; do not continue dragging full history along (threshold aligns with `tooloffload` specification).
- **flush-before-cancel**: Before aborting or switching away from a long-running task, persist state with `agentrun checkpoint --note ...`.
- **handoff summary**: When resuming tasks across sessions, write/read the 4-part agentcompact summary (progress + decisions / context + constraints + preferences / remaining steps / artifact references); format matches `agentcompact summarize` output.
- **Segmented memory budget** (spirit of Codex realtime_context): daily log <= 500 words per entry, prefixed with a keyword; `GLOBAL.md` stores only persistent preferences; compress old details with `agentcompact` instead of accumulating text.
- Long output handled by `tooloffload` is head+tail truncated (preserving trailing error tracebacks); when reading `full_output_ref`, inspect the tail segment first before deciding whether to read the middle segment.

## Run State (`agentrun`, Active Since 2026-08-21)
- **Unified Frontend `task` (Active Since 2026-08-22)**: Multi-step/long tasks must strictly use `task`, do not call underlying tools haphazardly:
  - Start task: `task start "goal" --criteria criterion1,criterion2` (blocked if a run is active; restart requires `--force`)
  - **Start of each turn**: `task next` to inspect digest (phase + next step + criteria dry-run + budget warnings) — do not reconstruct "where we are" from raw history; the state machine is the single source of truth.
  - Record step: `task do "summary" --tool T [--ok|--exit N] [--evidence K]`; record deliverables with `task add PATH`
  - Flow: `task phase P`, `task check` (all passing automatically transitions -> VERIFY), `task done`, `task fix "reason"`
  - Suspend/Resume: `task wait "note"` <-> `task resume`; long output: `task offload "cmd"`
  - Compact: `task next` will warn when events >= 15; `task compact` outputs handoff summary (blocked if below threshold)
  - Full usage: `task --help`; inspect state via `task show` / `task list` / `task where`
- Low-level `agentrun` syntax (use directly only when not covered by `task`):
  - DONE can only transition from VERIFY (model cannot declare completion directly); identical failure fingerprint >= 2 times forbidden from unchanged rerun; >= 3 times should transition to WAIT_USER.
  - Criteria syntax: `exists:path` / `cmd:cmd` / `contains:path:sub` / `json:path` / `pycompile:path` / `sources:N` / `domains:N` / `citations:N` (add `--evidence-json` for research).
  - Long output: `tooloffload run --cmd "..." --json` (envelope + full_output_ref); when details are needed, use `tooloffload read REF --lines 50` to read in chunks, never dump full output back to model.
  - State directory defaults to `/var/minis/workspace/.agent` (customizable via `--dir`). View with `agentrun show` / `agentrun list`.
  - Persistent shell/jobs (feasibility verified): `agentd start` -> `agentd open` -> `agentd exec --session S --cmd ...`; long tasks: `agentd job-start --cmd ...` + `agentd job-status/job-logs/job-kill --jid J`.
  ⚠️ iSH lacks job control: abort with `agentd interrupt` (SIGINT -> bash child process), do not send ^C.
  - Details in `/var/minis/shared/harness/` (`agentrun.py` / `agentverify.py` / `agentd.py` / `tooloffload.py`; selftest: `agentrun selftest`, `agentverify selftest`, `tooloffload selftest`, `python3 feasibility_agentd.py`).

## Presentation / PPTX Workflow (DISABLED Since 2026-08-23)
- All PPT guidelines disabled, archived in `/var/minis/shared/disabled-skills/` (including original section text `AGENTS-ppt-workflow.md`).
- Currently only the most foundational plugin is retained: **powerpoint-pro** (`SKILL.md` + `scripts/generate_pptx.py`, direct python-pptx export).
- Restoration method: Move required skill directories from `/var/minis/shared/disabled-skills/` back to `/var/minis/skills/`, and restore `AGENTS-ppt-workflow.md` contents into this section.

## Working Conventions
- Deliverables -> `/var/minis/shared/<project>/`; temporary files -> `/tmp/`.
- `minis://` links must always use the encoded URL returned by tools.
- Blueprint: `/var/minis/shared/minis-workspace-blueprint.md` (Phase 0 established this document + psh + env-bootstrap).

## Web Search (Codex Built-In Web Search, Sole Path Since 2026-08-23)
- Needing latest/external information -> `web-search "original query"` (synonym: `ws`). Pass the original query directly, **do not polish or expand query** — codex handles searching natively. See `/var/minis/skills/web-search/SKILL.md`; shim = `/var/minis/shared/codex-lab/codex-search.sh`.
- Entire pipeline is forwarded to codex built-in web search (DeepSeek `web_search` tool + `open_page`), bypassing HTML web scrapers.
- Each search consumes DeepSeek tokens (metered billing, roughly 10k–20k tokens); codex cold start is slower (tens of seconds). Powerful but not free.
- On codex failure, **do not fallback**, report failure directly to user.
- Removed/Disabled: `brave-search` MCP (deleted), `web-research` skill (moved to `disabled-skills/`), DDG/Bing (`web-search` command redirected to codex shim). **Never use these again**.
- Answers must include source URLs (`[Title](URL)`).
- `browser_use` is only used as a fallback when codex results require manual page verification, not for search.
```

---

## 4.2 GLOBAL.md (`/var/minis/memory/GLOBAL.md`)

```markdown
# Global Memory

## System and Environment Norms
- **Time and Date Management**: The running time of this system defaults to being synchronized with the host iOS phone environment (dynamically retrieved via the iSH shell).
- **Memory Update Mechanism**: Memory uses daily logs (`YYYY-MM-DD.md`) and global configuration (`GLOBAL.md`). On each conversation launch, the current log and status are loaded automatically, ensuring timestamps and context remain synchronized with the mobile device.
```

> Note: `GLOBAL.md` is maintained by the user via Settings; if the agent wants to change it, inform the user so the user can edit it.
