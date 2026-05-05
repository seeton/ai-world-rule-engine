#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  scripts/worktree.sh ensure <issue-number> <branch> [base-ref]
  scripts/worktree.sh list
  scripts/worktree.sh remove <issue-number> [--force] [--delete-branch]

Conventions:
  - repo-local worktrees live under .agent-workspaces/issue-<number>
  - one issue reuses one worktree path across runs
EOF
}

git_common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die "Run this command inside the repository."
repo_root="$(cd "${git_common_dir}/.." && pwd -P)"
workspace_root="${repo_root}/.agent-workspaces"

resolve_issue() {
  local issue_number="${1:-}"
  [[ "${issue_number}" =~ ^[0-9]+$ ]] || die "Issue number must be numeric."
  printf '%s\n' "${issue_number}"
}

worktree_path_for_issue() {
  local issue_number
  issue_number="$(resolve_issue "${1:-}")"
  printf '%s/issue-%s\n' "${workspace_root}" "${issue_number}"
}

worktree_exists() {
  local target_path="$1"
  git worktree list --porcelain | awk '/^worktree / { print substr($0, 10) }' | grep -Fx "${target_path}" >/dev/null
}

ensure_worktree() {
  local issue_number branch_name base_ref target_path current_branch
  issue_number="$(resolve_issue "${1:-}")"
  branch_name="${2:-}"
  base_ref="${3:-HEAD}"
  [[ -n "${branch_name}" ]] || die "Branch name is required."

  mkdir -p "${workspace_root}"
  target_path="$(worktree_path_for_issue "${issue_number}")"

  if worktree_exists "${target_path}"; then
    current_branch="$(git -C "${target_path}" rev-parse --abbrev-ref HEAD)"
    [[ "${current_branch}" == "${branch_name}" ]] || die "Existing ${target_path} uses branch ${current_branch}, expected ${branch_name}."
    printf 'Reusing %s on %s\n' "${target_path}" "${current_branch}"
    return 0
  fi

  if [[ -e "${target_path}" ]]; then
    die "${target_path} exists but is not a registered git worktree."
  fi

  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    git worktree add "${target_path}" "${branch_name}"
  else
    git worktree add -b "${branch_name}" "${target_path}" "${base_ref}"
  fi

  printf 'Created %s on %s\n' "${target_path}" "${branch_name}"
}

list_worktrees() {
  local found=0
  while IFS= read -r line; do
    found=1
    printf '%s\n' "${line}"
  done < <(
    git worktree list --porcelain |
      awk -v prefix="${workspace_root}/" '
        /^worktree / {
          path = substr($0, 10)
        }
        /^branch / && index(path, prefix) == 1 {
          branch = substr($0, 19)
          printf "%s [%s]\n", path, branch
        }
      '
  )

  if [[ "${found}" -eq 0 ]]; then
    echo "No repo-local agent worktrees found under ${workspace_root}"
  fi
}

remove_worktree() {
  local issue_number force_flag="" delete_branch=0 target_path branch_name
  issue_number="$(resolve_issue "${1:-}")"
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)
        force_flag="--force"
        ;;
      --delete-branch)
        delete_branch=1
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done

  target_path="$(worktree_path_for_issue "${issue_number}")"
  worktree_exists "${target_path}" || die "No registered worktree at ${target_path}"

  branch_name="$(git -C "${target_path}" rev-parse --abbrev-ref HEAD)"
  git worktree remove ${force_flag} "${target_path}"

  if [[ "${delete_branch}" -eq 1 ]]; then
    git branch -D "${branch_name}"
  fi

  printf 'Removed %s\n' "${target_path}"
}

command="${1:-}"
case "${command}" in
  ensure)
    shift
    ensure_worktree "$@"
    ;;
  list)
    list_worktrees
    ;;
  remove)
    shift
    remove_worktree "$@"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage
    die "Unknown command: ${command}"
    ;;
esac
