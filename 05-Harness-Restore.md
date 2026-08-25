# 05 — Harness Toolchain Restoration and Symlink Commands

> harness = the previously established agent self-discipline toolchain (`/var/minis/shared/harness/*.py`)
> The scripts are fairly long (~3,150 lines total) and **manual copying is not recommended** — restore from the backup tarball (see 06-OneTime-Backup-Script.md).
> Below are the symlink restoration commands, tool inventory with descriptions, and selftest procedures.

---

## 1. Symlink Restoration (New Device)

```sh
ln -sf /var/minis/shared/harness/guard.py        /usr/local/bin/guard
ln -sf /var/minis/shared/harness/agentrun.py     /usr/local/bin/agentrun
ln -sf /var/minis/shared/harness/agentverify.py  /usr/local/bin/agentverify
ln -sf /var/minis/shared/harness/agentd.py       /usr/local/bin/agentd
ln -sf /var/minis/shared/harness/task.py         /usr/local/bin/task
ln -sf /var/minis/shared/harness/tooloffload.py  /usr/local/bin/tooloffload
ln -sf /var/minis/shared/harness/agentcompact.py /usr/local/bin/agentcompact
```

---

## 2. Tool Inventory

| Tool | Lines | Purpose | selftest |
|---|---|---|---|
| guard.py | 239 | Security guardrail: path lock (`realpath` verification inside `/var/minis`, `/tmp`), secret masking (`api_key`/`token`/private keys -> `****`), dangerous operation classification (`rm`/`git push`/`dd`/`POST` without `--yes` rejected with exit 3) | `guard selftest` |
| agentrun.py | 742 | Run state machine (CREATED -> UNDERSTAND -> PLAN -> ACT -> OBSERVE -> VERIFY -> DONE; `events.jsonl` append-only; error fingerprint; semantic no-progress; DONE can only transition from VERIFY) | `agentrun selftest` |
| agentverify.py | 360 | CompletionVerifier: criteria syntax `exists:path` / `cmd:cmd` / `contains:path:sub` / `json:path` / `pycompile:path` / `sources:N` / `domains:N` / `citations:N`; all passing -> evidence + VERIFY, failure exit 2 | `agentverify selftest` |
| agentd.py | 638 | Persistent shell/PTY: Unix socket JSON Lines; session = persistent bash; job = background process group; iSH lacks job control -> interrupt uses SIGINT to scan `/proc` child processes | T1-T7 (see inside script) |
| task.py | 470 | **Unified Frontend**: start / next / do / add / phase / check / done / fix / wait / resume / compact / checkpoint / budget / show / list / where / offload — run `task next` at the start of each turn to get the digest | `task selftest` |
| tooloffload.py | 270 | Long output offloading: envelope `{ok, summary, important_output, full_output_ref, exit_code, duration_ms, truncated}`; HeadTailBuffer truncation (head half + tail half) | `tooloffload selftest` |
| agentcompact.py | 230 | Run store compression: Codex-style 4-part handoff summary (progress+decisions / context+constraints+preferences / remaining steps / artifact references); threshold=15 events | `agentcompact selftest` |
| feasibility_agentd.py | 203 | agentd feasibility tests | `python3 feasibility_agentd.py` |

---

## 3. env-bootstrap (Used to Rebuild psh)

> The original psh v3 resides at **/var/minis/shared/psh-kit/psh** (bash + FIFO, 196 lines). Verified fully passing 10 checks after restoration from psh-kit on 2026-08-23.
> **Restoration = copy directly, do not rewrite**:
```sh
cp /var/minis/shared/psh-kit/psh /root/.local/bin/psh && chmod +x /root/.local/bin/psh
ln -sf /root/.local/bin/psh /usr/local/bin/psh
```
> `env.sh` and `env-bootstrap` are also located in `psh-kit`; copy them over similarly:
```sh
mkdir -p /root/.local/etc /root/.local/bin
cp /var/minis/shared/psh-kit/env.sh /root/.local/etc/env.sh
cp /var/minis/shared/psh-kit/env-bootstrap /root/.local/bin/env-bootstrap && chmod +x /root/.local/bin/env-bootstrap
ln -sf /root/.local/bin/env-bootstrap /usr/local/bin/env-bootstrap
```
> ⚠️ Pitfall: Stale `/tmp/psh.fifo` + dead readers cause `psh start` to hang indefinitely. Run `rm -f /tmp/psh.fifo /tmp/psh.out /tmp/psh.off` first before start (see pitfall #27 in 01-Pitfalls-Guide.md).
> Verification: `psh start` -> `psh status` (alive) -> `psh run 'echo hi'` -> `psh run 'cd /tmp' && psh run 'pwd'` (`/tmp`) -> bg/wait/tail/tasks -> timeout auto-rebuild -> stop.
> Usage: start/stop/status/run [-t sec]/send/bg/wait/tail/tasks. Single-line commands; `run` starting with `exit` = stop.

---

## 3b. env-bootstrap Contents (Rebuild from this if psh-kit is also lost)

> Original `env-bootstrap` (`/var/minis/shared/psh-kit/env-bootstrap`, identical to `/root/.local/bin/env-bootstrap`):

```sh
#!/bin/sh
# env-bootstrap — one-shot toolchain install for a fresh Minis environment.
# Idempotent: safe to run any time. Run: env-bootstrap
set -e
echo "[bootstrap] installing core toolchain (this may take a few minutes)..."
apk add --no-cache git jq py3-pip nodejs npm tmux vim ripgrep fd sqlite htop curl wget bash file openssh-client 2>&1 | tail -1
echo "[bootstrap] tool check:"
for c in git jq pip3 python3 node npm tmux vim rg fd sqlite3 htop curl wget ssh bash; do
  if command -v "$c" >/dev/null 2>&1; then echo "  ok    $c"; else echo "  MISS  $c"; fi
done
echo "[bootstrap] linking psh + env.sh..."
mkdir -p /root/.local/bin /root/.local/etc
ln -sf /root/.local/bin/psh /usr/local/bin/psh 2>/dev/null || true
ln -sf /root/.local/bin/env-bootstrap /usr/local/bin/env-bootstrap 2>/dev/null || true
echo "[bootstrap] done. Add '. /root/.local/etc/env.sh' at the start of shell calls."
```

`env.sh` (original contents):
```sh
# sourced at the start of agent shell calls (dot-source it: . /root/.local/etc/env.sh)
export PATH="$HOME/.local/bin:$PATH"
alias ll='ls -la' 2>/dev/null
alias psho='tail -f /tmp/psh.out' 2>/dev/null
export PSH_TIMEOUT_DEFAULT=120
```

---

## 4. Other System Symlinks (Follow on New Device)

```sh
# codex + search
ln -sf /var/minis/shared/codex-lab/codex-ds.sh      /usr/local/bin/codex
ln -sf /var/minis/shared/codex-lab/codex-search.sh  /usr/local/bin/web-search
ln -sf /var/minis/shared/codex-lab/codex-search.sh  /usr/local/bin/ws

# pptx-gen (if restoring powerpoint-pro)
ln -sf /var/minis/skills/powerpoint-pro/scripts/generate_pptx.py /usr/local/bin/pptx-gen
```

---

## 5. slides-profiles (PPT Canvas Profiles)

`/var/minis/shared/slides-profiles/`:
- `base-16x9.pptx` — 16:9 blank template (13.333×7.5")
- `power-design-20.json` — design QA profile (min 18pt, margin 0.67", <=5 bullets, overlap<=0.15, no effects; after style neutralization)
- `bio-cyber.json` — alternative profile
- `slides-schema.json` — slides JSON schema

New device restoration: extract the entire directory from the backup tarball (see 06-OneTime-Backup-Script.md).
