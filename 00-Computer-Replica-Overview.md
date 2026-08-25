# 00 — Computer Replica Blueprint: Overview and Install Order

> Goal: build a shell system on a computer that is **100% identical** to the iPhone iSH
> environment, and use a computer-grade agent there for development, testing,
> verification, and debugging.
> Document series: 00 overview / 01 OS and toolchain / 02 full Codex / 03 Minis area and
> skills / 04 harness and psh / 05 iSH-specific non-replicable parts /
> **debug-delegation-exec-bug-v2-unresolved.md (latest bug delegation — read first by the computer codex)**
> Generated: 2026-08-24. Source: collected from the real iPhone iSH device (all data measured).

---

## ⚠️ First: honest statement (you must know this)

This blueprint can restore **everything except the iSH kernel emulation layer** 100% on a
computer. Some things simply cannot be replicated on real Linux — and **should not be**:

| Item | iSH reality | On a computer |
|---|---|---|
| Kernel | `4.20.69-ish` (iSH's own syscall emulation) | real Linux kernel — **this is a good thing** |
| exec bug (waitid(P_PIDFD) returns EINVAL) | present (iSH emulation-layer defect) | **automatically gone** (real kernel supports it) |
| prctl(PR_SET_PDEATHSIG) | returns EINVAL | works |
| ring TLS handshake | fails | works (the bridge is theoretically unnecessary, but keep the config for environment parity) |
| apple-* tools, minis-* tools | built into the Minis App | absent (app-layer things) |
| /var/minis/mounts/ | iOS Files mounts | absent (create empty directories manually) |
| memory (daily log), chatroom | built into the Minis App | absent |

**Conclusion**: the computer environment = "the healthy version iSH should have had". All the
hacks we made on iSH to work around emulation-layer defects (bridge, patched binary) are still
installed on the computer (to stay 100% consistent), but they are **not necessarily needed** —
you should know this.

---

## Fastest install: copy directly from the documents

**No packaging needed** — everything is already in this document series (00-05). Follow the
"manual install order" in 00 and copy each piece. The most important parts: **02 contains the
full codex file contents, 04 contains the full psh, 03 contains the full text of the two core
skills** — the remaining files (harness py, powerpoint-pro scripts) live under `/var/minis/`
on the real device; `cat` whichever one you need and copy it over.

Before starting work on a computer, the most practical approach: transfer these 6 md files
(00-05) to the computer (AirDrop / iCloud / GitHub). The computer agent only needs to read 00
to know the entire install order.

---

## Manual install order (when there is no tar)

1. **Install Alpine Linux 3.21** (Docker / VM / WSL all fine; aarch64 or x86_64 both fine —
   for x86_64 use the official x86_64 musl binary)
   ```sh
   docker run -it alpine:3.21 sh
   # or install Alpine 3.21 in a VM/WSL
   ```
2. **Install the toolchain per 01** (full apk add set + pip + npm)
3. **Install Codex per 02** (binary + config.toml + bridge + wrapper + shim + resolver)
4. **Create the Minis area per 03** (/var/minis structure + skills + AGENTS.md + symlinks)
5. **Restore harness + psh per 04**
6. **Verification checklist** (at the end of 02)

---

## Environment snapshot (state when this document was collected)

```
OS: Alpine Linux v3.21.0
Arch: aarch64 (a computer can use aarch64 or x86_64 — switch the binary accordingly)
Kernel: 4.20.69-ish (iSH emulation; a computer uses its own real kernel)
BusyBox: v1.37.0
Python: 3.12.14
Node: 22.23.2 / npm 10.9.1
codex: 0.139.0 (v2 double patch, hash f626dda1...)
DeepSeek: deepseek-v4-flash, effort=xhigh
```

---

## Key facts (for an agent taking over)

- **codex 0.139.0 is the pinned version**: the official 0.148/0.149 binaries have a rustls
  P-521 assert panic; 0.139.0 is the last version that works normally
- **A bridge is not needed on a computer**: ring TLS works on real Linux, so codex can connect
  directly to `https://api.deepseek.com` — but for 100% consistency the blueprint still ships
  the bridge config (base_url points to 127.0.0.1:8787)
  **If you want direct connection on the computer**: change `base_url = "https://api.deepseek.com/"`
  in config.toml, that's all
- **codex-chat-map / resolver degrades on a computer**: `minis-sessions-cli` does not exist →
  the resolver cannot obtain CHAT_ID → `MODE=new` (a new session every time). To simulate
  chatroom binding on a computer, write codex-chat-map manually
- **The exec bug does not exist on a computer** — if you still see `exited -1` on a computer,
  that is a new problem
