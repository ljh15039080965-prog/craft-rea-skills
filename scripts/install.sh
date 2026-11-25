#!/usr/bin/env bash
# Install Craft Anything + REA into Claude Code / Codex (macOS, Linux).
#
#   bash scripts/install.sh                 # claude_code + codex
#   bash scripts/install.sh codex           # one client
#   SKIP_REA=1 bash scripts/install.sh      # only Craft Anything
#   SKIP_CRAFT=1 bash scripts/install.sh    # only REA
set -uo pipefail

REA_VERSION="${REA_VERSION:-6.5.0}"
CRAFT_VERSION="${CRAFT_VERSION:-0.6.1}"
CRAFT_DIR="${CRAFT_DIR:-$HOME/.local/craft-anything}"

CLIENTS=("$@")
if [ ${#CLIENTS[@]} -eq 0 ]; then CLIENTS=(claude_code codex); fi

step() { printf '\n== %s\n' "$1"; }
ok()   { printf '   [ok]   %s\n' "$1"; }
skip() { printf '   [skip] %s\n' "$1"; }
warn() { printf '   [warn] %s\n' "$1"; }

# A dead local proxy in ~/.npmrc breaks npx; force direct connections.
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy 2>/dev/null || true
export NO_PROXY='*'
NPM_FLAGS=(--proxy=false --https-proxy=false)

step "Environment"
if ! command -v node >/dev/null 2>&1; then warn 'node not found (REA needs Node.js >= 22.19)'; exit 1; fi
ok "node $(node -v)"
command -v npm >/dev/null 2>&1 && ok "npm $(npm -v)" || warn 'npm not found'

case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *)      OS=unknown ;;
esac
case "$(uname -m)" in
  arm64|aarch64) ARCH=aarch64 ;;
  x86_64|amd64)  ARCH=x86_64 ;;
  *)             ARCH=$(uname -m) ;;
esac
ok "$OS-$ARCH"

# ---------------------------------------------------------------- REA
if [ "${SKIP_REA:-0}" != "1" ]; then
  step "REA $REA_VERSION"
  for c in "${CLIENTS[@]}"; do
    if npx "${NPM_FLAGS[@]}" -y "rea-agents@$REA_VERSION" setup --client "$c" --yes >/tmp/rea-setup-"$c".log 2>&1; then
      ok "$c configured"
    else
      warn "$c failed (see /tmp/rea-setup-$c.log)"
    fi
  done
else
  skip 'REA (SKIP_REA=1)'
fi

# ------------------------------------------------------- Craft Anything
if [ "${SKIP_CRAFT:-0}" != "1" ]; then
  step "Craft Anything $CRAFT_VERSION"

  CLI="$(command -v craft-anything-cli 2>/dev/null || true)"
  if [ -z "$CLI" ] && [ -x "$CRAFT_DIR/craft-anything-cli" ]; then CLI="$CRAFT_DIR/craft-anything-cli"; fi

  if [ -z "$CLI" ]; then
    mkdir -p "$CRAFT_DIR"
    TMP="$(mktemp -d)"
    if [ "$OS" = "macos" ]; then
      FILE="craft-anything-cli-$CRAFT_VERSION-macos-universal.zip"
      URL="https://github.com/storytold/craft-anything/releases/download/v$CRAFT_VERSION/$FILE"
      echo "   downloading $FILE (about 28 MB)"
      if curl -fL --noproxy '*' -o "$TMP/$FILE" "$URL"; then
        ( cd "$TMP" && ditto -x -k "$FILE" . >/dev/null 2>&1 || unzip -q "$FILE" )
        FOUND="$(find "$TMP" -name craft-anything-cli -type f | head -1)"
        [ -n "$FOUND" ] && install -m 0755 "$FOUND" "$CRAFT_DIR/craft-anything-cli" && CLI="$CRAFT_DIR/craft-anything-cli"
        [ -n "$CLI" ] && xattr -d com.apple.quarantine "$CLI" 2>/dev/null || true
      fi
    elif [ "$OS" = "linux" ]; then
      FILE="craft-anything-$CRAFT_VERSION-linux-$ARCH.tar.gz"
      URL="https://github.com/storytold/craft-anything/releases/download/v$CRAFT_VERSION/$FILE"
      echo "   downloading $FILE (about 70 MB)"
      if curl -fL --noproxy '*' -o "$TMP/$FILE" "$URL"; then
        tar -xzf "$TMP/$FILE" -C "$TMP"
        FOUND="$(find "$TMP" -name 'craft-anything-cli*' -type f | head -1)"
        if [ -n "$FOUND" ]; then install -m 0755 "$FOUND" "$CRAFT_DIR/craft-anything-cli"; CLI="$CRAFT_DIR/craft-anything-cli"; fi
      fi
    fi
    rm -rf "$TMP"
  fi

  if [ -z "$CLI" ]; then
    warn 'craft-anything-cli unavailable; install manually from https://github.com/storytold/craft-anything/releases'
  else
    ok "cli: $CLI"
    case ":$PATH:" in
      *":$CRAFT_DIR:"*) : ;;
      *) warn "add to PATH: export PATH=\"$CRAFT_DIR:\$PATH\"" ;;
    esac
    for c in "${CLIENTS[@]}"; do
      if "$CLI" setup --client "$c" --yes --format text >/tmp/craft-setup-"$c".log 2>&1; then ok "$c configured"; else warn "$c failed (see /tmp/craft-setup-$c.log)"; fi
    done
    step 'Self test'
    "$CLI" doctor --format text || warn 'doctor reported problems'
  fi
else
  skip 'Craft Anything (SKIP_CRAFT=1)'
fi

printf '\nRestart Claude Code and Codex to load the new MCP servers and skills.\n'
printf 'Verify with:  bash scripts/verify.sh\n'
