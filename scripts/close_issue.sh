#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  scripts/close_issue.sh <issue-number> [--reason completed|not-planned] [--repo owner/name] [--delete-branch] [--force-remove]

Closes a GitHub issue through the local repository workflow:
  1. fetch the repo root from origin
  2. fast-forward pull the repo root when it is a clean checkout of the default branch
  3. close the issue via gh
  4. release issue/PR/worktree claims for the issue worktree
  5. remove the repo-local worktree for the issue

Run this from the repository root or another worktree, not from the issue worktree being removed.
EOF
}

git_common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die "Run this command inside the repository."
repo_root="$(cd "${git_common_dir}/.." && pwd -P)"
workspace_root="${repo_root}/.agent-workspaces"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

resolve_issue() {
  local issue_number="${1:-}"
  [[ "${issue_number}" =~ ^[0-9]+$ ]] || die "Issue number must be numeric."
  printf '%s\n' "${issue_number}"
}

target_worktree_path() {
  local issue_number
  issue_number="$(resolve_issue "${1:-}")"
  printf '%s/issue-%s\n' "${workspace_root}" "${issue_number}"
}

worktree_exists() {
  local target_path="$1"
  git -C "${repo_root}" worktree list --porcelain | awk '/^worktree / { print substr($0, 10) }' | grep -Fx "${target_path}" >/dev/null
}

worktree_is_clean() {
  local target_path="$1"
  [[ -z "$(git -C "${target_path}" status --porcelain)" ]]
}

root_is_clean() {
  [[ -z "$(git -C "${repo_root}" status --porcelain --untracked-files=no)" ]]
}

maybe_pull_repo_root() {
  local default_branch="$1"
  bash "${script_dir}/agent_guard.sh" run-exclusive git-sync-root -- \
    bash -lc '
      repo_root="$1"
      default_branch="$2"

      current_branch="$(git -C "$repo_root" branch --show-current 2>/dev/null || true)"
      if [[ "$current_branch" != "$default_branch" ]]; then
        echo "Skipping repo-root pull because ${repo_root} is on ${current_branch:-HEAD}, not ${default_branch}." >&2
        exit 0
      fi

      if [[ -n "$(git -C "$repo_root" status --porcelain --untracked-files=no)" ]]; then
        echo "Skipping repo-root pull because ${repo_root} has tracked changes or unresolved conflicts." >&2
        exit 0
      fi

      if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
        echo "Repo-root has only untracked files; continuing with ff-only pull." >&2
      fi

      git -C "$repo_root" pull --ff-only origin "$default_branch"
    ' -- "${repo_root}" "${default_branch}"
}

close_issue() {
  local issue_number="$1"
  local reason="$2"
  local repo_name="$3"
  local delete_branch="$4"
  local force_remove="$5"
  local target_path="$6"
  local remove_args

  bash "${script_dir}/agent_guard.sh" run-exclusive git-fetch -- \
    git -C "${repo_root}" fetch --prune origin

  local default_branch
  default_branch="$(gh repo view "${repo_name}" --json defaultBranchRef --jq '.defaultBranchRef.name')"
  maybe_pull_repo_root "${default_branch}"

  local issue_state
  issue_state="$(gh issue view "${issue_number}" --repo "${repo_name}" --json state --jq '.state')"
  if [[ "${issue_state}" == "OPEN" ]]; then
    gh issue close "${issue_number}" --repo "${repo_name}" --reason "${reason}"
  elif [[ "${issue_state}" != "CLOSED" ]]; then
    die "Unsupported issue state for #${issue_number}: ${issue_state}"
  fi

  bash "${script_dir}/agent_guard.sh" release-worktree ".agent-workspaces/issue-${issue_number}"

  if worktree_exists "${target_path}"; then
    remove_args=(remove "${issue_number}")
    if [[ "${force_remove}" == "1" ]]; then
      remove_args+=(--force)
    fi
    if [[ "${delete_branch}" == "1" ]]; then
      remove_args+=(--delete-branch)
    fi

    (
      cd "${repo_root}"
      bash "${script_dir}/worktree.sh" "${remove_args[@]}"
    )
  fi
}

reason="completed"
repo_name=""
delete_branch=0
force_remove=0

issue_number="${1:-}"
if [[ "${issue_number}" == "-h" || "${issue_number}" == "--help" || "${issue_number}" == "help" ]]; then
  usage
  exit 0
fi
[[ -n "${issue_number}" ]] || { usage; exit 1; }
issue_number="$(resolve_issue "${issue_number}")"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reason)
      [[ $# -ge 2 ]] || die "--reason requires a value"
      reason="$2"
      if [[ "${reason}" == "not-planned" ]]; then
        reason="not planned"
      fi
      [[ "${reason}" == "completed" || "${reason}" == "not planned" ]] || die "--reason must be 'completed', 'not-planned', or quoted 'not planned'"
      shift 2
      ;;
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
      usage
      die "Unknown option: $1"
      ;;
  esac
done

target_path="$(target_worktree_path "${issue_number}")"
current_dir="$(pwd -P)"
if [[ "${current_dir}" == "${target_path}" || "${current_dir}" == "${target_path}/"* ]]; then
  die "Run this command from the repository root or another worktree, not from ${target_path}."
fi

if [[ -z "${repo_name}" ]]; then
  repo_name="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
fi

if worktree_exists "${target_path}" && [[ "${force_remove}" != "1" ]] && ! worktree_is_clean "${target_path}"; then
  die "Worktree ${target_path} has local changes. Commit, stash, or rerun with --force-remove."
fi

close_issue "${issue_number}" "${reason}" "${repo_name}" "${delete_branch}" "${force_remove}" "${target_path}"
