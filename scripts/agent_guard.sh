#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/.agent-workspaces/.coord"
ISSUES_DIR="$STATE_DIR/issues"
WORKTREES_DIR="$STATE_DIR/worktrees"
PRS_DIR="$STATE_DIR/prs"
LOCKS_DIR="$STATE_DIR/locks"

mkdir -p "$ISSUES_DIR" "$WORKTREES_DIR" "$PRS_DIR" "$LOCKS_DIR"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/agent_guard.sh claim-issue <issue-id> <worktree-path>
  bash scripts/agent_guard.sh release-issue <issue-id> <worktree-path>
  bash scripts/agent_guard.sh claim-pr <pr-number> <worktree-path>
  bash scripts/agent_guard.sh release-pr <pr-number> <worktree-path>
  bash scripts/agent_guard.sh run-exclusive <operation-name> -- <command...>
  bash scripts/agent_guard.sh status
EOF
}

sanitize() {
  printf '%s' "$1" | tr '/: ' '___'
}

issue_claim_path() {
  printf '%s/%s.claim' "$ISSUES_DIR" "$1"
}

worktree_claim_path() {
  printf '%s/%s.claim' "$WORKTREES_DIR" "$(sanitize "$1")"
}

pr_claim_path() {
  printf '%s/%s.claim' "$PRS_DIR" "$1"
}

write_claim() {
  local path="$1"
  local content="$2"
  printf '%s\n' "$content" >"$path"
}

read_claim() {
  local path="$1"
  if [[ -f "$path" ]]; then
    cat "$path"
  fi
}

claim_issue() {
  local issue_id="$1"
  local worktree_path="$2"
  local issue_path
  local worktree_path_claim

  issue_path="$(issue_claim_path "$issue_id")"
  worktree_path_claim="$(worktree_claim_path "$worktree_path")"

  local current_issue_owner
  current_issue_owner="$(read_claim "$issue_path")"
  if [[ -n "${current_issue_owner:-}" && "$current_issue_owner" != "$worktree_path" ]]; then
    echo "Issue $issue_id is already claimed by $current_issue_owner" >&2
    exit 1
  fi

  local current_worktree_owner
  current_worktree_owner="$(read_claim "$worktree_path_claim")"
  if [[ -n "${current_worktree_owner:-}" && "$current_worktree_owner" != "$issue_id" ]]; then
    echo "Worktree $worktree_path is already claimed for issue $current_worktree_owner" >&2
    exit 1
  fi

  write_claim "$issue_path" "$worktree_path"
  write_claim "$worktree_path_claim" "$issue_id"
  echo "Claimed issue $issue_id for $worktree_path"
}

release_issue() {
  local issue_id="$1"
  local worktree_path="$2"
  local issue_path
  local worktree_path_claim

  issue_path="$(issue_claim_path "$issue_id")"
  worktree_path_claim="$(worktree_claim_path "$worktree_path")"

  local current_issue_owner
  current_issue_owner="$(read_claim "$issue_path")"
  if [[ "$current_issue_owner" == "$worktree_path" ]]; then
    rm -f "$issue_path"
  fi

  local current_worktree_owner
  current_worktree_owner="$(read_claim "$worktree_path_claim")"
  if [[ "$current_worktree_owner" == "$issue_id" ]]; then
    rm -f "$worktree_path_claim"
  fi

  echo "Released issue $issue_id for $worktree_path"
}

claim_pr() {
  local pr_number="$1"
  local worktree_path="$2"
  local claim_path

  claim_path="$(pr_claim_path "$pr_number")"

  local current_owner
  current_owner="$(read_claim "$claim_path")"
  if [[ -n "${current_owner:-}" && "$current_owner" != "$worktree_path" ]]; then
    echo "PR $pr_number is already claimed by $current_owner" >&2
    exit 1
  fi

  write_claim "$claim_path" "$worktree_path"
  echo "Claimed PR $pr_number for $worktree_path"
}

release_pr() {
  local pr_number="$1"
  local worktree_path="$2"
  local claim_path

  claim_path="$(pr_claim_path "$pr_number")"

  local current_owner
  current_owner="$(read_claim "$claim_path")"
  if [[ "$current_owner" == "$worktree_path" ]]; then
    rm -f "$claim_path"
  fi

  echo "Released PR $pr_number for $worktree_path"
}

run_exclusive() {
  local operation_name="$1"
  shift

  if [[ "${1:-}" != "--" ]]; then
    echo "run-exclusive requires -- before the command" >&2
    exit 1
  fi
  shift

  if [[ "$#" -eq 0 ]]; then
    echo "run-exclusive requires a command to execute" >&2
    exit 1
  fi

  local lock_dir="$LOCKS_DIR/repo-exclusive.lock"
  local owner_file="$lock_dir/owner"

  local lock_acquired="false"

  if mkdir "$lock_dir" 2>/dev/null; then
    lock_acquired="true"
  else
    if [[ -f "$owner_file" ]]; then
      local current_pid
      current_pid="$(awk -F= '/^pid=/{print $2}' "$owner_file")"
      if [[ -n "${current_pid:-}" ]] && ! kill -0 "$current_pid" 2>/dev/null; then
        rm -rf "$lock_dir"
      fi
    fi
    if mkdir "$lock_dir" 2>/dev/null; then
      lock_acquired="true"
    fi
  fi

  if [[ "$lock_acquired" != "true" ]]; then
    echo "Exclusive operation already running:" >&2
    if [[ -f "$owner_file" ]]; then
      cat "$owner_file" >&2
    fi
    exit 1
  fi

  trap 'rm -rf "'"$lock_dir"'"' EXIT INT TERM

  cat >"$owner_file" <<EOF
operation=$operation_name
pid=$$
cwd=$(pwd)
command=$*
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

  "$@"
}

show_status() {
  echo "--- Issues ---"
  find "$ISSUES_DIR" -type f -name '*.claim' -print | sort | while read -r path; do
    printf '%s -> %s\n' "$(basename "$path" .claim)" "$(cat "$path")"
  done

  echo "--- Worktrees ---"
  find "$WORKTREES_DIR" -type f -name '*.claim' -print | sort | while read -r path; do
    printf '%s -> %s\n' "$(basename "$path" .claim)" "$(cat "$path")"
  done

  echo "--- PRs ---"
  find "$PRS_DIR" -type f -name '*.claim' -print | sort | while read -r path; do
    printf '%s -> %s\n' "$(basename "$path" .claim)" "$(cat "$path")"
  done

  echo "--- Locks ---"
  if [[ -f "$LOCKS_DIR/repo-exclusive.lock/owner" ]]; then
    cat "$LOCKS_DIR/repo-exclusive.lock/owner"
  else
    echo "none"
  fi
}

main() {
  local command="${1:-}"
  case "$command" in
    claim-issue)
      [[ $# -eq 3 ]] || { usage; exit 1; }
      claim_issue "$2" "$3"
      ;;
    release-issue)
      [[ $# -eq 3 ]] || { usage; exit 1; }
      release_issue "$2" "$3"
      ;;
    claim-pr)
      [[ $# -eq 3 ]] || { usage; exit 1; }
      claim_pr "$2" "$3"
      ;;
    release-pr)
      [[ $# -eq 3 ]] || { usage; exit 1; }
      release_pr "$2" "$3"
      ;;
    run-exclusive)
      [[ $# -ge 4 ]] || { usage; exit 1; }
      run_exclusive "$2" "${@:3}"
      ;;
    status)
      [[ $# -eq 1 ]] || { usage; exit 1; }
      show_status
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
