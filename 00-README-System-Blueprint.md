# 00 — Minis System Blueprint (one-shot reinstall guide for a new phone)

> This document series = the complete blueprint for this device + a pitfall guide + every
> copy-paste-ready configuration. To reinstall on a new phone, follow 01→06 in order to
> fully restore the environment.

## 1. System architecture

```
iOS phone
└── Minis App (AI chat frontend)
    └── iSH Shell (Alpine Linux 3.21, aarch64, 2.8G RAM)
        ├── /var/minis/          ← Minis shared area (app ↔ shell, both directions)
        │   ├── skills/          ← AI skills (codex/powerpoint-pro/skill-creator/web-search)
        │   ├── shared/          ← cross-session storage (this blueprint series lives here)
        │   │   ├── AGENTS.md    ← agent-managed long-term instructions (active for every task)
        │   │   ├── codex-lab/   ← codex core (binary+config+bridge+wrapper)
        │   │   ├── harness/     ← agent toolchain (guard/agentrun/agentverify/agentd/task/tooloffload/agentcompact)
        │   │   ├── slides-profiles/  ← PPT canvas templates + profiles
        │   │   └── disabled-skills/  ← archived disabled skills
        │   ├── memory/GLOBAL.md ← global memory (user-maintained, read-only)
        │   ├── memory/YYYY-MM-DD.md ← daily memory
        │   ├── workspace/       ← working files
        │   ├── attachments/     ← media attachments
        │   └── mounts/          ← external iOS Files mounts (mounted manually by the user)
        └── /usr/local/bin/      ← system commands
            ├── codex → codex-ds.sh (Codex+DeepSeek wrapper)
            ├── web-search/ws → codex-search.sh (search shim)
            ├── guard/agentrun/agentverify/agentd/task/tooloffload/agentcompact
            │     → /var/minis/shared/harness/*.py
            └── apple-* / minis-* (built into Minis)
```

## 2. New phone install order (overview)

1. Install the Minis App (App Store), sign in
2. Install the iSH App, boot Alpine Linux
3. Base toolchain: `apk add git jq py3-pip nodejs npm tmux vim ripgrep fd sqlite htop curl wget bash file openssh-client`
4. **Restore files**: extract the backup tarball (see 06) into /var/minis/shared/
5. **codex**: follow 02 (download 0.139.0 + place tls_bridge.py + codex-ds.sh + config.toml)
6. **skills**: follow 03 (place into /var/minis/skills/)
7. **AGENTS.md**: follow 04 (place at /var/minis/shared/AGENTS.md)
8. **harness tools**: follow 05 (create symlinks)
9. Verify: `codex exec "reply with exactly: OK"` returns OK = done

## 3. Document index

| Document | Content |
|---|---|
| 01-Pitfalls-Guide.md | every pitfall we hit (iSH/TLS/PTY/timeouts/packages…) |
| 02-Codex-Core.md | full Codex+DeepSeek install (with every copyable file) |
| 03-Skills-Full-Archive.md | all skills verbatim (direct copy) |
| 04-AGENTS-and-GLOBAL-Full-Archive.md | AGENTS.md + GLOBAL.md verbatim |
| 05-Harness-Restore.md | harness toolchain restore + symlink commands |
| 06-OneTime-Backup-Script.md | backup script that packages the current system |

## 4. Core facts at a glance

- **System**: Alpine 3.21.0 aarch64 (musl libc, no glibc); kernel 4.20.69-ish
- **codex**: 0.139.0 (official 0.148/0.149 panic, see pitfalls)
- **Model**: deepseek-v4-flash, effort=max (DeepSeek supports 7 levels; ultra is not supported)
- **TLS**: codex must use the local bridge (ring TLS does not work on iSH)
- **Search**: web-search/ws = codex built-in web search forwarding (the only path)
- **Search cost**: roughly 10k–20k DeepSeek tokens per search (usage-based billing)
