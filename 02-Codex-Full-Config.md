# 02 — Full Codex Configuration (100% identical, with the complete contents of every file)

> Source: collected from the real iPhone iSH device (2026-08-24). Every file below can be
> copied verbatim.

---

## 2.1 Binary

| Item | Value |
|---|---|
| Version | codex-cli 0.139.0 |
| Source | https://github.com/openai/codex/releases/download/rust-v0.139.0/codex-aarch64-unknown-linux-musl.tar.gz |
| Current hash | `f626dda1db933a39df4a8448ccfc8e53afe15b55e4fee491b6d10a25cc0c1440` (v2 double patch: EINVAL tolerance + tokio SIGCHLD fallback) |
| Original hash | `ed0f6efecf1ba42f4a3bc523d7bafa062451195ab47c02b60a93cb8d569ad2ce` (official, unpatched) |
| v1 patch hash | `923a31a92b15f53a3055896fa6fd727d1fea8b9a8dd9a7bc8cf878ac304fc03f` (EINVAL tolerance only) |

**On a computer (x86_64) use this**:
```
https://github.com/openai/codex/releases/download/rust-v0.139.0/codex-x86_64-unknown-linux-musl.tar.gz
```
**On a computer (aarch64/ARM) use the aarch64 link above.**

Download and install:
```sh
mkdir -p /var/minis/shared/codex-lab/codex-0139
cd /var/minis/shared/codex-lab
curl -fL -o codex.tar.gz <the link above>
tar xzf codex.tar.gz -C codex-0139
mv codex-0139/codex-* codex-0139/codex
chmod +x codex-0139/codex
codex-0139/codex --version   # codex-cli 0.139.0
```

> ⚠️ **On a computer the official unpatched binary is enough** — the v2 patch exists only to work
> around iSH emulation-layer defects; on real Linux the official build works completely normally
> (and is even better, since tokio is untouched). For 100% consistency use the patched one (build
> it yourself; materials are in ish-einval-fix/); for a healthy system use the official original.

---

## 2.2 config.toml (/var/minis/shared/codex-lab/codex-home/config.toml)

```toml
model = "deepseek-v4-flash"
model_provider = "deepseek"
model_reasoning_effort = "xhigh"

# Login via API key (avoids opening the ChatGPT login page)
preferred_auth_method = "apikey"
forced_login_method = "api"

approval_policy = "never"
sandbox_mode = "danger-full-access"
personality = "pragmatic"

[model_providers.deepseek]
name = "deepseek"
base_url = "http://127.0.0.1:8787/"
wire_api = "responses"
experimental_bearer_token = "<DeepSeek API key>"

[projects."/var/minis/shared/codex-lab/testrepo"]
trust_level = "trusted"

[projects."/root"]
trust_level = "trusted"
```

**For a direct DeepSeek connection on a computer (bypassing the bridge)**: change
`base_url = "https://api.deepseek.com/"`. **For 100% consistency**: keep 127.0.0.1:8787 and run
the bridge.

---

## 2.3 tls_bridge.py (/var/minis/shared/codex-lab/tls_bridge.py)

```python
#!/usr/bin/env python3
"""TLS bridge: local http -> https://api.deepseek.com (OpenSSL TLS, works on iSH).
Codex talks plain HTTP to 127.0.0.1:8787; this forwards to DeepSeek over TLS.
"""
import http.server
import http.client
import ssl
import sys

TARGET = "api.deepseek.com"
PORT = 8787

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _forward(self):
        try:
            body = None
            cl = self.headers.get("Content-Length")
            if cl:
                body = self.rfile.read(int(cl))
            conn = http.client.HTTPSConnection(
                TARGET, 443, timeout=120,
                context=ssl.create_default_context(),
            )
            headers = {}
            for k, v in self.headers.items():
                kl = k.lower()
                if kl in ("host", "connection", "accept-encoding", "content-length"):
                    continue
                headers[k] = v
            conn.request(self.command, self.path, body=body, headers=headers)
            resp = conn.getresponse()
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                kl = k.lower()
                if kl in ("transfer-encoding", "connection", "content-length", "keep-alive"):
                    continue
                self.send_header(k, v)
            self.send_header("Connection", "close")
            self.end_headers()
            while True:
                chunk = resp.read(8192)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
            conn.close()
        except Exception as e:
            try:
                self.send_response(502)
                self.end_headers()
                self.wfile.write(str(e).encode())
            except Exception:
                pass

    def do_POST(self):
        self._forward()

    def do_GET(self):
        self._forward()

    def do_OPTIONS(self):
        self._forward()

    def log_message(self, *a):
        pass

if __name__ == "__main__":
    srv = http.server.HTTPServer(("127.0.0.1", PORT), Handler)
    print(f"bridge listening on 127.0.0.1:{PORT} -> https://{TARGET}", flush=True)
    srv.serve_forever()
```

---

## 2.4 codex-ds.sh (/var/minis/shared/codex-lab/codex-ds.sh, wrapper)

```bash
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
```

---

## 2.5 codex-resolve.sh (/var/minis/shared/codex-lab/codex-resolve.sh)

```sh
#!/bin/sh
# codex-resolve — decides whether this codex call should resume or open a new session.
#
# Design (user requirement 2026-08-23):
#   codex sessions map 1:1 to Minis chatrooms.
#   - within the same chatroom, unless explicitly notified, codex calls always resume the same session
#   - a new chatroom -> automatically opens a new codex session
#   - forced new: environment variable CODEX_NEW_SESSION=1, or the wrapper received --new
#   - no turn/time limit: continuity wins; context length is left to codex itself
#     (only fall back to a new session when resume really fails)
#
# Usage (inside the wrapper):
#   eval "$(codex-resolve)"   -> sets MODE=resume|new, SID=<codex-session-id|empty>, TURNS=<n>
#
# State file: /var/minis/shared/codex-lab/codex-chat-map
#   format: <minis_chat_id> <codex_session_id> <last_ts> <turns>

MAP=/var/minis/shared/codex-lab/codex-chat-map

# Get the current Minis chatroom id (first item in list = most recently active = current conversation)
CHAT_ID=$(minis-sessions-cli list --limit 1 2>/dev/null | grep -oE '"session_id" : "[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')

MODE=new
SID=""
TURNS=0
TS=0

if [ -n "$CHAT_ID" ] && [ "$CODEX_NEW_SESSION" != "1" ] && [ -f "$MAP" ]; then
  read -r OLD_CHAT OLD_SID OLD_TS OLD_TURNS < "$MAP"
  if [ "$OLD_CHAT" = "$CHAT_ID" ] && [ -n "$OLD_SID" ]; then
    MODE=resume
    SID="$OLD_SID"
    TURNS="${OLD_TURNS:-0}"
    TS="$OLD_TS"
  else
    echo "[codex] new chatroom ($CHAT_ID) -> opening a new codex session" >&2
  fi
elif [ "$CODEX_NEW_SESSION" = "1" ]; then
  echo "[codex] user requested a new session" >&2
else
  echo "[codex] new chatroom ($CHAT_ID) -> opening a new codex session" >&2
fi

echo "MODE=$MODE"
echo "SID=$SID"
echo "TURNS=$TURNS"
echo "CHAT_ID=$CHAT_ID"
```

---

## 2.6 codex-search.sh (/var/minis/shared/codex-lab/codex-search.sh, search shim v4)

```sh
#!/bin/sh
# codex-search: forwards the entire "web search" to codex's built-in web search
# (DeepSeek web_search tool). This is a transparent shim — to the outside it looks like a
# web-search command, but codex actually performs the search.
# Principle: do not polish/expand the query; pass the original wording through (codex knows how to search).
#
# v3 (2026-08-23): unified chatroom binding.
# v3.1 (2026-08-23): --help fix + argument defense.
# v4 (2026-08-23): GPT Sol suggestion — wrap the original query in <user_query> (authoritative
#   intent); codex is free to choose its search strategy; quality gate + verification rules +
#   stop condition; normal answers do not dump all links (exhaustive only on follow-up).

CODEX_DS=/var/minis/shared/codex-lab/codex-ds.sh
RESOLVER=/var/minis/shared/codex-lab/codex-resolve.sh
MAP=/var/minis/shared/codex-lab/codex-chat-map
WORKDIR=/var/minis/shared/codex-lab/testrepo

usage() {
  cat >&2 <<'EOF'
web-search — forwarding shim for codex's built-in web search
usage:
  web-search "original query"   auto-detects (same chatroom = resume; new chatroom = new session)
  web-search --new "new topic"  force a new session (-n is a synonym)
  web-search --status           show mapping status
  web-search --reset            clear the mapping (next call = new session)
  web-search --help             show this help
EOF
}

case "$1" in
  --status)
    if [ -f "$MAP" ]; then
      read -r C S T N < "$MAP"
      echo "[ws] chatroom=$C codex_session=$S turns=$N" >&2
    else
      echo "[ws] no codex session mapping (next call will open a new one)" >&2
    fi
    exit 0
    ;;
  --reset)
    rm -f "$MAP"
    echo "[ws] mapping cleared (next call = new session)" >&2
    exit 0
    ;;
  --help|-h)
    usage
    exit 0
    ;;
esac

NEW=0
while [ "$1" = "--new" ] || [ "$1" = "-n" ]; do
  NEW=1; shift
done
QUERY="$1"
if [ -z "$QUERY" ]; then
  usage
  exit 2
fi
case "$QUERY" in
  -*)
    echo "web-search: unknown option $QUERY (a query should not start with -; see --help for options)" >&2
    exit 2
    ;;
esac

[ "$NEW" = "1" ] && export CODEX_NEW_SESSION=1

# Resolve to pick the skeleton (the wrapper resolves again internally to execute; results are consistent)
eval "$("$RESOLVER")"
MODE="${MODE:-new}"

cd "$WORKDIR" || exit 2

if [ "$MODE" = "resume" ]; then
  echo "[ws] resume (chatroom $CHAT_ID)" >&2
  PROMPT="User follow-up (answer directly from the existing search results above whenever possible, including full links; only search again if new information is really needed, and state that it is a new search): $QUERY
Referent understanding: words in the user message such as \"the above/earlier/those/these/that\" refer to the earlier part of this conversation (your previous search results and replies). If the user asks to list links (e.g. \"list the links above\", \"all URLs from the above websites\"):
- extract directly from the earlier context, do not search again;
- list every link that appeared in the earlier search results, without missing any, each with its title;
- if there were multiple search rounds, group them by query term; do not pick just one or two representative ones. \"All\" means all.
Stop searching once there is enough information to answer the user's question."
else
  echo "[ws] new session" >&2
  PROMPT="You are responsible for completing the web search and any necessary source verification.
The following is the user's original query. Treat it as the authoritative source of the final intent; do not change its real question, constraints, or requirements:
<user_query>
$QUERY
</user_query>
The search strategy is up to you. You may search the original wording directly; you may also, when it improves accuracy, relevance, completeness, or freshness, switch to keywords better suited to the search engine, use synonyms or language variants, split complex questions, add necessary year/version/region/entity names, run multiple search rounds, open candidate pages to verify, refine based on preliminary results, and cross-check important information. All query transformations are only search tactics; they must not change the user's original intent.
Quality requirements:
1. Clearly mismatched, polluted, or irrelevant results must not be treated as valid answers.
2. For volatile information such as prices, versions, dates, and latest status, verify against the latest reliable sources as much as possible.
3. When a suitable first-party/original source exists, use it to verify objective facts.
4. When sources contradict each other, point out the contradiction; do not pretend there is a single definitive answer.
5. When sufficient reliable information cannot be obtained, say so clearly; do not guess.
6. If native search results are insufficient, you may try other available search/page verification methods (including shell commands); any supplemental content must pass the same quality gate; do not retry endlessly when the environment capability fails.
7. Stop searching once there is enough reliable evidence to answer the user's question; do not keep searching just to increase the source count.
Output format:
- First answer the user's real question directly.
- Attach relevant sources and URLs for important facts.
- Do not list every URL searched by default; only output an exhaustive link list when the user explicitly asks for full URLs/all links."
fi

exec "$CODEX_DS" exec "$PROMPT"
```

---

## 2.7 Supporting directories and files

```sh
# CODEX_HOME
mkdir -p /var/minis/shared/codex-lab/codex-home

# testrepo (git repo, working dir for the search shim)
mkdir -p /var/minis/shared/codex-lab/testrepo
cd /var/minis/shared/codex-lab/testrepo
git init && git config user.email t@t.t && git config user.name test
echo "# test" > README.md && git add -A && git commit -m init

# symlinks
chmod +x /var/minis/shared/codex-lab/codex-ds.sh /var/minis/shared/codex-lab/codex-resolve.sh /var/minis/shared/codex-lab/codex-search.sh
ln -sf /var/minis/shared/codex-lab/codex-ds.sh      /usr/local/bin/codex
ln -sf /var/minis/shared/codex-lab/codex-search.sh  /usr/local/bin/web-search
ln -sf /var/minis/shared/codex-lab/codex-search.sh  /usr/local/bin/ws
```

---

## 2.8 Verification checklist (run each item after install)

```sh
codex --version                                     # codex-cli 0.139.0
codex exec --new --skip-git-repo-check "reply with exactly: OK"   # prints OK + tokens used
codex exec "What did I just ask you to do?"          # resumes the same session, proves memory
web-search --help                                   # usage (exit 0)
web-search "today's Hong Kong news"                 # results + sources
web-search "list all the weblinks above"            # resume + exhaustive link list
```

> The exec bug does not exist on a computer; `codex exec "use exec_command to run echo hi"`
> should print hi normally. If `exited -1` appears on a computer too, check the binary / bridge /
> config first.
