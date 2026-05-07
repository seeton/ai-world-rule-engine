#!/usr/bin/env bash

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if git_common_dir="$(git -C "$SCRIPT_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  ROOT_DIR="$(cd "${git_common_dir}/.." && pwd -P)"
else
  ROOT_DIR="$SCRIPT_ROOT"
fi
STATE_DIR="$ROOT_DIR/.agent-workspaces/.coord"
ISSUES_DIR="$STATE_DIR/issues"
WORKTREES_DIR="$STATE_DIR/worktrees"
PRS_DIR="$STATE_DIR/prs"
LOCKS_DIR="$STATE_DIR/locks"
CLAIMS_LOCK_DIR="$LOCKS_DIR/claim-mutations.lock"

mkdir -p "$ISSUES_DIR" "$WORKTREES_DIR" "$PRS_DIR" "$LOCKS_DIR"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/agent_guard.sh claim-issue <issue-id> <worktree-path>
  bash scripts/agent_guard.sh release-issue <issue-id> <worktree-path>
  bash scripts/agent_guard.sh release-worktree <worktree-path>
  bash scripts/agent_guard.sh claim-pr <pr-number> <worktree-path>
  bash scripts/agent_guard.sh release-pr <pr-number> <worktree-path>
  bash scripts/agent_guard.sh run-exclusive <operation-name> -- <command...>
  bash scripts/agent_guard.sh status
  bash scripts/agent_guard.sh status-root

Claims are one-to-one: each issue can claim only one worktree path, and each worktree
path can be claimed for only one issue. Use status to inspect current ownership.
EOF
}

sanitize() {
  printf '%s' "$1" | tr '/: ' '___'
}

current_pid() {
  printf '%s\n' "${BASHPID:-$$}"
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

write_lock_owner() {
  local owner_file="$1"
  local operation_name="$2"
  local command_display="$3"

  cat >"$owner_file" <<EOF
operation=$operation_name
pid=$(current_pid)
cwd=$(pwd)
command=$command_display
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

cleanup_stale_lock() {
  local lock_dir="$1"
  local owner_file="$lock_dir/owner"

  if [[ ! -f "$owner_file" ]]; then
    return 1
  fi

  local owner_pid
  owner_pid="$(awk -F= '/^pid=/{print $2}' "$owner_file")"
  if [[ -n "${owner_pid:-}" ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
    rm -rf "$lock_dir"
    return 0
  fi

  return 1
}

acquire_lock() {
  local lock_dir="$1"
  local operation_name="$2"
  local busy_message="$3"
  local command_display="$4"
  local owner_file="$lock_dir/owner"

  if ! mkdir "$lock_dir" 2>/dev/null; then
    cleanup_stale_lock "$lock_dir" || true
    if ! mkdir "$lock_dir" 2>/dev/null; then
      echo "$busy_message" >&2
      if [[ -f "$owner_file" ]]; then
        cat "$owner_file" >&2
      fi
      return 1
    fi
  fi

  write_lock_owner "$owner_file" "$operation_name" "$command_display"
}

release_lock() {
  local lock_dir="$1"
  rm -rf "$lock_dir"
}

with_lock() {
  local lock_dir="$1"
  local operation_name="$2"
  local busy_message="$3"
  local command_display="$4"
  shift 4

  acquire_lock "$lock_dir" "$operation_name" "$busy_message" "$command_display" || return 1

  local exit_code=0
  "$@" || exit_code=$?
  release_lock "$lock_dir"
  return "$exit_code"
}

find_other_issue_for_worktree() {
  local worktree_path="$1"
  local expected_issue_id="$2"
  local path

  while IFS= read -r path; do
    local other_issue_id
    other_issue_id="$(basename "$path" .claim)"
    if [[ "$other_issue_id" != "$expected_issue_id" && "$(read_claim "$path")" == "$worktree_path" ]]; then
      printf '%s\n' "$other_issue_id"
      return 0
    fi
  done < <(find "$ISSUES_DIR" -type f -name '*.claim' -print | sort)

  return 1
}

find_other_worktree_claim_for_issue() {
  local issue_id="$1"
  local expected_worktree_path="$2"
  local path

  while IFS= read -r path; do
    local claimed_issue_id
    claimed_issue_id="$(read_claim "$path")"
    if [[ "$claimed_issue_id" == "$issue_id" && "$(basename "$path" .claim)" != "$(sanitize "$expected_worktree_path")" ]]; then
      printf '%s\n' "$(basename "$path" .claim)"
      return 0
    fi
  done < <(find "$WORKTREES_DIR" -type f -name '*.claim' -print | sort)

  return 1
}

claim_issue_locked() {
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
    return 1
  fi

  local current_worktree_owner
  current_worktree_owner="$(read_claim "$worktree_path_claim")"
  if [[ -n "${current_worktree_owner:-}" && "$current_worktree_owner" != "$issue_id" ]]; then
    echo "Worktree $worktree_path is already claimed for issue $current_worktree_owner" >&2
    return 1
  fi

  local other_issue_id=""
  other_issue_id="$(find_other_issue_for_worktree "$worktree_path" "$issue_id" || true)"
  if [[ -n "$other_issue_id" ]]; then
    echo "Worktree $worktree_path is already claimed for issue $other_issue_id" >&2
    return 1
  fi

  local other_worktree_claim=""
  other_worktree_claim="$(find_other_worktree_claim_for_issue "$issue_id" "$worktree_path" || true)"
  if [[ -n "$other_worktree_claim" ]]; then
    echo "Issue $issue_id already has another worktree claim: $other_worktree_claim" >&2
    return 1
  fi

  write_claim "$issue_path" "$worktree_path"
  write_claim "$worktree_path_claim" "$issue_id"
  echo "Claimed issue $issue_id for $worktree_path"
}

claim_issue() {
  local issue_id="$1"
  local worktree_path="$2"
  with_lock \
    "$CLAIMS_LOCK_DIR" \
    "claim-issue:$issue_id" \
    "Another claim mutation is already running:" \
    "claim-issue $issue_id $worktree_path" \
    claim_issue_locked "$issue_id" "$worktree_path"
}

release_issue_locked() {
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

release_issue() {
  local issue_id="$1"
  local worktree_path="$2"
  with_lock \
    "$CLAIMS_LOCK_DIR" \
    "release-issue:$issue_id" \
    "Another claim mutation is already running:" \
    "release-issue $issue_id $worktree_path" \
    release_issue_locked "$issue_id" "$worktree_path"
}

release_worktree_locked() {
  local worktree_path="$1"
  local path

  while IFS= read -r path; do
    if [[ "$(read_claim "$path")" == "$worktree_path" ]]; then
      rm -f "$path"
    fi
  done < <(find "$ISSUES_DIR" -type f -name '*.claim' -print | sort)

  rm -f "$(worktree_claim_path "$worktree_path")"

  while IFS= read -r path; do
    if [[ "$(read_claim "$path")" == "$worktree_path" ]]; then
      rm -f "$path"
    fi
  done < <(find "$PRS_DIR" -type f -name '*.claim' -print | sort)

  echo "Released all claims for $worktree_path"
}

release_worktree() {
  local worktree_path="$1"
  with_lock \
    "$CLAIMS_LOCK_DIR" \
    "release-worktree:$worktree_path" \
    "Another claim mutation is already running:" \
    "release-worktree $worktree_path" \
    release_worktree_locked "$worktree_path"
}

claim_pr_locked() {
  local pr_number="$1"
  local worktree_path="$2"
  local claim_path

  claim_path="$(pr_claim_path "$pr_number")"

  local current_owner
  current_owner="$(read_claim "$claim_path")"
  if [[ -n "${current_owner:-}" && "$current_owner" != "$worktree_path" ]]; then
    echo "PR $pr_number is already claimed by $current_owner" >&2
    return 1
  fi

  write_claim "$claim_path" "$worktree_path"
  echo "Claimed PR $pr_number for $worktree_path"
}

claim_pr() {
  local pr_number="$1"
  local worktree_path="$2"
  with_lock \
    "$CLAIMS_LOCK_DIR" \
    "claim-pr:$pr_number" \
    "Another claim mutation is already running:" \
    "claim-pr $pr_number $worktree_path" \
    claim_pr_locked "$pr_number" "$worktree_path"
}

release_pr_locked() {
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

release_pr() {
  local pr_number="$1"
  local worktree_path="$2"
  with_lock \
    "$CLAIMS_LOCK_DIR" \
    "release-pr:$pr_number" \
    "Another claim mutation is already running:" \
    "release-pr $pr_number $worktree_path" \
    release_pr_locked "$pr_number" "$worktree_path"
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

repo_root_branch() {
  git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true
}

repo_root_upstream_counts() {
  local upstream_ref
  upstream_ref="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ -z "${upstream_ref}" ]]; then
    printf '0 0\n'
    return 0
  fi

  git -C "$ROOT_DIR" rev-list --left-right --count "HEAD...${upstream_ref}"
}

repo_root_non_unmerged_tracked_paths() {
  git -C "$ROOT_DIR" status --short --untracked-files=no | \
    awk '
      {
        status = substr($0, 1, 2)
        if (status !~ /^(AA|AU|DD|DU|UA|UD|UU)$/) {
          print substr($0, 4)
        }
      }
    '
}

repo_root_unmerged_paths() {
  git -C "$ROOT_DIR" status --short --untracked-files=no | \
    awk '
      {
        status = substr($0, 1, 2)
        if (status ~ /^(AA|AU|DD|DU|UA|UD|UU)$/) {
          print substr($0, 4)
        }
      }
    '
}

repo_root_untracked_paths() {
  git -C "$ROOT_DIR" status --short | awk 'substr($0, 1, 2) == "??" { print substr($0, 4) }'
}

print_path_preview() {
  local label="$1"
  local raw_paths="${2:-}"
  local max_preview=5

  if [[ -z "${raw_paths}" ]]; then
    return 0
  fi

  printf '%s:\n' "$label"
  printf '%s\n' "${raw_paths}" | awk -v max_preview="${max_preview}" '
    NF {
      count += 1
      if (count <= max_preview) {
        print "  - " $0
      }
    }
    END {
      if (count > max_preview) {
        printf "  - ... (%d more)\n", count - max_preview
      }
    }
  '
}

count_non_empty_lines() {
  local raw_paths="${1:-}"
  if [[ -z "${raw_paths}" ]]; then
    printf '0\n'
    return 0
  fi

  printf '%s\n' "${raw_paths}" | awk 'NF { count += 1 } END { print count + 0 }'
}

show_repo_root_status() {
  local branch ahead behind
  local tracked_paths
  local unmerged_paths
  local untracked_paths
  local tracked_count
  local unmerged_count
  local untracked_count

  branch="$(repo_root_branch)"
  read -r ahead behind <<<"$(repo_root_upstream_counts)"
  tracked_paths="$(repo_root_non_unmerged_tracked_paths)"
  unmerged_paths="$(repo_root_unmerged_paths)"
  untracked_paths="$(repo_root_untracked_paths)"
  tracked_count="$(count_non_empty_lines "${tracked_paths}")"
  unmerged_count="$(count_non_empty_lines "${unmerged_paths}")"
  untracked_count="$(count_non_empty_lines "${untracked_paths}")"

  echo "--- Repo Root ---"
  printf 'path=%s\n' "$ROOT_DIR"
  printf 'branch=%s\n' "${branch:-HEAD}"
  printf 'ahead=%s\n' "$ahead"
  printf 'behind=%s\n' "$behind"
  printf 'tracked_changes=%s\n' "${tracked_count}"
  printf 'unmerged=%s\n' "${unmerged_count}"
  printf 'untracked=%s\n' "${untracked_count}"

  if (( unmerged_count > 0 )); then
    echo "state=blocked-unmerged"
  elif (( tracked_count > 0 )); then
    echo "state=dirty-tracked"
  elif (( untracked_count > 0 )); then
    echo "state=syncable-with-untracked"
  else
    echo "state=clean"
  fi

  print_path_preview "tracked_change_paths" "${tracked_paths}"
  print_path_preview "unmerged_paths" "${unmerged_paths}"
  print_path_preview "untracked_paths" "${untracked_paths}"
}

show_status() {
  show_repo_root_status
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
    release-worktree)
      [[ $# -eq 2 ]] || { usage; exit 1; }
      release_worktree "$2"
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
    status-root)
      [[ $# -eq 1 ]] || { usage; exit 1; }
      show_repo_root_status
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
