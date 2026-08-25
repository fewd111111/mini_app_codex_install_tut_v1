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
