# Source this file: it only exports variables.
# Non-interactive shells on this machine do not have node on PATH; it lives in nvm.
if ! command -v node >/dev/null 2>&1; then
  NODE_BIN=$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1)
  [ -n "$NODE_BIN" ] && export PATH="$NODE_BIN:$PATH"
fi
export QUARTZ_DIR="${QUARTZ_DIR:-$HOME/quartz-banbe}"
export SITES_ROOT="${SITES_ROOT:-$HOME/quartz-sites}"
export REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
