# 06 — One-Time Backup Script (Package the Entire System)

> Usage: `bash backup.sh [output_dir]`
> Output: `backup-YYYYMMDD.tar.gz` + `manifest.txt` (listing all packaged items)
> Restoration: Extract tar to the corresponding `/var/minis/` paths on the new device (see 00-README-System-Blueprint.md)

---

## backup.sh (Complete and Copy-Paste Ready)

```sh
#!/bin/sh
# backup.sh — Minis system one-time backup
# Usage: bash backup.sh [output_dir]   (defaults to /var/minis/workspace/minis-backup)
# Options: --with-binary  bundles codex-0139.tar.gz (79MB) along with backup
set -e

OUT="${1:-/var/minis/workspace/minis-backup}"
WITH_BIN=0
[ "$1" = "--with-binary" ] && WITH_BIN=1 && OUT="${2:-/var/minis/workspace/minis-backup}"

STAMP=$(date +%Y%m%d)
TAR="$OUT/backup-$STAMP.tar.gz"
STAGE="$OUT/stage"
rm -rf "$STAGE" && mkdir -p "$STAGE"

echo "[backup] staging files..."

# 1. Blueprint docs (this series)
cp -r /var/minis/shared/system-blueprint "$STAGE/"

# 2. skills (all)
cp -r /var/minis/skills "$STAGE/"

# 3. AGENTS.md
cp /var/minis/shared/AGENTS.md "$STAGE/"

# 4. harness toolchain
cp -r /var/minis/shared/harness "$STAGE/"

# 5. codex-lab core (excludes old binaries and analysis scratch files)
mkdir -p "$STAGE/codex-lab/codex-home"
cp /var/minis/shared/codex-lab/tls_bridge.py     "$STAGE/codex-lab/"
cp /var/minis/shared/codex-lab/codex-ds.sh       "$STAGE/codex-lab/"
cp /var/minis/shared/codex-lab/codex-search.sh   "$STAGE/codex-lab/"
cp /var/minis/shared/codex-lab/codex-home/config.toml "$STAGE/codex-lab/codex-home/"
if [ "$WITH_BIN" = "1" ] && [ -f /var/minis/shared/codex-lab/codex-0139.tar.gz ]; then
  cp /var/minis/shared/codex-lab/codex-0139.tar.gz "$STAGE/codex-lab/"
fi

# 6. slides-profiles (PPT templates)
cp -r /var/minis/shared/slides-profiles "$STAGE/"

# 7. Memory
cp -r /var/minis/memory "$STAGE/"

# 8. disabled-skills (archived, if needed)
# cp -r /var/minis/shared/disabled-skills "$STAGE/"   # Omit if too large

# manifest
{
  echo "Minis system backup $STAMP"
  echo "---- files ----"
  find "$STAGE" -type f | sed "s|$STAGE/||" | sort
  echo "---- total size ----"
  du -sh "$STAGE"
} > "$OUT/manifest.txt"

tar czf "$TAR" -C "$OUT" stage
rm -rf "$STAGE"
echo "[backup] done: $TAR"
ls -lh "$TAR" "$OUT/manifest.txt"
echo "[backup] ⚠️ config.toml contains DeepSeek API key; remove it before sharing backup!"
```

---

## Restoration (New Mobile Device)

```sh
# 1. Place backup-YYYYMMDD.tar.gz into new device iSH (via iOS Files mount /var/minis/mounts/<folder>/)
# 2. Extract
cd / && tar xzf /var/minis/mounts/<folder>/backup-YYYYMMDD.tar.gz

# 3. Move to corresponding target locations
cp -r stage/system-blueprint /var/minis/shared/
cp -r stage/skills           /var/minis/skills/
cp stage/AGENTS.md           /var/minis/shared/AGENTS.md
cp -r stage/harness          /var/minis/shared/harness
cp -r stage/codex-lab        /var/minis/shared/codex-lab
cp -r stage/slides-profiles  /var/minis/shared/slides-profiles
cp -r stage/memory           /var/minis/memory

# 4. codex binary (if not bundled in backup)
cd /var/minis/shared/codex-lab
curl -fL -o codex-0139.tar.gz \
  https://github.com/openai/codex/releases/download/rust-v0.139.0/codex-aarch64-unknown-linux-musl.tar.gz
mkdir -p codex-0139 && tar xzf codex-0139.tar.gz -C codex-0139
mv codex-0139/codex-aarch64-unknown-linux-musl codex-0139/codex && chmod +x codex-0139/codex

# 5. Restore symlinks (see 05-Harness-Restore.md)
# 6. Set API key: vi /var/minis/shared/codex-lab/codex-home/config.toml

# 7. Verification
codex exec --skip-git-repo-check --sandbox danger-full-access "reply with exactly: OK"
```

---

## Backup Content Inventory (Comparison)

| Backup Item | Staged Location | Restores To |
|---|---|---|
| Blueprint docs x6 | `stage/system-blueprint/` | `/var/minis/shared/system-blueprint/` |
| skills x4 | `stage/skills/` | `/var/minis/skills/` |
| AGENTS.md | `stage/AGENTS.md` | `/var/minis/shared/AGENTS.md` |
| harness tools x8 | `stage/harness/` | `/var/minis/shared/harness/` |
| codex core (bridge/wrapper/shim/config) | `stage/codex-lab/` | `/var/minis/shared/codex-lab/` |
| codex binary tarball (optional `--with-binary`) | `stage/codex-lab/codex-0139.tar.gz` | Extracted as shown above |
| PPT profiles | `stage/slides-profiles/` | `/var/minis/shared/slides-profiles/` |
| Memory (daily + GLOBAL) | `stage/memory/` | `/var/minis/memory/` |

---

## ⚠️ Security Warnings

1. **`config.toml` contains DeepSeek API key** (`experimental_bearer_token`) — the backup archive is equivalent to an API key; do not share, upload, or feed to AI.
2. Daily memory files may contain sensitive conversation summaries — apply the same caution.
3. Backup size: ~a few MB without binary; +79MB with binary.
