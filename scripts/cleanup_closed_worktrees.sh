#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  scripts/cleanup_closed_worktrees.sh [--repo owner/name] [--delete-branch] [--force-remove] [issue-number...]

Scans repo-local issue worktrees and cleans up the ones whose GitHub issues are already closed.
Without explicit issue numbers, all registered `.agent-workspaces/issue-<number>` worktrees are considered.
EOF
}

git_common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die "Run this command inside the repository."
repo_root="$(cd "${git_common_dir}/.." && pwd -P)"
workspace_root="${repo_root}/.agent-workspaces"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

repo_name=""
delete_branch=0
force_remove=0
issue_numbers=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires a value"
      repo_name="$2"
      shift 2
      ;;
    --delete-branch)
      delete_branch=1
      shift
      ;;
    --force-remove)
      force_remove=1
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      [[ "$1" =~ ^[0-9]+$ ]] || die "Issue number must be numeric: $1"
      issue_numbers+=("$1")
      shift
      ;;
  esac
done

if [[ -z "${repo_name}" ]]; then
  repo_name="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
fi

if [[ "${#issue_numbers[@]}" -eq 0 ]]; then
  while IFS= read -r path; do
    if [[ "${path}" == "${workspace_root}/issue-"* ]]; then
      issue_number="${path#"${workspace_root}/issue-"}"
      if [[ "${issue_number}" =~ ^[0-9]+$ ]]; then
        issue_numbers+=("${issue_number}")
      fi
    fi
  done < <(git -C "${repo_root}" worktree list --porcelain | awk '/^worktree / { print substr($0, 10) }')
fi

if [[ "${#issue_numbers[@]}" -eq 0 ]]; then
  echo "No repo-local issue worktrees found under ${workspace_root}"
  exit 0
fi

failures=0
for issue_number in "${issue_numbers[@]}"; do
  if ! issue_state="$(gh issue view "${issue_number}" --repo "${repo_name}" --json state --jq '.state')"; then
    echo "Failed to inspect #${issue_number}" >&2
    failures=1
    continue
  fi
  if [[ "${issue_state}" != "CLOSED" ]]; then
    echo "Skipping #${issue_number}: issue is ${issue_state}"
    continue
  fi

  args=("${issue_number}" "--repo" "${repo_name}")
  if [[ "${delete_branch}" == "1" ]]; then
    args+=("--delete-branch")
  fi
  if [[ "${force_remove}" == "1" ]]; then
    args+=("--force-remove")
  fi

  if ! bash "${script_dir}/close_issue.sh" "${args[@]}"; then
    failures=1
  fi
done

exit "${failures}"
