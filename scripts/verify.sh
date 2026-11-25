#!/usr/bin/env bash
# Verify Craft Anything + REA registrations and MCP handshakes (macOS, Linux).
#
#   bash scripts/verify.sh [client]      # client defaults to claude_code
set -uo pipefail

CLIENT="${1:-claude_code}"
REA_VERSION="${REA_VERSION:-6.5.0}"
FAIL=0

unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy 2>/dev/null || true
export NO_PROXY='*'

step() { printf '\n== %s\n' "$1"; }

step "REA registration ($CLIENT)"
if OUT="$(npx --proxy=false --https-proxy=false -y "rea-agents@$REA_VERSION" doctor --client "$CLIENT" --json 2>/dev/null)"; then
  echo "$OUT" | grep -E '"(name|state|detail|installed_version|installed_tool_count)"' | sed 's/^ *//' | head -30
  if echo "$OUT" | grep -q '"state":"aligned"'; then printf '   aligned\n'; else printf '   not aligned\n'; FAIL=$((FAIL+1)); fi
else
  printf '   REA doctor failed\n'; FAIL=$((FAIL+1))
fi

step 'Craft Anything registration'
CLI="$(command -v craft-anything-cli 2>/dev/null || true)"
[ -z "$CLI" ] && [ -x "$HOME/.local/craft-anything/craft-anything-cli" ] && CLI="$HOME/.local/craft-anything/craft-anything-cli"
if [ -z "$CLI" ]; then
  printf '   craft-anything-cli not found\n'; FAIL=$((FAIL+1))
else
  printf '   cli: %s\n' "$CLI"
  "$CLI" doctor --format text | grep -E 'registration:|mcp:self-test|healthy' || true
fi

step 'MCP handshake'
if [ -n "$CLI" ]; then
  if node "$(dirname "$0")/probe-mcp.mjs" "$CLI" "$REA_VERSION"; then
    printf '   both servers answered\n'
  else
    printf '   one or more servers failed\n'; FAIL=$((FAIL+1))
  fi
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then printf 'ALL CHECKS PASSED\n'; exit 0; fi
printf '%s CHECK(S) NEED ATTENTION\n' "$FAIL"; exit 1
