#!/bin/bash
# SessionStart hook for Claude Code cloud sessions.
#
# Installs the Solidity toolchain quietly and idempotently:
#   forge/cast (foundryup, npm fallback), Soldeer deps, node deps, solc warm-up build (required)
#   slither venv, just (optional; failures are warnings)
#
# Each step logs to $LOG_DIR/<step>.log. Prints one line on success and one
# block per failed step. Never runs tests. Never modifies tracked files.
# Exits 1 if a required step failed. settings.json appends `|| true` so the
# session always starts and the failure lines reach the agent as context
# (Claude Code drops a SessionStart hook's stdout on a non-zero exit).

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Pinned Foundry version for foundryup and the npm fallback. CI uses
# foundry-toolchain@v1 (latest stable), so bump this when CI's forge moves ahead.
FOUNDRY_VERSION="1.7.1"
FOUNDRY_DIR="${FOUNDRY_DIR:-$HOME/.foundry}"
JUST_NPM_PKG="rust-just"
SLITHER_VENV="${HOME}/.cache/apyx/slither-venv"
LOG_DIR="/tmp/session-setup"

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT" || exit 0
mkdir -p "$LOG_DIR"

required_failed=0
failures=()
done_steps=()
forge_source=""

# foundryup's binaries take precedence over an npm-installed forge.
export PATH="$FOUNDRY_DIR/bin:$PATH"

# Name the blocked host if the proxy refused a request.
blocked_host() {
  grep -iE -A1 "403|forbidden" "$1" 2>/dev/null |
    grep -oE "https?://[^/ \"')]+" | head -1 | sed -E 's#https?://##'
}

# run_step <name> <required|optional> <command...>
run_step() {
  local name="$1" kind="$2"
  shift 2
  local log="$LOG_DIR/$name.log"
  if "$@" >"$log" 2>&1; then
    done_steps+=("$name")
    return 0
  fi
  local host label
  host="$(blocked_host "$log")"
  [ "$kind" = required ] && label="FAIL" || label="WARN"
  [ "$kind" = required ] && required_failed=1
  failures+=("session-setup: $label $name${host:+ (blocked host: $host)} — log: $log
$(tail -n 15 "$log" | sed 's/^/  /')")
  return 1
}

# --- forge + cast -----------------------------------------------------------
forge_ok() { forge --version 2>/dev/null | grep -q "forge Version: $FOUNDRY_VERSION"; }
# Official installer, attestation verification left on. One retry so a
# blocked github.com (attestations, releases/latest) fails fast.
install_foundryup() {
  local installer
  installer="$(mktemp)" || return 1
  FOUNDRYUP_MAX_RETRIES=1 curl -fsSL --retry 1 -o "$installer" https://foundry.paradigm.xyz &&
    FOUNDRYUP_MAX_RETRIES=1 FOUNDRY_DIR="$FOUNDRY_DIR" bash "$installer" </dev/null &&
    FOUNDRYUP_MAX_RETRIES=1 FOUNDRY_DIR="$FOUNDRY_DIR" \
      "$FOUNDRY_DIR/bin/foundryup" -i "v$FOUNDRY_VERSION" </dev/null
  local rc=$?
  rm -f "$installer"
  return "$rc"
}
install_forge() {
  if install_foundryup && forge_ok; then
    forge_source=foundryup
    return 0
  fi
  echo "--- foundryup failed; falling back to npm @foundry-rs/forge"
  npm install -g --no-fund --no-audit \
    "@foundry-rs/forge@$FOUNDRY_VERSION" "@foundry-rs/cast@$FOUNDRY_VERSION" &&
    forge_ok && forge_source=npm
}
if ! forge_ok; then
  run_step forge required install_forge
fi
# Expose foundryup's bin dir to the session's later Bash commands.
if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -x "$FOUNDRY_DIR/bin/forge" ] &&
  ! grep -qs "$FOUNDRY_DIR/bin" "$CLAUDE_ENV_FILE"; then
  echo "export PATH=\"$FOUNDRY_DIR/bin:\$PATH\"" >>"$CLAUDE_ENV_FILE"
fi

# --- Soldeer deps -----------------------------------------------------------
soldeer_ok() {
  local d
  for d in forge-std-1.11.0 @openzeppelin-contracts-5.5.0 \
    @openzeppelin-contracts-upgradeable-5.5.0 solady-0.1.26; do
    [ -d "dependencies/$d" ] || return 1
  done
}
install_soldeer() {
  forge soldeer install --config-location soldeer </dev/null && soldeer_ok
}
if ! soldeer_ok && command -v forge >/dev/null; then
  run_step soldeer required install_soldeer
fi

# --- node deps (remappings.txt -> node_modules/) ----------------------------
node_ok() {
  [ -d node_modules/@chainlink/contracts/src ] &&
    [ -d node_modules/@chainlink/contracts-ccip/contracts ] &&
    [ -d node_modules/@openzeppelin/contracts-4.8.3 ] &&
    [ -d node_modules/@openzeppelin/contracts-5.0.2 ]
}
# Direct deps from pnpm-lock.yaml's root importer, as npm install specs.
lock_specs() {
  awk '
    /^importers:/ { imp = 1; next }
    /^packages:/ { exit }
    imp && /^      [^ ]/ { gsub(/[\x27:]/, ""); sub(/^ +/, ""); name = $0; next }
    imp && name && /^        version:/ {
      v = $2; gsub(/\x27/, "", v); sub(/\(.*/, "", v)
      if (v ~ /^@?[^@]+@/) print name "@npm:" v; else print name "@" v
      name = ""
    }' pnpm-lock.yaml
}
install_node() {
  if pnpm install --frozen-lockfile </dev/null; then
    node_ok && return 0
  fi
  # pnpm fails when the proxy blocks codeload.github.com (transitive
  # @zksync/contracts tarball). npm without saving touches no tracked file.
  echo "--- pnpm failed; falling back to npm --no-save"
  local specs
  mapfile -t specs < <(lock_specs)
  [ "${#specs[@]}" -gt 0 ] || { echo "could not read specs from pnpm-lock.yaml"; return 1; }
  echo "specs: ${specs[*]}"
  npm install --no-save --no-package-lock --ignore-scripts --legacy-peer-deps \
    --no-fund --no-audit "${specs[@]}" && node_ok
}
if ! node_ok; then
  run_step node-deps required install_node
fi

# --- solc warm-up build ------------------------------------------------------
# Downloads solc on first run; later runs are an incremental no-op.
if command -v forge >/dev/null && soldeer_ok && node_ok; then
  run_step build required forge build
fi

# --- slither (optional) -----------------------------------------------------
install_slither() {
  python3 -m venv "$SLITHER_VENV" &&
    "$SLITHER_VENV/bin/pip" install -q slither-analyzer &&
    "$SLITHER_VENV/bin/slither" --version
}
if [ ! -x "$SLITHER_VENV/bin/slither" ]; then
  rm -rf "$SLITHER_VENV"
  run_step slither optional install_slither || rm -rf "$SLITHER_VENV"
fi

# --- just (optional) --------------------------------------------------------
if ! command -v just >/dev/null; then
  run_step just optional npm install -g --no-fund --no-audit "$JUST_NPM_PKG"
fi

# --- report -----------------------------------------------------------------
if [ "${#failures[@]}" -eq 0 ]; then
  echo "session-setup: ok (forge $FOUNDRY_VERSION${forge_source:+ via $forge_source}, deps, slither, just)"
else
  printf '%s\n' "${failures[@]}"
fi
exit "$required_failed"
