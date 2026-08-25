# 03 — Minis Directory Structure and Skills (100% identical)

> Source: collected from the real iPhone iSH device (2026-08-24).

---

## 3.1 /var/minis directory tree (as collected)

```
/var/minis/
├── attachments/          ← media attachments (managed by the Minis app)
├── browser/              ← browser screenshots (managed by the Minis app)
├── mcp-servers/          ← MCP config (servers.json + logs)
├── memory/               ← memory files
│   ├── GLOBAL.md
│   ├── SOUL.md
│   └── YYYY-MM-DD.md     ← daily log
├── mounts/               ← iOS Files mounts (create empty directories on a computer)
│   ├── Alpine Linux Storage/
│   ├── Codex-cli/
│   ├── Extension:Upgrade storage/
│   ├── OpenMinis_優化報告/
│   ├── grok-build-main/
│   ├── open_minis_grok_web_tools/
│   ├── patched-codex-v2-完整包/
│   ├── patched-codex-傳手機/
│   ├── 待辨工作-優化-Debug-除錯_藍圖儲存文件夾/
│   └── 心理學/
├── offloads/             ← large-output offloads
├── shared/               ← cross-session storage (core)
│   ├── AGENTS.md
│   ├── apple-deck/
│   ├── archive/
│   ├── codex-lab/        ← full codex setup (see 02)
│   ├── desktop-replica/  ← this blueprint series
│   ├── disabled-skills/  ← disabled skills archive
│   ├── harness/          ← 8 tool py files (see 04)
│   ├── minis-workspace-blueprint.md
│   ├── psh-kit/          ← original psh (see 04)
│   ├── slides-profiles/
│   ├── system-blueprint/ ← new-phone reinstall blueprint 00-06
│   ├── web-research/     ← old (disabled)
│   └── web-search/       ← old DDG/Bing implementation (disabled)
├── skills/               ← 4 skills (see 3.2-3.5)
│   ├── codex/
│   ├── powerpoint-pro/
│   ├── skill-creator/
│   └── web-search/
└── workspace/            ← working files
    ├── ish-einval-fix/   ← exec bug build materials
    └── minis-backup/     ← backups
```

Create on a computer (empty skeleton):
```sh
mkdir -p /var/minis/{attachments,browser,mcp-servers,memory,mounts,offloads,shared,skills,workspace}
```

---

## 3.2 /usr/local/bin symlink map (complete)

```sh
# harness tools (real files in /var/minis/shared/harness/)
ln -sf /var/minis/shared/harness/guard.py        /usr/local/bin/guard
ln -sf /var/minis/shared/harness/agentrun.py     /usr/local/bin/agentrun
ln -sf /var/minis/shared/harness/agentverify.py  /usr/local/bin/agentverify
ln -sf /var/minis/shared/harness/agentd.py       /usr/local/bin/agentd
ln -sf /var/minis/shared/harness/task.py         /usr/local/bin/task
ln -sf /var/minis/shared/harness/tooloffload.py  /usr/local/bin/tooloffload
ln -sf /var/minis/shared/harness/agentcompact.py /usr/local/bin/agentcompact

# full codex setup (see 02)
ln -sf /var/minis/shared/codex-lab/codex-ds.sh     /usr/local/bin/codex
ln -sf /var/minis/shared/codex-lab/codex-search.sh /usr/local/bin/web-search
ln -sf /var/minis/shared/codex-lab/codex-search.sh /usr/local/bin/ws

# psh (real file in /root/.local/bin/, see 04)
ln -sf /root/.local/bin/psh          /usr/local/bin/psh
ln -sf /root/.local/bin/env-bootstrap /usr/local/bin/env-bootstrap

# PPT
ln -sf /var/minis/skills/powerpoint-pro/scripts/generate_pptx.py /usr/local/bin/pptx-gen
```

**Built-in Minis app commands (absent on a computer; no need to install)**:
`apple-*` (24 iOS framework tools), `minis-*` (browser-use/config/debug/mcp-cli/model-use/open/sessions-cli),
`gnome-open`, `kde-open`, `sensible-browser`, `mcp-server-brave-search` (disabled).

---

## 3.3 Skill: codex (/var/minis/skills/codex/SKILL.md, full text)

```markdown
# Codex CLI (DeepSeek) — Subagent Skill

Use Codex CLI 0.139.0 for headless agent tasks (driven by DeepSeek v4 flash).
This skill lets an agent run multi-step tasks directly with codex, without the user manually
opening a terminal.

## Entry points

```sh
codex "task description"              # interactive mode (needs a TTY; do not use)
codex exec "task description"         # one-shot headless task <- commonly used
codex exec resume --last "continue"   # resume the most recent session (has memory)
codex exec resume <session_id> "..."  # resume a specific session
```

- `/usr/local/bin/codex` is a wrapper (auto-starts the TLS bridge + sets CODEX_HOME)
- The bridge does not need manual management: the wrapper detects that 127.0.0.1:8787 is not
  open and starts it automatically

## Environment

- CODEX_HOME=/var/minis/shared/codex-lab/codex-home (config.toml lives here)
- Model: `deepseek-v4-flash` (change in config.toml)
- Provider: deepseek, wire_api=responses, base_url points to http://127.0.0.1:8787/
  (local TLS bridge -> https://api.deepseek.com)
- approval=never, sandbox=danger-full-access (fully automatic, no confirmation)
- API key: experimental_bearer_token in config.toml (sensitive — do not write it into
  memory/output)

## Important parameters

- **reasoning effort** (config.toml `model_reasoning_effort`): DeepSeek supports 7 values:
  `none / minimal / low / medium / high / xhigh / max` (`ultra` is not supported, returns 400)
- Change effort: `codex -c 'model_reasoning_effort="high"'` or edit config.toml directly
- Change model: the `model` field in config.toml (deepseek-v4-flash / deepseek-v4-pro /
  deepseek-v4-flash-vision-exp)

## Relay rules (important — forward verbatim)

- When the user says "use codex to do XX" / "ask codex to do XX" / "hand it to codex" etc.:
  **strip only the prefix instruction**; everything after XX stays **exactly as-is — no
  translation, no rewriting, no added interpretation** and is passed to `codex exec "..."`.
- A spec/description pasted by the user -> pass the whole segment verbatim; do not summarize
  it in your own words.
- Why: codex is itself an agent that understands and executes; we are only the messenger, and
  rewriting distorts the message.
- Returning output: **relay codex's reply as-is**; no translation, no summary, no polish
  (unless the user explicitly asks for a summary/translation).
- Exception: when the user is asking *me* rather than telling me to use codex, do not
  auto-forward to codex.

## Session binding (important — chatroom mapping)

- codex sessions map **1:1** to Minis chatrooms (managed automatically by the wrapper; state
  file /var/minis/shared/codex-lab/codex-chat-map).
- **Within the same chatroom, unless the user explicitly notifies otherwise, every codex call
  defaults to resuming the same session** (search, writing code, editing files are all one
  codex conversation — codex remembers the whole earlier context).
- **New chatroom** -> automatically opens a new codex session.
- **Forced new**: when the user explicitly says "start a new codex session" / "new
  conversation" / "reset codex" -> use `codex exec --new "..."` or `web-search --new "..."`.
- **Unlimited turns**: no turn/time limits (continuity wins); context is left to codex itself;
  only fall back to a new session when resume really fails.
- Do not decide "it is time for a new session" yourself — there are only three new-session
  conditions: new chatroom / user notification / resume failure.

## Current limitations (important — since 2026-08-23, iSH-specific)

**codex's exec tool has a bug on iSH**: non-TTY exec_command fails 100% of the time
(`exited -1 in 0ms`, the child is killed by a signal immediately; root cause confirmed: iSH does
not support waitid(P_PIDFD), the tokio pidfd path returns EINVAL every time). A patched binary
was waiting for a rebuild. Therefore:

- **Pure Q&A / analysis / search / chat** -> codex works completely normally, use it.
- **Writing files / running commands / git / tests** -> do not go through codex (it spins in the
  exec retry loop and burns time); use shell_execute yourself.
- If codex really must execute a command, the prompt must say "every exec_command must use
  tty:true" (the tty:true path is verified to work; codex follows it).
- **Local file operations (grep/find/file lookup) -> never ask codex**: it may grep across the
  whole /var/minis (212MB binary + all sessions + the mounts source trees) and hang for up to 10
  minutes. Always use shell_execute for local searches.
- **Product comparisons / external information -> always web-search** (codex built-in web
  search); do not ask codex to look locally (it goes in the wrong direction).
- **Zombie bridge**: the wrapper adds PID detection and auto-cleanup (a zombie bridge = process
  alive but socket unresponsive, which makes codex hang in a Reconnecting loop). When codex
  appears stuck, first run `curl -s --max-time 2 http://127.0.0.1:8787/` to check the bridge.

## Execution rules

1. Multi-step tasks (writing code, editing multiple files, running tests) -> `codex exec "..."`;
   it thinks, executes, and verifies by itself
   (⚠️ but see "Current limitations": until the exec bug is fixed, tasks that actually execute
   go through shell_execute first)
2. Need context from a previous step -> `codex exec resume --last "..."` (sessions persist in CODEX_HOME)
3. The exec output repeats the agent reply at the end (normal behavior)
4. Timeout: **do not use short timeouts**. Long codex tasks (at max effort) can run close to 10
   minutes.
   - `timeout 900 codex exec ...` (900 seconds = 15 minutes, the hard upper limit at the tool layer)
   - when using the shell_execute tool, its `timeout` parameter must be set to **900**
     (default 900 seconds = 15 minutes)
   - short timeouts like 120s cut long tasks off (codex is Terminated and tokens are burned
     with no result)
   - quick probes (like reply OK) may use short timeouts (60-120s); real tasks always 900
5. Run exec inside a git repo first; `--skip-git-repo-check` allows running outside a repo
6. Do not use `codex login` / interactive mode (TTY issues); everything goes through exec

## Troubleshooting

- `stream disconnected` / `Reconnecting...` -> bridge died: `ps | grep tls_bridge`; if absent,
  run `nohup python3 /var/minis/shared/codex-lab/tls_bridge.py > /tmp/tls_bridge.log 2>&1 &`
- `Once instance has previously been poisoned` / P521 assert -> the 0.149 binary is in use;
  always use the wrapper (which points to 0.139.0)
- 401 -> experimental_bearer_token in config.toml is invalid; replace the key

## Background (why the bridge)

ring TLS handshake fails on iSH (curl/OpenSSL work) -> codex cannot connect to https directly.
Fix: codex connects to http://127.0.0.1:8787/, and tls_bridge.py forwards to api.deepseek.com
with OpenSSL. The official 0.149 binary panics (rustls P521 assert, binary inconsistent with its
Cargo.lock); 0.139.0 has no problem.
```

---

## 3.4 Skill: web-search (/var/minis/skills/web-search/SKILL.md, v4 full text)

```markdown
# web-search v4 — Codex web research architecture

> On the surface it is a web-search tool; in reality the whole request is forwarded to
> **codex's built-in web search** (DeepSeek native web_search tool + open_page).
> This skill is the **only** search path. Brave MCP, web-research, and DDG/Bing HTML are all
> disabled/removed — **do not use them again**.

## 1. Roles
- **Codex = the actual web research agent**: it decides the search strategy itself and is
  responsible for final quality.
- **Outer agent = intent delivery + lightweight acceptance**: passes the original wording in,
  receives results, checks basic problems, and **does not search itself**.

## 2. Hard quality rules (iron rules)
1. **Must not change the user's real intent** (question, constraints, requirements).
2. Must not present unverified information as verified fact.
3. Clearly irrelevant/polluted results must not be delivered as the answer.
4. When up-to-date information is needed, must not rely only on model memory.
5. When a search fails, must not pretend success — report transparently.
6. Cited sources must actually support the relevant claim.
7. **Only list exhaustively when the user explicitly asks for "all links"**.
8. Must not create a Codex -> ws -> Codex recursion loop.
9. The chatroom ↔ Codex session continuity design must not be broken by automatic rotation.

## 3. Commands
```
web-search "original query"        # synonym: ws "original query"
web-search --new "new topic"       # force a new session (synonym -n)
web-search --reset                 # clear the mapping (next = new session)
web-search --status                # view status
web-search --help                  # usage (does not trigger a search)
```

## 4. Query delivery (key v4 change)
- **The user's original wording = the only authoritative source of intent**: the outer agent
  passes it in completely; no translation, rewriting, or replacement.
- **But the original wording is not the only query codex must search verbatim**: after receiving
  it, codex may freely design its search strategy — change keywords, synonyms/language variants,
  split questions, add year/version/region, multiple rounds, open pages to verify, refine,
  cross-check.
- All query transformations are only search tactics; they must not change the user's original intent.
- The outer agent **must not** rewrite the query itself; the shim already wraps the original
  wording in `<user_query>` before passing it to codex.

## 5. Search quality gate
After completing the search, codex must judge: relevance (does it really answer the question),
freshness (if the latest is needed, is there recent material), source fit (does the source
support this kind of claim), consistency (do sources contradict each other), coverage (are the
important parts answered). If it fails -> refine/search again/open pages/switch sources yourself,
do not hand it over.

## 6. Verification
- Volatile information (prices, versions, dates, latest status, announcements, benchmarks) ->
  verify against first-party/original sources whenever possible.
- One suitable primary source is enough; do not force a second source for the sake of having two.
- Source contradictions -> point out the contradiction; do not pretend there is a single answer.
- When reliable information cannot be obtained -> say so clearly; do not guess.
- When native search results are insufficient, codex may try other available methods (including
  shell commands); supplemental content must pass the same quality gate; when the environment
  capability fails (e.g. the iSH exec bug), do not retry endlessly.

## 7. Session (chatroom binding, unchanged)
- codex sessions map **1:1** to Minis chatrooms (the wrapper + shim share codex-chat-map).
- **Unlimited turns** (continuity wins); a new chatroom automatically opens a new one; `--new`
  or an explicit user request opens a new one; only fall back when resume fails.
- **Topic shift only warns, does not auto-break**: when the user changes topic within the same
  chatroom, you may note "new question, do not be distracted by the old topic above" when
  passing to codex, but the session still resumes the same one.
- Judgment: the user message refers to earlier context ("that one", "just now", "the second
  one") -> follow-up; a brand-new topic -> `--new`.

## 8. Output contract
- **Answer the question first, then attach sources**; attach relevant URLs for important facts.
- **Normal answers do not dump all URLs** — only list the sources that actually support the answer.
- **An exhaustive link list is only output when the user explicitly asks** (see below).

## 9. Link follow-up rules (exhaustive mode)
When the user says "list the links above" / "all URLs from the websites above" / "all weblinks
related to XX" -> exhaustive mode:
- The agent directly calls `web-search "user's original wording"` (passed through verbatim; the
  shim's resume prompt already embeds the instructions).
- codex extracts from the earlier context (no re-search), lists everything, misses nothing, each
  with its title; multiple search rounds are grouped by query term.
- Agent acceptance: compare against the earlier tool traces to check for omissions; follow up to
  fill in any missing ones (never fabricate links).

## 10. The outer agent's lightweight acceptance (no second research)
After receiving codex's reply, check:
1. Does it really answer the question? 2. Any obvious hallucination / mismatched results?
3. When the latest is needed, are there real web sources? 4. Are link formats valid?
5. When the user wants all links, is anything missing? 6. Did codex hide uncertainty?
-> If there is a problem, follow up with codex; **do not rewrite the answer yourself and do not
search yourself**.

## 11. Failure handling
- There is no second-layer search engine (DDG/Bing measured unusable, Brave deleted) —
  **do not fabricate a fallback**.
- codex fails (bridge dead / key invalid) -> report transparently to the user; do not fall back
  to a junk engine and do not pretend success.
- Partial success -> state clearly which parts are verified and which are not
  (PARTIALLY VERIFIED); do not be vague.

## 12. Protection (since v3.1, kept)
- `ws --help`/`-h` -> prints usage, exit 0; unknown arguments starting with `-` -> error, exit 2.
  Neither triggers a search.
- **Anti-recursion**: nested ws/codex calls inside a codex session are blocked by
  /tmp/codex-recursion-guard (exit 2).
- Zombie bridge auto-cleanup (inside codex-ds.sh).

## 13. Cost and latency
- Each search consumes ~10k-20k DeepSeek tokens; cold start takes tens of seconds; multi-round
  searches at xhigh effort can take 30s-3min.
- Follow-ups preferentially reuse evidence already in the session, avoiding unnecessary re-searches.
- codex has a stop condition: "stop once there is enough reliable evidence; do not keep searching
  to increase the source count".

## Files
- shim: `/var/minis/shared/codex-lab/codex-search.sh` (symlinks `/usr/local/bin/web-search`,
  `/usr/local/bin/ws`)
- old DDG/Bing implementation: `/var/minis/shared/web-search/web-search.py` (disabled, not deleted)
- codex: `/var/minis/shared/codex-lab/codex-0139/codex` + `codex-home/config.toml`
  (DeepSeek key is here; do not leak it)
```

---

## 3.5 Skill: powerpoint-pro + skill-creator

> Full text is already in /var/minis/shared/system-blueprint/03-Skills-Full-Archive.md
> (powerpoint-pro condensed version + skill-creator condensed version). The complete originals
> are in the two directories under /var/minis/skills/ on the real device. Neither is core;
> copy them directly from the device when needed.

---

## 3.6 AGENTS.md (/var/minis/shared/AGENTS.md)

> Content identical to the real device — get the original with `cat /var/minis/shared/AGENTS.md`
> and copy it character by character.
> Structure: ①environment snapshot ②psh rules ③guard guardrails ④output quality/loop quality
> ⑤Run State (task/agentrun/agentd) ⑥PPTX workflow (DISABLED) ⑦working conventions
> ⑧web search (v4 rules). After installing codex on a computer, this AGENTS.md is the computer
> agent's "work manual" — just place it at `/var/minis/shared/AGENTS.md` in the same location.

---

## 3.7 GLOBAL.md + SOUL.md (memory/)

```markdown
# Global Memory

## System and environment rules
- **Time and date management**: this system's runtime time defaults to staying in sync with the
  iOS phone host environment (the iSH shell dynamically obtains the current system time).
- **Memory update mechanism**: memory uses a daily log (YYYY-MM-DD.md) plus global settings
  (GLOBAL.md); every conversation start automatically loads the current log and state, keeping
  timestamps and context in sync with the phone system.
```

> SOUL.md is the Minis app's agent personality config, managed at the app layer; not needed on a
> computer. GLOBAL.md is maintained by the user via Settings (agent read-only).

---

## 3.8 slides-profiles (PPT templates)

```
base-16x9.pptx      ← 16:9 blank template (13.333×7.5")
power-design-20.json ← design QA profile (after style neutralization)
bio-cyber.json      ← another profile
slides-schema.json  ← slides JSON schema
```

---

## 3.9 disabled-skills (archive, no need to restore)

```
slides-extract / slides-build / slides-full / slides-edit / slides-audit /
slides-critique / slides-polish (agent-slides series)
power-design (73 brand DNA)
web-research (Tavily/Brave/Exa routing — free tier 0/10 unusable)
AGENTS-ppt-workflow.md
```
