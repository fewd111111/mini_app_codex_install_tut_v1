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
