#!/bin/bash
# codex-ds: Codex 0.139 + DeepSeek via local TLS bridge (for iSH)
# ring TLS fails on iSH, so we bridge plain-HTTP -> https://api.deepseek.com via Python/OpenSSL.
#
# v2 (2026-08-23): codex sessions map 1:1 to Minis chatrooms.
#   - within the same chatroom, `codex exec "prompt"` defaults to resuming the same codex session
#   - a new chatroom -> automatically opens a new session
#   - forced new: `codex exec --new "prompt"` (or CODEX_NEW_SESSION=1)
#   - no turn/time limit; fall back to a new session only when resume really fails
#   - `codex exec resume <id> ...` / other subcommands (--version/doctor/mcp-server...) -> pass through as-is
#
# v2.1 (2026-08-23): anti-recursion.
#   - calling codex/ws again inside a codex session (sandbox shell) creates nested sessions and infinite loops
#   - the GUARD file records this wrapper's PID; a nested call that sees the guard PID still alive is refused (exit 2)
#   - the guard uses a PID instead of a timestamp: once the wrapper is killed the guard immediately expires, so later calls are never wrongly locked

BRIDGE_PORT=8787
BRIDGE_LOG=/tmp/tls_bridge.log
BRIDGE_PID=/tmp/tls_bridge.pid
CODEX=/var/minis/shared/codex-lab/codex-0139/codex
RESOLVER=/var/minis/shared/codex-lab/codex-resolve.sh
MAP=/var/minis/shared/codex-lab/codex-chat-map
GUARD=/tmp/codex-recursion-guard
export CODEX_HOME=/var/minis/shared/codex-lab/codex-home

# Start the bridge (if not running). Note: on iSH the bridge can become a zombie (the process
# stays alive but the socket stops responding, occupying the port so a new bridge cannot bind)
# — liveness detection must therefore be a double check: "PID alive + curl responds".
bridge_alive() {
  curl -s --max-time 2 "http://127.0.0.1:$BRIDGE_PORT/" >/dev/null 2>&1
}
if ! bridge_alive; then
  # An old bridge process exists but is not responding -> zombie, kill it first
  if [ -f "$BRIDGE_PID" ]; then
    OLD_PID=$(cat "$BRIDGE_PID" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      echo "[codex] old bridge (pid $OLD_PID) is a zombie; cleaning up and restarting" >&2
      kill -9 "$OLD_PID" 2>/dev/null
      sleep 1
    fi
  fi
  nohup python3 /var/minis/shared/codex-lab/tls_bridge.py > "$BRIDGE_LOG" 2>&1 &
  echo $! > "$BRIDGE_PID"
  sleep 2
  bridge_alive || echo "[codex] warning: bridge started but not responding; TLS may fail" >&2
fi

# Strip the --new flag
NEW=0
args=()
for a in "$@"; do
  if [ "$a" = "--new" ]; then NEW=1; else args+=("$a"); fi
done
set -- "${args[@]}"
[ "$NEW" = "1" ] && export CODEX_NEW_SESSION=1

# Anti-recursion check: for any exec call, if the PID in the guard is still alive, an outer codex session is in progress
if [ "$1" = "exec" ] && [ -f "$GUARD" ]; then
  read -r GPID < "$GUARD" 2>/dev/null
  if [ -n "$GPID" ] && kill -0 "$GPID" 2>/dev/null; then
    echo "[codex] anti-recursion: detected a codex session (pid $GPID) in progress; nested call blocked. You are inside a codex exec environment — use the built-in web search tool directly instead of calling ws/codex." >&2
    exit 2
  fi
fi

# Only exec (not resume/review/help subcommands) does auto-resolve
if [ "$1" != "exec" ] || [ "$2" = "resume" ] || [ "$2" = "review" ] || [ "$2" = "help" ]; then
  exec "$CODEX" "$@"
fi

eval "$("$RESOLVER")"
MODE="${MODE:-new}"
SID="${SID:-}"
TURNS="${TURNS:-0}"
CHAT_ID="${CHAT_ID:-}"

OUT_FILE=$(mktemp /tmp/codex-out.XXXXXX) || OUT_FILE=/tmp/codex-out.$$
rc=0

# Set the guard (record our own PID); trap guarantees it is cleared on both normal and abnormal exit
echo $$ > "$GUARD"
trap 'rm -f "$GUARD"' EXIT

if [ "$MODE" = "resume" ] && [ -n "$SID" ]; then
  echo "[codex] resume session $SID (chatroom $CHAT_ID)" >&2
  "$CODEX" exec resume "$SID" --skip-git-repo-check "${@:2}" > "$OUT_FILE" 2>&1
  rc=$?
  cat "$OUT_FILE"
  # resume failed (no session id in output or exit != 0) -> fall back to a new session
  if [ "$rc" != "0" ] || ! grep -q 'session id:' "$OUT_FILE"; then
    echo "[codex] resume failed; falling back to a new session" >&2
    "$CODEX" exec --skip-git-repo-check "${@:2}" > "$OUT_FILE" 2>&1
    rc=$?
    cat "$OUT_FILE"
  fi
else
  "$CODEX" exec --skip-git-repo-check "${@:2}" > "$OUT_FILE" 2>&1
  rc=$?
  cat "$OUT_FILE"
fi

# Update the mapping
NEW_SID=$(grep -oE 'session id: [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$OUT_FILE" 2>/dev/null | head -1 | awk '{print $3}')
rm -f "$OUT_FILE"
if [ -n "$NEW_SID" ] && [ -n "$CHAT_ID" ]; then
  echo "$CHAT_ID $NEW_SID $(date +%s) $((TURNS + 1))" > "$MAP"
fi
exit $rc
