# 04 — Harness Toolchain and psh (100% Identical)

> The 8 harness Python files total ~3,150 lines — **manual copying is not recommended**; restoring from tar (see the packaging command in 00) or copying from the real device is safest.
> The full text of psh is provided below (196 lines of bash, a critical tool).

---

## 4.1 Harness Tools (`/var/minis/shared/harness/`)

| File | Lines | Purpose | selftest |
|---|---|---|---|
| guard.py | 239 | Security guardrail: path lock, secret masking (api_key/token -> ****), dangerous operation classification (rm/git push/dd/POST without --yes rejected with exit 3) | `guard selftest` |
| agentrun.py | 742 | Run state machine (events.jsonl append-only; error fingerprint; DONE can only transition from VERIFY) | `agentrun selftest` |
| agentverify.py | 360 | CompletionVerifier: criteria syntax exists:/cmd:/contains:/json:/pycompile:/sources:N/domains:N/citations:N | `agentverify selftest` |
| agentd.py | 638 | Persistent shell/PTY: Unix socket JSON Lines; session/job; iSH lacks job control -> SIGINT scans /proc | `python3 feasibility_agentd.py` |
| task.py | 470 | Unified frontend: start/next/do/add/phase/check/done/fix/wait/resume/compact/checkpoint | `task selftest` |
| tooloffload.py | 270 | Long output offloading: envelope + full_output_ref + HeadTailBuffer | `tooloffload selftest` |
| agentcompact.py | 230 | Run store compression: 4-part handoff summary; threshold=15 events | `agentcompact selftest` |
| feasibility_agentd.py | 203 | agentd feasibility tests | `python3 feasibility_agentd.py` |

**Restore**: `cp -r` the entire directory + symlink (see section 3.2 in 03-Minis-Directory-and-Skills.md). **All selftests passing = healthy toolchain.**

---

## 4.2 psh (`/root/.local/bin/psh`, 196 lines bash, full text)

```bash
#!/bin/bash
# psh v3 — persistent stateful shell for the Minis agent (iSH-hardened).
# v2 used pgrep-based liveness; on iSH pgrep/pkill are unreliable (stale /proc
# entries, non-standard STAT, kills that silently fail), which caused stop/start
# to silently skip rebuilds and run() to hang 120s replaying old output.
# v3 uses PROBE-based liveness: a round-trip echo through the FIFO that must
# appear in OUT within 4s. A session is only "alive" if a reader actually evals.
#
#   psh start|stop|status
#   psh run [-t sec] 'single-line command'  run synchronously, print new output
#   psh send 'cmd'                           fire-and-forget (no wait)
#   psh bg <name> 'single-line command'      background task -> /tmp/tasks/<name>.log
#   psh wait <name> [-t sec]                 block until task done (prints log)
#   psh tail <name> [n]                      last n lines of a task log
#   psh tasks                                list tasks
# Commands must be single-line; for multi-line logic write a script file first.
FIFO=/tmp/psh.fifo; OUT=/tmp/psh.out; OFF=/tmp/psh.off
RUNNER=/tmp/psh-runner.sh; TASKDIR=/tmp/tasks
PAT="bash $RUNNER"; KA='sleep 999999'
mkdir -p "$TASKDIR"

# --- probe: true liveness test (round-trip echo through the FIFO) ---
probe() {
  local m="PSHPROBE_$(date +%s%N)_$RANDOM"
  timeout 2 printf 'echo %s\n' "$m" > "$FIFO" 2>/dev/null || return 1
  local s=$(date +%s)
  while [ $(( $(date +%s) - s )) -lt 4 ]; do
    tail -c 800 "$OUT" 2>/dev/null | grep -q "$m" && return 0
    sleep 1
  done
  return 1
}

writestate() { wc -c < "$OUT" > "$OFF" 2>/dev/null || echo 0 > "$OFF"; }

start() {
  if [ -e "$FIFO" ] && [ -e "$OUT" ] && probe; then
    writestate   # consume probe echo from OUT
    echo "[psh] session alive"
    return 0
  fi
  # rebuild — best-effort kill (unreliable on iSH; rare leaks are tolerated)
  pkill -9 -f "$PAT" 2>/dev/null
  pkill -9 -f "$KA" 2>/dev/null
  for p in $(ps -A -o pid=,args= 2>/dev/null | grep -F "$RUNNER" | awk '{print $1}'); do
    kill -9 "$p" 2>/dev/null
  done
  rm -f "$FIFO" "$OUT" "$OFF"
  # always regenerate: runner version must match psh version (__rc capture)
  printf '#!/bin/bash\nwhile IFS= read -r line; do eval "$line"; __rc=$?\ndone\n' > "$RUNNER"
  chmod +x "$RUNNER"
  rm -f "$FIFO"; mkfifo "$FIFO" || { echo "[psh] mkfifo failed"; return 1; }
  setsid sh -c "sleep 999999 > $FIFO" </dev/null >/dev/null 2>&1 &
  setsid bash "$RUNNER" < "$FIFO" > "$OUT" 2>&1 &
  sleep 1
  if probe; then
    writestate
    echo "[psh] session started"
  else
    echo "[psh] start FAILED (no live reader after rebuild)"
    return 1
  fi
}

stop() {
  pkill -9 -f "$PAT" 2>/dev/null
  pkill -9 -f "$KA" 2>/dev/null
  rm -f "$FIFO" "$OFF"
  echo "[psh] stopped (on iSH the old reader may linger until next rebuild)"
}

status() {
  if [ -e "$FIFO" ] && probe; then
    writestate
    local os=$(wc -c < "$OUT" 2>/dev/null || echo 0)
    local of=$(cat "$OFF" 2>/dev/null || echo 0)
    echo "[psh] alive (probe ok) out=${os}B unread=$((os-of))B"
  else
    echo "[psh] dead (probe failed)"
  fi
}

fwrite() { # payload may contain newlines; rebuilds session once if dead
  timeout 15 printf '%s\n' "$1" > "$FIFO" 2>/dev/null && return 0
  start || return 1
  timeout 15 printf '%s\n' "$1" > "$FIFO" 2>/dev/null
}

run() {
  local t=120 cmd=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -t) t=$2; shift 2;;
      *) cmd="$1"; shift;;
    esac
  done
  [ -n "$cmd" ] || { echo "[psh] usage: psh run [-t sec] 'cmd'"; return 1; }
  if [[ "$cmd" =~ ^exit([[:space:]]|$) ]]; then
    stop
    return 0
  fi
  start || return 1
  local off=$(cat "$OFF" 2>/dev/null || echo 0)
  local m="PSHMARK_$(date +%s%N)_$$_$RANDOM"
  local payload
  printf -v payload '%s\necho; echo "%s:$__rc"' "$cmd" "$m"
  fwrite "$payload" || { echo "[psh] FIFO write failed"; return 1; }
  off=$(cat "$OFF" 2>/dev/null || echo 0)
  local s=$(date +%s)
  while [ $(( $(date +%s) - s )) -lt "$t" ]; do
    tail -c +$((off+1)) "$OUT" 2>/dev/null | grep -q "$m" && break
    sleep 1
  done
  local out=$(tail -c +$((off+1)) "$OUT" 2>/dev/null)
  wc -c < "$OUT" > "$OFF" 2>/dev/null || true
  local mark=$(printf '%s\n' "$out" | grep "^$m:" | tail -1)
  printf '%s\n' "$out" | sed "/^$m:[0-9]*$/d"
  if [ -z "$mark" ]; then
    pkill -9 -f "$PAT" 2>/dev/null
    rm -f "$FIFO" "$OFF"
    echo "[psh] TIMEOUT after ${t}s (session killed; next call rebuilds fresh)"
    return 1
  fi
  local ex="${mark#*:}"
  if [ -n "$ex" ] && [ "$ex" != "0" ]; then
    echo "[psh] exit=$ex"
    return 1
  fi
  return 0
}

send() { start || return 1; fwrite "$1" && echo "[psh] sent"; }

bg() {
  local name="$1" cmd="$2"
  [ -n "$cmd" ] || { echo "usage: psh bg <name> 'cmd'"; return 1; }
  start || return 1
  local log="$TASKDIR/$name.log"
  rm -f "$log"
  local esc=$(printf '%s' "$cmd" | sed "s/'/'\\\\''/g")
  local payload
  printf -v payload "setsid bash -c '(%s) >> %s 2>&1; echo TASKDONE_%s >> %s' </dev/null &" "$esc" "$log" "$name" "$log"
  fwrite "$payload" || { echo "[psh] task write failed"; return 1; }
  local s=$(date +%s)
  while [ $(( $(date +%s) - s )) -lt 20 ] && [ ! -s "$log" ]; do sleep 1; done
  if [ -s "$log" ]; then
    echo "[psh] task '$name' running -> $log"
  else
    echo "[psh] task '$name' FAILED to start"
    return 1
  fi
}

taskwait() {
  local name="$1" t=600
  [ "$2" = "-t" ] && t=$3
  local log="$TASKDIR/$name.log"
  [ -f "$log" ] || { echo "[psh] no log for '$name'"; return 1; }
  local s=$(date +%s)
  while [ $(( $(date +%s) - s )) -lt "$t" ]; do
    grep -q "TASKDONE_$name" "$log" 2>/dev/null && { cat "$log"; return 0; }
    sleep 1
  done
  echo "[psh] wait TIMEOUT ${t}s, last lines:"
  tail -n 5 "$log"
  return 1
}

tasktail() {
  tail -n "${2:-20}" "$TASKDIR/$1.log" 2>/dev/null || echo "[psh] no log for '$1'"
}

tasks() {
  local f found=""
  for f in "$TASKDIR"/*.log; do
    [ -e "$f" ] || break
    found=1
    if grep -q "TASKDONE_" "$f" 2>/dev/null; then s="done  "; else s="running"; fi
    echo "  $s  $(basename "$f" .log)"
  done
  [ -z "$found" ] && echo "[psh] no tasks"
  return 0
}

case "${1:-}" in
  start)  start;;
  stop)   stop;;
  status) status;;
  run)    shift; run "$@";;
  send)   shift; send "$@";;
  bg)     shift; bg "$@";;
  wait)   shift; taskwait "$@";;
  tail)   shift; tasktail "$@";;
  tasks)  tasks;;
  *)      sed -n '2,17p' "$0";;
esac
```

## 4.3 env.sh + env-bootstrap (`/root/.local/`)

**env.sh** (`/root/.local/etc/env.sh`):
```sh
# sourced at the start of agent shell calls (dot-source it: . /root/.local/etc/env.sh)
export PATH="$HOME/.local/bin:$PATH"
alias ll='ls -la' 2>/dev/null
alias psho='tail -f /tmp/psh.out' 2>/dev/null
export PSH_TIMEOUT_DEFAULT=120
```

**env-bootstrap** (`/root/.local/bin/env-bootstrap`):
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

Installation:
```sh
mkdir -p /root/.local/bin /root/.local/etc /tmp/tasks
chmod +x /root/.local/bin/psh /root/.local/bin/env-bootstrap
ln -sf /root/.local/bin/psh /usr/local/bin/psh
ln -sf /root/.local/bin/env-bootstrap /usr/local/bin/env-bootstrap
```

## 4.4 psh Verification Checklist (10 Items)

```sh
rm -f /tmp/psh.fifo /tmp/psh.out /tmp/psh.off   # ⚠️ Stale FIFO will cause start to hang indefinitely
psh start          # [psh] session started
psh status         # alive (probe ok)
psh run 'echo hi'  # hi
psh run 'cd /tmp' && psh run 'pwd'   # /tmp (cwd continuity)
psh run 'export X=42' && psh run 'echo $X'   # 42 (env continuity)
psh bg t1 'sleep 3; echo done' && psh wait t1 && psh tail t1 2 && psh tasks
psh run -t 5 'sleep 30'   # TIMEOUT after 5s
psh run 'echo rebuilt'    # Auto-rebuilt
psh stop
```

> ⚠️ On iSH, `/root/.local` disappears after reboot (empirically confirmed 2026-08-24) — psh/env-bootstrap must be restored from `psh-kit` via `cp`. On a computer this issue does not exist (standard filesystem persistence).
