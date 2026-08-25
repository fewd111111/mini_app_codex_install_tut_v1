# 03 — Skills Full Archive (direct copy to restore)

> Path: /var/minis/skills/<name>/SKILL.md
> Four skills: codex / web-search / powerpoint-pro / skill-creator

---

## 3.1 codex (/var/minis/skills/codex/SKILL.md)

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

## Execution rules

1. Multi-step tasks (writing code, editing multiple files, running tests) -> `codex exec "..."`;
   it thinks, executes, and verifies by itself
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

## 3.2 web-search (/var/minis/skills/web-search/SKILL.md)

```markdown
# web-search — default web search mechanism (codex forwarding shim)

> On the surface it is a web-search tool; in reality the whole request is forwarded to
> **codex's built-in web search** (DeepSeek native web_search tool + open_page).
> This skill is the **only** search path. Brave MCP, web-research, and DDG/Bing HTML are all
> disabled/removed — **do not use them again**.

## Iron rules (mandatory)
1. Any task needing **latest/immediate/external** information must use `web-search "original query"`.
2. **Do not polish, expand, or rewrite the query** — pass the original wording through. codex's
   search ability is stronger than this agent's; let it decide what to search and which pages to
   open for verification.
3. **Do not** use brave-search MCP, web-research, DuckDuckGo, Bing, or browser_use for searching
   (browser_use is only a fallback when a codex result needs a human to open a page).
4. When codex fails (bridge down / DeepSeek key invalid), **do not fall back to a junk engine**;
   report the failure directly to the user.

## Commands
```
web-search "original query"        # synonym: ws "original query"
web-search --new "new topic"       # force a new session (synonym -n)
web-search --reset                 # clear the mapping (next = new session)
web-search --status                # view status
web-search --help                  # usage (does not trigger a search)
```

## Session continuity (important, since v3 — global chatroom binding)
- codex sessions map 1:1 to Minis chatrooms (the wrapper + shim share
  /var/minis/shared/codex-lab/codex-chat-map).
- **Within the same chatroom, every codex call (search/exec) is the same codex session** —
  follow-ups like "do you have the full links?" / "what is the second one?" go straight through
  `web-search "follow-up query"`; codex can see the earlier context (including all links) and
  answers directly without re-searching.
- **New chatroom** -> automatically opens a new session. **User notification** ("start fresh") ->
  `web-search --new "query"`.
- **Unlimited turns**: no 60min/8-turn auto rotation (continuity wins); only fall back to a new
  session when resume really fails.
- Judgment rule: if the user message clearly refers to earlier context ("that one", "just now",
  "the first one") -> follow-up; a brand-new topic -> --new.

## Link follow-up rules (important — the most common user operation)
- When the user says "list the links above" / "all URLs from the websites above" / "all weblinks
  related to XX" = link follow-up.
- The agent directly calls `web-search "user's original wording"` (passed through verbatim; the
  shim's resume prompt already embeds referent understanding + full listing instructions).
- After codex replies, check that all links are listed; if any are missing, follow up again to
  fill them in (never fabricate links yourself).
- Verified: follow-up "list all weblinks about opencode above" -> codex listed all 10 from the
  earlier context and noted "no new search performed".
- A new search's final reply must include a "full link list" section (nothing missing).

## Protection (since v3.1)
- `ws --help`/`-h` -> prints usage, exit 0; unknown arguments starting with `-` -> error, exit 2.
  Neither is treated as a search query.
- **Anti-recursion**: a nested ws/codex call inside a codex session is blocked by
  /tmp/codex-recursion-guard (PID detection), exit 2, with a message guiding codex to use the
  built-in web search tool. "Search --help returning junk" and nested loops no longer happen.

## Output contract
codex returns: search results (each with **title + URL + summary**) + a short quality/relevance
self-assessment.
- When answering the user, **source URLs are mandatory** (`[title](url)` form).
- Note that codex's banner / `web search:` tool traces are normal (proof it actually searched);
  use the final answer when replying to the user.

## Cost and latency
- Each search consumes DeepSeek tokens (usage-based billing, roughly 10k–20k tokens per search),
  and codex cold start is slow (tens of seconds or more).
- Powerful but not free: this is the price of the default path.

## Files
- shim: `/var/minis/shared/codex-lab/codex-search.sh` (symlinks `/usr/local/bin/web-search`,
  `/usr/local/bin/ws`)
- the old DDG/Bing implementation still exists at `/var/minis/shared/web-search/web-search.py`
  (symlinks repointed; file not deleted)
- codex: `/var/minis/shared/codex-lab/codex-0139/codex` + `codex-home/config.toml`
  (DeepSeek key is here; do not leak it)
```

---

## 3.3 powerpoint-pro (/var/minis/skills/powerpoint-pro/SKILL.md)

> The full 200-line version is in the original file. The following is the condensed version
> (to restore the original: extract the whole directory from the backup tar, see 06).
> If there is no backup tar, rebuild with the core rules below:

```markdown
---
name: powerpoint-pro
description: >-
  Generate .pptx presentations directly with python-pptx. This skill only provides the
  necessary technical guardrails, readability, and file-compatibility constraints; it does
  not assume any aesthetic, brand style, layout preference, or color direction. All
  non-essential visual and design decisions are driven by user requirements.
  Trigger keywords: ppt, pptx, powerpoint, slides, deck, presentation, report.
---

# PowerPoint Pro — generate PPTX directly with python-pptx

## Technical baseline (must follow)
- Canvas: default 16:9 = 13.333" × 7.5" (unless the user requests another ratio)
- Text must not overflow/overlap/get clipped; if it does not fit -> condense text -> enlarge the
  box -> split the slide -> shrink font only as a last resort
- Font sizes: body ≥14pt (projector ≥18pt), titles ≥20pt, KPI 32–44pt, captions ≥11pt
- Contrast: body vs background ≥ WCAG 4.5:1 reference
- Fonts: Arial/Calibri/Aptos/Helvetica/Segoe UI; a user-specified brand font wins
- Safe margins: main content 0.5"–0.7" from the edges
- Density: ≤600 characters per box, ≤5 main bullet items
- Charts: avoid 3D charts (information distortion + renderer differences), excessive gridlines,
  and overly dense data labels

## Design decisions (the user decides; no default aesthetic)
Colors/light-dark/brand colors/whitespace/font style/rounded corners/shadows/gradients/cards/
minimal/business/tech/editorial/playful/image ratio/layout density/decoration — all follow user
requirements. When the user does not specify, use a neutral default (clear structure, no overlap,
readable, ordinary fonts) — **not a fixed design language**.

## Theme (technical fallback, not an aesthetic recommendation)
The built-in modern_blue / dark_tech / warm_corporate are only optional presets. The CLI
requiring --theme is a technical parameter. When the user specifies brand colors, follow the
user's requirement.

## Generation
```bash
pptx-gen --theme modern_blue --output /var/minis/workspace/demo.pptx
pptx-gen --input /tmp/deck.json --theme dark_tech --output /var/minis/workspace/deck.pptx
```
- Layouts: bullets (items) / cards (columns) / metrics (metrics)
- Checks: file exists, .pptx extension, canvas 13.333×7.5, no overflow, python-pptx can re-read it
```

**Attached script**: `/var/minis/skills/powerpoint-pro/scripts/generate_pptx.py` (297 lines,
pptx-gen). Restore from the backup tar (see 06). Dependencies: `apk add py3-pptx` or
`pip install python-pptx`.

**Related profiles**: /var/minis/shared/slides-profiles/ (base-16x9.pptx +
power-design-20.json + bio-cyber.json + slides-schema.json)

---

## 3.4 skill-creator (/var/minis/skills/skill-creator/SKILL.md)

> Official skill template, 92 lines. Condensed:

```markdown
---
name: skill-creator
version: 2.1.0
description: Guide for creating effective skills. This skill should be used when users want to create a new skill (or update an existing skill) that extends the agent's capabilities with specialized knowledge, workflows, or tool integrations.
---

# Skill Creator

## Core Principles
- **Concise is Key**: the context window is a shared resource; only add what the agent does not
  already know, do not re-explain.
- **Degrees of Freedom**: high freedom (pure text guidance) ↔ low freedom (fixed scripts)
  depending on how fragile the task is.

## Anatomy
```
skill-name/
├── SKILL.md (required: YAML frontmatter with name+description; description is the trigger mechanism)
└── scripts/ references/ assets/ (optional)
```
- SKILL.md body <500 lines; split into reference files beyond that
- Progressive Disclosure: metadata (~100 words) -> body (<5k words) -> resources (on demand)

## Process
1. Understand (user examples) 2. Plan 3. Create 4. Test 5. Iterate
- the description must include all trigger keywords
- use the imperative mood
```

---

## 3.5 Disabled skills (do not restore unless the user asks)

Archive area `/var/minis/shared/disabled-skills/`:
- slides-extract/build/full/edit/audit/critique/polish (agent-slides series)
- power-design (73 brand DNA + 20 rules)
- web-research (Tavily/Brave/Exa routing; free tier proven unusable)
- AGENTS-ppt-workflow.md (old PPT workflow section)

Restore method: move the directory back to /var/minis/skills/ + restore the corresponding
AGENTS.md section.
