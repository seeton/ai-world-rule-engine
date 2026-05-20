#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  scripts/launch_copilot.sh [--] [copilot-args...]

Launch GitHub Copilot CLI with this repository's preferred defaults:
  --model gpt-5.4
  --effort high
  --allow-all

The launcher prepends those defaults, then forwards any extra Copilot arguments.
Pass `--` before Copilot arguments when you want to be explicit.

Examples:
  bash scripts/launch_copilot.sh
  bash scripts/launch_copilot.sh -- --continue
  bash scripts/launch_copilot.sh -- --model gpt-5-mini
EOF
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

if [[ "${1:-}" == "--" ]]; then
  shift
fi

command -v copilot >/dev/null 2>&1 || die "copilot command not found in PATH."

default_args=(
  --model gpt-5.4
  --effort high
  --allow-all
)

exec copilot "${default_args[@]}" "$@"
