# 01 — Pitfall Guide (every pitfall we hit + fixes)

> Go through each item when reinstalling on a new device; especially the ⚠️ items are the
> ones that can hard-block you.

## A. Core Codex pitfalls

### ⚠️ 1. Official 0.148/0.149 binaries panic on iSH
```
thread 'codex-main' panicked at utils/rustls-provider/src/lib.rs:27:9:
installed rustls crypto provider must support ECDSA_NISTP521_SHA512
```
- **Cause**: the official release binary embeds a rustls provider inconsistent with its own
  Cargo.lock (assert P-521 check, an issue in the official Bazel build pipeline). Introduced by
  PR #27706 (2026-06-10); earlier versions are unaffected.
- **Fix**: use **rust-v0.139.0** (the last stable release before the PR; pure ring, no assert).
  0.139.0 is verified to work completely normally.
- **Do not try**: LD_PRELOAD (binary is statically linked, ineffective); binary patching (NOP-ing
  the assert does not help, the provider is genuinely missing); a local proxy to bypass TLS
  (the panic happens before any connection).

### ⚠️ 2. ring TLS handshake fails on iSH (codex cannot reach any https endpoint)
- Symptom: `stream disconnected before completion: error sending request for url (https://...)` +
  infinite `Reconnecting... 1/5` retries
- **But curl/OpenSSL work completely normally** (curl can reach the DeepSeek API directly)
- **Cause**: ring's TLS implementation fails during the handshake under iSH's emulation
- **Fix**: **local TLS bridge** — codex connects to `http://127.0.0.1:8787/`, and a Python
  (OpenSSL) process forwards to `https://api.deepseek.com`. See tls_bridge.py in 02.

### ⚠️ 3. wire_api must be `"responses"`
- `wire_api = "chat"` reports: `` `wire_api = "chat"` is no longer supported `` (removed since 0.139)
- DeepSeek **supports** the `/responses` endpoint (verified with a direct curl), so `responses` works.

### ⚠️ 4. effort values: DeepSeek supports 7 levels, `ultra` does not work
- Allowed: `none / minimal / low / medium / high / xhigh / max`
- `ultra` → API returns 400 `unknown variant 'ultra'` (the Codex enum has ultra but DeepSeek rejects it)

### ⚠️ 5. codex resume needs a TTY
- `codex resume <id>` (interactive) on a non-TTY shell reports `Error: stdin is not a terminal`
- **For headless**: `codex exec resume <id> "prompt"` / `codex exec resume --last "prompt"`
  (these do not need a TTY; memory is verified to work)
- `codex exec resume` does not accept the `--sandbox` flag (sandbox is already set in config.toml)

### ⚠️ 6. exec is blocked outside a git repo
- `Not inside a trusted directory and --skip-git-repo-check was not specified.`
- Fix: add `--skip-git-repo-check`, or run inside a git repo (`git init` + one commit is enough)

### ⚠️ 7. Timeouts: long codex tasks can run close to 10 minutes
- `timeout 120` cuts tasks off (Terminated + tokens burned with no result)
- Real tasks should always use `timeout 900` (15 minutes = the hard upper limit of the shell tool)
- Short timeouts are only for quick probes (reply OK etc.)

### ⚠️ 8. Harmless WARNING printed on every run
```
WARNING: failed to clean up stale arg0 temp dirs: Not a directory (os error 20)
ERROR codex_core_skills::manager: failed to install system skills: ... Not a directory
```
- iSH lacks part of the /proc semantics; **does not affect functionality**, ignore it.

### 9. The exec output repeats the reply at the end
- Normal behavior (stdout print + final summary), not a bug.

### 10. codex doctor reports auth ✗ when there is no key
- Normal (not logged in); as long as exec produces a result, connectivity works.

## B. General iSH / Alpine pitfalls

### ⚠️ 11. BusyBox grep does not support `--include`
- `grep --include="*.rs"` errors out. Use `grep -r ... . | grep -v target` or `find ... -exec grep`.
- No globstar (`**` does not work); use `find <dir> -name '*.ext'`.

### ⚠️ 12. pip cannot install large packages (no musllinux aarch64 wheels)
- numpy/pandas/pillow/matplotlib/scipy: always use `apk add py3-numpy py3-pandas py3-pillow py3-matplotlib py3-scipy`
- pip is only for pure-Python packages (requests etc.)
- matplotlib must use `matplotlib.use('Agg')` (no display server)

### ⚠️ 13. npx segfaults on iSH
- Any npx command can die (even cowsay segfaults)
- Fix: install globally with npm (`npm install -g <pkg>`), run dist/index.js directly with node

### ⚠️ 14. Background services must redirect stdout/stderr
- `python3 server.py &` without redirect silently dies of SIGPIPE when the shell exits
- Correct: `nohup python3 server.py > /tmp/x.log 2>&1 &`

### ⚠️ 15. pgrep/pkill are unreliable
- /proc keeps stale dead processes; pgrep can match fake-alive processes
- Liveness must be determined by actual probing (curl ping etc.), never rely on pgrep

### ⚠️ 16. iSH has no job control
- `bash -i` exits with 2 immediately; ^C kills the whole shell
- To interrupt, send a signal (SIGINT) to the child process, do not send ^C

### 17. Disk writes are slow (~0.85MB/s) + iOS storage is tight
- Avoid large downloads / accumulating large files; offload heavy work
- Mounting external folders under /var/minis/mounts/ does not free iSH internal space (same volume)

### 18. Processes are not guaranteed after the app is suspended
- Surviving across shell_execute calls works (setsid), but is unreliable after the app goes to background
- Use Apple Shortcuts for scheduled tasks, do not rely on crontab

### 19. `$$` expands to a PID in minis-mcp-cli --env
- To pass a `$VAR` reference, do not escape with $$; point the config at the environment variable name directly

### 20. minis:// URLs must be percent-encoded
- Chinese/space filenames that are not encoded break Markdown rendering
- Use the encoded minis_url returned by the tool

### 21. psh restore source: /var/minis/shared/psh-kit/
- The original psh v3 (bash + FIFO, 196 lines) is at **/var/minis/shared/psh-kit/psh**
  (restored from it on 2026-08-23)
- Do not rewrite it yourself! Correct restore: `cp /var/minis/shared/psh-kit/psh /root/.local/bin/psh && chmod +x`
- It was once rewritten in Python (453-line socket version) — that was not a restore, it was
  abandoned in favor of the original
- env.sh / env-bootstrap are also in psh-kit (/root/.local/etc/env.sh, /root/.local/bin/env-bootstrap)
- GUIDE.md is outdated (v2 manual); ALL-IN-ONE.md is the v3 full text

### 27. Stale psh FIFOs make start hang forever
- Symptom: `psh start` blocks indefinitely (a FIFO that exists but has no reader makes an open-for-write block forever)
- Trigger: an old session died without stop → /tmp/psh.fifo, /tmp/psh.out remain
- Fix: `kill -9 $(ps -A | grep 'psh start' | awk '{print $1}') 2>/dev/null; rm -f /tmp/psh.fifo /tmp/psh.out /tmp/psh.off` then start again
- Recommended: before every psh use, `ls /tmp/psh.fifo` and clean leftovers (or just run `psh stop` once)

## C. Search pitfalls (web-search)

### ⚠️ 22. Free search engines are fully blocked on this network
- DDG 202-blocks this machine's egress IP entirely; Bing anti-scraping pollutes results
  (200 but returns other people's queries)
- DDG/Bing/brave-MCP/web-research are completely disabled
- **The only path**: codex built-in web search (DeepSeek native web_search tool), see 02/03

### ⚠️ 23. Do not fall back when codex search fails
- Report the failure directly to the user (bridge down / key invalid); never silently swap in a
  junk engine

### 24. Search cost
- Roughly 10k–20k tokens per search (DeepSeek usage-based billing); cold start takes tens of seconds

### 28. Search/calls were not continuous (fixed: global chatroom binding)
- Old versions: every `web-search` / `codex exec` = a brand-new codex session → follow-ups re-search / lose context
- User design requirement: **codex sessions map 1:1 to Minis chatrooms** — within the same chatroom
  (unless notified), every codex call defaults to resuming the same session; a new chatroom opens a
  new one; **unlimited turns** (no automatic rotation)
- Implementation: codex-resolve.sh (reads the current chatroom id from minis-sessions-cli) +
  codex-ds.sh v2 + codex-search.sh v3 share /var/minis/shared/codex-lab/codex-chat-map
- Forced new: `codex exec --new` / `web-search --new` / CODEX_NEW_SESSION=1
- Verified: 3 consecutive exec calls in the same chatroom (including web-search follow-ups) all
  resumed the same session, codex remembered the context ("42"); after --new, codex answered
  "missing context", proving it was a new session
- Pitfall: the wrapper must auto-add --skip-git-repo-check (shell_execute cwd is not a git repo);
  resume failure auto-falls back to a new session

### 29. `ws --help` was treated as a query + nested recursion (fixed, v3.1)
- The old shim did not handle --help → `ws --help` made codex search "--help" and return junk;
  codex inside a search task saw the ws command and ran `ws --help` itself → nested new codex
  sessions → recursion (measured: 20s idle spin + 3 short-lived sessions)
- Fix: ① shim handles --help/-h (prints usage, exit 0) + unknown arguments starting with `-`
  error out with exit 2 (no longer treated as queries); ② anti-recursion: codex-ds.sh uses
  /tmp/codex-recursion-guard (writes its own PID + kill -0 check), a nested exec sees the guard
  PID still alive and refuses (exit 2), guiding codex to use the built-in web search tool;
  trap EXIT clears the guard automatically
- Uses a PID instead of a timestamp: once the wrapper is killed the guard immediately expires,
  so later calls are never wrongly locked
- Verified: nested `ws --help` only returns usage (no new sessions); a nested ws real query is
  blocked and codex proactively says "switch to the built-in web search"

### 30. DeepSeek web_search has a platform-level content filter (cannot be disabled from our side)
- Sensitive/adult queries (tested: creamyspot): the DeepSeek native web_search tool only returns
  safe mismatched results
- The codex agentic loop lifts itself: reword the query + use shell curl against
  Bing/Baidu/DDG to bypass → finds the real results
- This filter is on the DeepSeek server side; no config/shim/key switch exists; the bypass
  behavior is codex's own strategy — do not try to "lift" it at the platform layer

## D. PPT pitfalls

### ⚠️ 25. Canvas ratio
- python-pptx defaults to 10×7.5" (4:3); 16:9 needs 13.333×7.5"
- Template: /var/minis/shared/slides-profiles/base-16x9.pptx

### ⚠️ 26. Style neutrality
- PPT skills never assume an aesthetic by default; user-specified style wins
- generate_pptx.py's --theme is required (no default) — that is a technical parameter, not a design judgment
