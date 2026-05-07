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
  scripts/worktree.sh root-status
  scripts/worktree.sh sync-root [branch]
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

repo_root_branch() {
  git -C "${repo_root}" branch --show-current 2>/dev/null || true
}

repo_root_default_branch() {
  local remote_head
  remote_head="$(git -C "${repo_root}" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "${remote_head}" ]]; then
    printf '%s\n' "${remote_head#origin/}"
    return 0
  fi

  printf 'main\n'
}

repo_root_upstream_counts() {
  local upstream_ref
  upstream_ref="$(git -C "${repo_root}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ -z "${upstream_ref}" ]]; then
    printf '0 0\n'
    return 0
  fi

  git -C "${repo_root}" rev-list --left-right --count "HEAD...${upstream_ref}"
}

repo_root_non_unmerged_tracked_paths() {
  git -C "${repo_root}" status --short --untracked-files=no | \
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
  git -C "${repo_root}" status --short --untracked-files=no | \
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
  git -C "${repo_root}" status --short | awk 'substr($0, 1, 2) == "??" { print substr($0, 4) }'
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

  printf 'path=%s\n' "${repo_root}"
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

sync_repo_root() {
  local target_branch="${1:-$(repo_root_default_branch)}"
  bash "${repo_root}/scripts/agent_guard.sh" run-exclusive git-sync-root -- \
    bash -lc '
      repo_root="$1"
      target_branch="$2"

      current_branch="$(git -C "$repo_root" branch --show-current 2>/dev/null || true)"
      if [[ "$current_branch" != "$target_branch" ]]; then
        echo "Error: Repo root is on ${current_branch:-HEAD}, expected ${target_branch}." >&2
        exit 1
      fi

      if [[ -n "$(git -C "$repo_root" status --porcelain --untracked-files=no)" ]]; then
        echo "Error: Repo root has tracked changes or unresolved conflicts. Move them to an issue worktree before syncing." >&2
        exit 1
      fi

      git -C "$repo_root" fetch --prune origin
      git -C "$repo_root" pull --ff-only origin "$target_branch"
    ' -- "${repo_root}" "${target_branch}"
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

  if [[ "${delete_branch}" -eq 1 && "${branch_name}" != "HEAD" ]]; then
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
  root-status)
    show_repo_root_status
    ;;
  sync-root)
    shift
    [[ $# -le 1 ]] || die "sync-root accepts at most one optional branch argument."
    sync_repo_root "${1:-}"
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
