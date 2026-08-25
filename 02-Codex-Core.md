# 02 — Codex Core (full install + every copyable file)

> Codex CLI 0.139.0 + DeepSeek (deepseek-v4-flash, effort=max)
> After install: `codex exec "task"` runs the agent directly; `codex` enters the TUI.

## 1. Download the binary (must be 0.139.0)

```sh
mkdir -p /var/minis/shared/codex-lab/codex-0139
cd /var/minis/shared/codex-lab
curl -fL -o codex-0139.tar.gz \
  https://github.com/openai/codex/releases/download/rust-v0.139.0/codex-aarch64-unknown-linux-musl.tar.gz
tar xzf codex-0139.tar.gz -C codex-0139
mv codex-0139/codex-aarch64-unknown-linux-musl codex-0139/codex
chmod +x codex-0139/codex
codex-0139/codex --version   # should print codex-cli 0.139.0
```

**Version rule**:
- ✅ 0.139.0 — the only usable version (pure ring, no P-521 assert)
- ❌ 0.148.0 / 0.149.0 — panic (official binary inconsistent with its Cargo.lock, see pitfall #1 in 01)
- Do not run `codex update`! It panics right after upgrading.

## 2. TLS bridge (required — ring cannot reach https on iSH)

File: `/var/minis/shared/codex-lab/tls_bridge.py`

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

Manual start: `nohup python3 /var/minis/shared/codex-lab/tls_bridge.py > /tmp/tls_bridge.log 2>&1 &`

## 3. Wrapper (/usr/local/bin/codex)

File: `/var/minis/shared/codex-lab/codex-ds.sh` (v2.1, 2026-08-23)
> The file itself is authoritative (the backup tar `stage/codex-lab/codex-ds.sh` is the source
> of truth; do not hand-copy an old version from a document).

Core behavior:
1. Auto-starts the TLS bridge (detects 127.0.0.1:8787) + sets CODEX_HOME
2. **Chatroom binding**: `codex exec "prompt"` automatically resumes this chatroom's codex
   session; a new chatroom opens a new one; `--new` forces a new one; resume failure
   auto-falls back to a new session
3. **Anti-recursion**: /tmp/codex-recursion-guard (writes its own PID + kill -0 check); a
   nested exec that sees the guard PID still alive is refused (exit 2); trap EXIT clears the guard
4. Auto-adds `--skip-git-repo-check`; other subcommands (--version/doctor/mcp-server/resume <id>…)
   pass through as-is

Install:
```sh
chmod +x /var/minis/shared/codex-lab/codex-ds.sh
ln -sf /var/minis/shared/codex-lab/codex-ds.sh /usr/local/bin/codex
```

## 4. config.toml (/var/minis/shared/codex-lab/codex-home/config.toml)

```toml
model = "deepseek-v4-flash"
model_provider = "deepseek"
model_reasoning_effort = "max"

# Login via API key (avoids opening the ChatGPT login page)
preferred_auth_method = "apikey"
forced_login_method = "api"

approval_policy = "never"
sandbox_mode = "danger-full-access"

[model_providers.deepseek]
name = "deepseek"
base_url = "http://127.0.0.1:8787/"
wire_api = "responses"
experimental_bearer_token = "<put your DeepSeek API key here>"
```

**⚠️ Security**: the key is hardcoded in config.toml (`experimental_bearer_token`). This is a
local file, but remove it from backups/shared copies. Key format: `sk-` + 32 hex characters.
Verify the key: `curl -s https://api.deepseek.com/models -H "Authorization: Bearer sk-xxx"` →
returning the model list means it is valid.

**Settings**:
- `model`: deepseek-v4-flash (default) / deepseek-v4-pro / deepseek-v4-flash-vision-exp
- `model_reasoning_effort`: none/minimal/low/medium/high/xhigh/max (ultra does not work)
- Temporary override: `codex -c 'model_reasoning_effort="high"'` or `codex -m deepseek-v4-pro`
- base_url **must** point to 127.0.0.1:8787 (the bridge) — connecting directly to
  https://api.deepseek.com fails the TLS handshake

## 5. Search shim (web-search / ws, v3.1 session-continuity + protection version)

File: `/var/minis/shared/codex-lab/codex-search.sh`
> The file itself is authoritative (backup tar `stage/codex-lab/codex-search.sh` is the source
> of truth). The old version used ws-state (60min/8-turn rotation), replaced by v3 global
> chatroom binding — **do not re-copy the old version**.

Core behavior (v4, 2026-08-23):
1. **Chatroom binding**: shares the resolver + codex-chat-map with codex-ds.sh. Follow-ups
   (no --new) resume the same codex session; a new chatroom opens a new one; `--new` forces a
   new one; unlimited turns
2. **--help/-h** → prints usage, exit 0 (never treated as a query again); unknown arguments
   starting with `-` → error, exit 2
3. **Anti-recursion**: nested calls are blocked by codex-ds.sh's recursion guard (exit 2,
   guides codex to use the built-in web search tool)
4. **v4 search skeleton prompt**:
   - the original query is wrapped in `<user_query>` (authoritative intent; the outer layer does
     not rewrite it), codex is free to design its own search strategy (rewording keywords /
     translating / splitting questions / multiple rounds / opening pages / refining / cross-checking);
     query variants are only tactics, the intent must not change
   - quality gate (relevance/freshness/source fit/consistency/coverage) + verification rules
     (volatile info uses first-party sources; contradictions must be pointed out)
   - supplemental methods (including shell) must pass the same quality gate; do not retry
     endlessly when the environment capability fails
   - **stop condition**: stop when there is enough evidence; do not keep searching to inflate
     the source count
   - output: answer the question first, list only sources that support the answer;
     **an exhaustive link list is only output when the user explicitly asks**
   - resume version: reuse the earlier context first + referent understanding (for link
     follow-ups, list all links from the earlier context, grouped, without re-searching)
5. `--status` / `--reset` manage codex-chat-map
6. Zombie bridge protection is in codex-ds.sh (double PID detection, auto cleanup)

Install:
```sh
chmod +x /var/minis/shared/codex-lab/codex-search.sh
ln -sf /var/minis/shared/codex-lab/codex-search.sh /usr/local/bin/web-search
ln -sf /var/minis/shared/codex-lab/codex-search.sh /usr/local/bin/ws
```

**Prerequisite**: WORKDIR (/var/minis/shared/codex-lab/testrepo) must be a git repo:
```sh
mkdir -p /var/minis/shared/codex-lab/testrepo && cd /var/minis/shared/codex-lab/testrepo
git init && git config user.email t@t.t && git config user.name test
echo "# test" > README.md && git add -A && git commit -m init
```

## 6. Verification checklist (run each item after a fresh install)

```sh
codex --version                     # codex-cli 0.139.0
codex exec --skip-git-repo-check --sandbox danger-full-access "reply with exactly: OK"
                                    # prints OK + tokens used
codex exec resume --last "What was my previous instruction? Reply briefly"
                                    # proves session memory works
web-search "today's Hong Kong top news"   # returns results + source URLs + quality self-assessment
```

## 7. Common command quick reference

```sh
codex exec "task"                    # one-shot headless (primary)
codex exec resume --last "continue"  # resume the most recent session (has memory)
codex exec resume <session_id> "..." # resume a specific session
codex exec resume --last             # no prompt = read-only?
codex mcp-server                     # MCP server mode (stdio, for other agents to call)
codex exec-server                    # [experimental] background service
codex login status                   # check login status
codex doctor                         # health check (reports auth ✗ without a key — normal)
```

- headless = `codex exec` (no TTY needed). `codex resume` (interactive TUI) needs a TTY; use it
  in the Minis terminal.
- Session files persist under CODEX_HOME; they survive an iSH restart.
- The exec output repeats the reply at the end = normal.
- Long tasks: `timeout 900 codex exec "..."`

## 8. Troubleshooting quick reference

| Symptom | Cause/fix |
|---|---|
| `stream disconnected ... Reconnecting 1/5` loop | bridge died: `ps \| grep tls_bridge`; if absent, restart (see §2) |
| P521 assert / Once poisoned panic | 0.149 binary in use — check /usr/local/bin/codex points to codex-ds.sh |
| `wire_api = "chat"` no longer supported | change it back to `"responses"` |
| 401 Unauthorized | key invalid; replace `experimental_bearer_token` |
| `stdin is not a terminal` | interactive resume was used; switch to `codex exec resume` |
| `Not inside a trusted directory` | add `--skip-git-repo-check` or run inside a git repo |
| 400 unknown variant `ultra` | effort set to ultra, DeepSeek does not support it (max is the top) |
