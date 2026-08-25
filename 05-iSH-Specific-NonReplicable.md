# 05 — iSH-Specific and Non-Replicable on a Computer (Honest Statement and Comparison)

> This document provides the complete inventory of "what cannot be replicated + why it should not be replicated".
> Purpose: Avoid wasting time attempting to mimic iSH defects on a computer.

---

## 5.1 Kernel Emulation Layer (Core Differences)

| Feature | iSH | Real Linux (Computer) |
|---|---|---|
| Kernel | `4.20.69-ish` (iSH custom syscall emulator) | Real kernel 5.x/6.x |
| `prctl(PR_SET_PDEATHSIG)` | ❌ EINVAL | ✅ Normal |
| `waitid(P_PIDFD)` | ❌ EINVAL | ✅ Normal |
| `pidfd_open` | ✅ Opens (but companion support is incomplete) | ✅ Complete |
| `fork`/`spawn` | Intermittent issues | ✅ Normal |
| PTY job control | ❌ `bash -i` exits 2, ^C kills entire shell | ✅ Normal |
| `/proc` | Incomplete (dead process remnants, pgrep false positives) | ✅ Normal |
| `strace` | ❌ PTRACE_SETOPTIONS EINVAL | ✅ Normal |
| ring TLS handshake | ❌ Fails (hence bridge is used) | ✅ Normal |
| Performance | 10–20x slower, no JIT, disk write ~0.85MB/s | ✅ Normal |

**These cannot be simulated on a computer** (unless using an x86 emulator in QEMU, which is still not 100% identical and pointless) — because they are bugs in iSH, not features.

---

## 5.2 Items Existing on iSH to Work Around Defects (Automatically Redundant on a Computer)

| Component | Reason on iSH | On a Computer |
|---|---|---|
| **TLS bridge** (`tls_bridge.py` + base_url `127.0.0.1:8787`) | ring TLS handshake failure | Not needed (can connect directly to `https://api.deepseek.com`); keeping it is harmless |
| **v2 patched binary** (EINVAL + tokio SIGCHLD) | Emulation layer defect | Not needed (official upstream binary works normally) |
| **tty:true workaround** | exec bug | Not needed |
| **OPENSSL_armcap=0 / GODEBUG / PYTHONMALLOC** | Workarounds for iSH CPU/memory emulation issues | Not needed, do not copy |
| **bridge zombie cleanup logic** | iSH process management defect | Harmless, can keep (real Linux does not spawn zombies) |
| **psh probe liveness detection** | iSH pgrep unreliability | Harmless, can keep |

---

## 5.3 Minis App Layer (Completely Absent on a Computer)

| Component | Description |
|---|---|
| `apple-*` 24 tools | iOS frameworks (Health/Calendar/Photos/Maps...), only available on iPhone |
| `minis-*` tools | Built into Minis app (browser-use/config/mcp-cli/model-use/open/sessions-cli/debug) |
| `/var/minis/memory/` daily logs | Managed by Minis app (create empty directories on a computer) |
| `/var/minis/mounts/` | iOS Files mounts (create empty directories on a computer) |
| `minis-sessions-cli list` | `codex-resolve.sh` relies on this to get chatroom id — **this command does not exist on a computer** |
| chatroom binding | Resolver cannot get `CHAT_ID` on a computer -> always `MODE=new` (new session each time) |
| `SOUL.md` / `GLOBAL.md` auto-loading | Minis app layer |

**Simulating chatroom binding on a computer** (when testing session continuity):
```sh
# Manually write codex-chat-map: <arbitrary_chat_id> <codex_session_id> <ts> <turns>
# But the resolver still cannot obtain CHAT_ID (minis-sessions-cli missing) —
# To test resume, running `codex exec resume <session_id> "..."` directly is sufficient.
```

---

## 5.4 Real Purpose of the Computer Environment (Honest Assessment)

| Purpose | Suitable on Computer |
|---|---|
| **Reproducing exec bug** | ❌ Pointless (real Linux does not have this bug) |
| **Validating patch builds** | ✅ Yes (verify build is normal on real Linux -> take to iSH for testing) |
| **Developing/Testing codex features, config, shim logic** | ✅ Ideal |
| **Running heavy tasks** (large builds, grepping large repos) | ✅ 10–20x faster |
| **web-search quality testing, benchmarks** | ✅ (as long as effort/model match) |
| **Writing new features like Gmail CLI** | ✅ |
| **Reproducing other iSH platform bugs** (ring TLS, PTY) | ❌ Cannot reproduce (real Linux is normal) |

---

## 5.5 Current Exec Bug Status (Snapshot when Blueprint Was Written)

- **v2 double-patch binary installed** (hash `f626dda1...`), but exec on iSH still gives `exited -1` — meaning the tokio SIGCHLD fallback patch still did not resolve it (likely deeper iSH issues, such as incomplete SIGCHLD signal delivery on iSH, or Rust std fork+waitpid path quirks on iSH).
- **tty:true workaround remains effective**.
- **This bug will never appear on a computer** — if exec fails on a computer, it is a different issue.
- Full details: see FINAL-Codex-Exec-Bug-Debug-Record.md and debug-delegation-exec-bug-v2-unresolved.md.

---

## 5.6 Summary in One Sentence

**Computer replica = "The healthy version iSH should have been"**.
- Install everything (100% configuration parity) -> do development/testing/verification on computer.
- Do not attempt to mimic iSH bugs (emulation layer defects cannot and should not be replicated).
- Debugging iSH-specific bugs must still be done on the real iSH device (as shown by the exec bug precedent).
