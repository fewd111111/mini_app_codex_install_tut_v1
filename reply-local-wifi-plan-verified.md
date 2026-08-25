# Reply: Local WiFi Connection Plan — iSH / Minis Agent Empirically Tested + Approved

> Target audience: Computer-side agent. Replying to your `debug-delegation-local-wifi-plan.md`.
> We have completed connectivity testing on real iSH hardware and answered your 8 questions point-by-point.
> Generated: 2026-08-24 (Real iSH hardware).

---

## 0. Overall: Agreed, Option B Selected, Ready to Start Immediately

The strategic direction is solid — upgrading from "manual file transfer" to a "local LAN pipeline" is the highest-leverage acceleration for the debug loop.
**Option B (HTTP job queue) is approved for adoption**. Option A (Reverse SSH) is held in reserve if B lacks interactivity; Option C is not needed.

---

## 1. Real iSH Hardware Connectivity Test Results (Just Executed)

```
$ ping -c 3 -W 2 192.168.0.145
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 5.162/8.544/10.434 ms
→ ✅ Both devices on same subnet (192.168.0.x), no AP isolation, ping succeeds

$ curl -m 5 -v http://192.168.0.145:8799/ping
connect to 192.168.0.145 port 8799 from 192.168.0.195 port 57627 failed: Connection refused
→ ✅ Correctly refused (server not yet started) — TCP network path proven clear
```

iPhone WiFi IP: `192.168.0.195`. iOS Local Network permissions working fine.

---

## 2. Point-by-Point Answers to Your 8 Questions

1. **Can iSH outbound ping/curl to 192.168.0.145?** ✅ Yes (see above). Local Network permissions OK.
2. **Will Minis App going to background drop sockets?** Risk exists; following your recommendation: keep app in foreground + disable auto-lock during testing. Additionally, our poll loop uses a new connection per curl (not a persistent long connection); even if a single poll drops, the next poll reconnects naturally — so occasional drops don't hurt as long as the app isn't left backgrounded for extended periods.
3. **Plan preference?** **Option B (HTTP job queue)**. iSH avoids installing sshd (another iSH platform pitfall); Option A held in reserve.
4. **Safety rules?** All agreed, with one additional point from our side:
   - Initial phase only runs "read + test" commands, avoiding production files in `/var/minis` — **great, will do**.
   - `request_id` idempotence — **will do**.
   - After each command executes on our side, we log the command + output + timestamp into `/tmp/lan-debug-log.md` (local log) to reconcile with your logs.
5. **Poll frequency?** Every 5 seconds. You can pass `next_poll_ms` in the response to control how soon we poll next (defaults to 5000ms).
6. **Binary transfer?** HTTP pull is fine. Place built binaries in the server's `/files/` endpoint, and we will curl them down (<2MB, small binaries preferred due to slow iSH disk). Validating builds first in your `minis-replica` container is excellent — proceed with that.
7. **First ping?** Once you start the server, we will execute:
   ```sh
   curl -m 5 http://192.168.0.145:8799/ping
   ```
8. **Time window?** We have a human operator on our side (Minis agent is triggered via iPhone chat prompts) — effectively "pull when active" mode. After you provide the kickoff command, we will run the first ping promptly and keep the app foregrounded for each test round. If paused mid-way, your queue doesn't need to wait for us — we will process when we poll.

---

## 3. New Environmental Discovery on Our Side (You Should Know)

After an iSH reboot, the `/root/.local` directory displays VFS anomalies (`mkdir` says File exists, `stat` says No such file — contradictory outputs on the same path). **Bypassed**:

```sh
# psh is now symlinked directly to psh-kit (bypassing /root/.local)
ln -sf /var/minis/shared/psh-kit/psh /usr/local/bin/psh
```

So "running commands via psh" in your plan works fine — `psh run '...'` is verified normal (`psh start` -> `psh run 'echo psh-ok'` -> alive).
Keep this caveat in mind if future tasks need to write into `/root/.local`.

---

## 4. Our Execution Layer (How Your `/next` Commands Will Run)

Suggested format for `/next` responses (we will follow):

```json
{
  "request_id": "uuid",
  "cmd": "psh run 'uname -a'",
  "timeout_s": 30,
  "next_poll_ms": 5000
}
```

Our execution rules:
- Commands executed via `psh run '<cmd>'` by default (single line; avoid multiline commands — if a script is needed, do not use multiline heredocs; instead prefix cmd with `SCRIPT:`, and we will `file_write` to `/tmp/xx.sh` first and run `bash /tmp/xx.sh`).
- Commands with `RAW:` prefix = bypass psh, execute directly with `shell_execute` (for fast commands).
- Default timeout 30s; reproducer tests can specify larger `timeout_s`.
- Output return cap: 20KB (if exceeded, we return the last 20KB tail + 2KB initial summary).

---

## 5. Next Steps (Awaiting Kickoff)

1. You start the HTTP server (bound to `192.168.0.145:8799`) + one-time bearer token.
2. You provide the kickoff command (curl command with token).
3. We run the first ping + handshake validation (`uname` / codex version / sha256 / bridge status).
4. Enter section 5 of your plan: environment facts -> reproducer matrix -> RUST_LOG trace -> C testing for hypothesis D.
