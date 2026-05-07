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
  scripts/worktree.sh status [--stale-days <days>]
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
state_root="${workspace_root}/.coord"
issue_claims_dir="${state_root}/issues"
pr_claims_dir="${state_root}/prs"

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

normalize_worktree_path() {
  local raw_path="$1"
  local absolute_path="$raw_path"

  if [[ "${absolute_path}" != /* ]]; then
    absolute_path="${repo_root}/${absolute_path}"
  fi

  if [[ -d "${absolute_path}" ]]; then
    (
      cd "${absolute_path}"
      pwd -P
    )
    return 0
  fi

  local parent_dir
  parent_dir="$(dirname "${absolute_path}")"
  if [[ -d "${parent_dir}" ]]; then
    printf '%s/%s\n' "$(cd "${parent_dir}" && pwd -P)" "$(basename "${absolute_path}")"
    return 0
  fi

  printf '%s\n' "${absolute_path}"
}

claims_match_worktree_path() {
  local lhs="${1:-}"
  local rhs="${2:-}"
  [[ -n "${lhs}" && -n "${rhs}" ]] || return 1
  [[ "$(normalize_worktree_path "${lhs}")" == "$(normalize_worktree_path "${rhs}")" ]]
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

issue_state_for_worktree() {
  local issue_number="$1"
  gh issue view "${issue_number}" --json state --jq '.state' 2>/dev/null || printf 'UNKNOWN\n'
}

worktree_git_state() {
  local target_path="$1"
  local tracked_status

  tracked_status="$(git -C "${target_path}" status --short --untracked-files=no)"
  if [[ -n "$(printf '%s\n' "${tracked_status}" | awk 'substr($0, 1, 2) ~ /^(AA|AU|DD|DU|UA|UD|UU)$/' )" ]]; then
    printf 'unmerged\n'
    return 0
  fi

  if [[ -n "$(git -C "${target_path}" status --porcelain)" ]]; then
    printf 'dirty\n'
    return 0
  fi

  printf 'clean\n'
}

worktree_changed_paths() {
  local target_path="$1"

  {
    git -C "${target_path}" diff --name-only
    git -C "${target_path}" diff --cached --name-only
    git -C "${target_path}" diff --name-only --diff-filter=U
    git -C "${target_path}" ls-files --others --exclude-standard
  } | awk 'NF' | sort -u
}

worktree_latest_changed_path_epoch() {
  local target_path="$1"
  local changed_path
  local max_epoch=0

  while IFS= read -r changed_path; do
    local absolute_path
    local path_epoch
    absolute_path="${target_path}/${changed_path}"
    if [[ -e "${absolute_path}" ]]; then
      path_epoch="$(stat -f '%m' "${absolute_path}" 2>/dev/null || printf '0\n')"
      if (( path_epoch > max_epoch )); then
        max_epoch="${path_epoch}"
      fi
    fi
  done < <(worktree_changed_paths "${target_path}")

  printf '%s\n' "${max_epoch}"
}

worktree_last_update_epoch() {
  local target_path="$1"
  local git_state="$2"
  local head_epoch dirty_epoch

  head_epoch="$(git -C "${target_path}" log -1 --format=%ct 2>/dev/null || printf '0\n')"
  if [[ "${git_state}" == "clean" ]]; then
    printf '%s\n' "${head_epoch}"
    return 0
  fi

  dirty_epoch="$(worktree_latest_changed_path_epoch "${target_path}")"
  if (( dirty_epoch > head_epoch )); then
    printf '%s\n' "${dirty_epoch}"
  else
    printf '%s\n' "${head_epoch}"
  fi
}

epoch_to_iso_utc() {
  local epoch="$1"
  if [[ "${epoch}" =~ ^[0-9]+$ ]] && (( epoch > 0 )); then
    date -u -r "${epoch}" +"%Y-%m-%dT%H:%M:%SZ"
  else
    printf 'unknown\n'
  fi
}

issue_claim_state_for_worktree() {
  local issue_number="$1"
  local target_path="$2"
  local claim_path="${issue_claims_dir}/${issue_number}.claim"
  local claim_owner=""

  if [[ -f "${claim_path}" ]]; then
    claim_owner="$(cat "${claim_path}")"
  fi

  if claims_match_worktree_path "${claim_owner}" "${target_path}"; then
    printf 'claimed\n'
  else
    printf 'unclaimed\n'
  fi
}

pr_claims_for_worktree() {
  local target_path="$1"
  local claim_path
  local claim_owner
  local found=0

  if [[ ! -d "${pr_claims_dir}" ]]; then
    printf '-\n'
    return 0
  fi

  while IFS= read -r claim_path; do
    claim_owner="$(cat "${claim_path}")"
    if claims_match_worktree_path "${claim_owner}" "${target_path}"; then
      found=1
      printf '%s\n' "$(basename "${claim_path}" .claim)"
    fi
  done < <(find "${pr_claims_dir}" -type f -name '*.claim' -print | sort)

  if (( found == 0 )); then
    printf '%s\n' "-"
  fi
}

composite_worktree_status() {
  local issue_state="$1"
  local git_state="$2"
  local claim_state="$3"
  local stale_state="$4"
  local normalized_issue_state
  local result

  normalized_issue_state="$(printf '%s' "${issue_state}" | tr '[:upper:]' '[:lower:]')"
  result="${normalized_issue_state}-${git_state}"
  if [[ "${claim_state}" == "claimed" ]]; then
    result="${result}-claimed"
  fi
  if [[ "${stale_state}" == "stale" ]]; then
    result="${result}-stale"
  fi

  printf '%s\n' "${result}"
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
  local issue_number branch_name base_ref default_branch target_path current_branch
  issue_number="$(resolve_issue "${1:-}")"
  branch_name="${2:-}"
  default_branch="$(repo_root_default_branch)"
  base_ref="${3:-origin/${default_branch}}"
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

  if git -C "${repo_root}" show-ref --verify --quiet "refs/heads/${branch_name}"; then
    git -C "${repo_root}" worktree add "${target_path}" "${branch_name}"
  else
    git -C "${repo_root}" worktree add -b "${branch_name}" "${target_path}" "${base_ref}"
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

show_worktree_status() {
  local stale_days=14
  local option
  local now_epoch
  local found=0

  while [[ $# -gt 0 ]]; do
    option="$1"
    case "${option}" in
      --stale-days)
        [[ $# -ge 2 ]] || die "--stale-days requires a value"
        [[ "$2" =~ ^[0-9]+$ ]] || die "--stale-days must be a non-negative integer"
        stale_days="$2"
        shift 2
        ;;
      *)
        die "Unknown option for status: ${option}"
        ;;
    esac
  done

  now_epoch="$(date +%s)"
  printf 'stale_days=%s\n' "${stale_days}"
  printf 'ISSUE\tISSUE_STATE\tGIT_STATE\tCLAIM_STATE\tPR_CLAIMS\tSTALE\tAGE_DAYS\tLAST_UPDATED\tBRANCH\tPATH\tSTATUS\n'

  while IFS=$'\t' read -r issue_number target_path; do
    local issue_state
    local git_state
    local claim_state
    local pr_claims
    local branch_name
    local last_update_epoch
    local age_days
    local stale_state="fresh"
    local last_updated_iso
    local status_label

    found=1
    issue_state="$(issue_state_for_worktree "${issue_number}")"
    git_state="$(worktree_git_state "${target_path}")"
    claim_state="$(issue_claim_state_for_worktree "${issue_number}" "${target_path}")"
    pr_claims="$(pr_claims_for_worktree "${target_path}" | paste -sd ',' -)"
    branch_name="$(git -C "${target_path}" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'HEAD\n')"
    last_update_epoch="$(worktree_last_update_epoch "${target_path}" "${git_state}")"
    if (( last_update_epoch > 0 )); then
      age_days=$(( (now_epoch - last_update_epoch) / 86400 ))
      if (( age_days >= stale_days )); then
        stale_state="stale"
      fi
    else
      age_days=-1
      stale_state="unknown"
    fi
    last_updated_iso="$(epoch_to_iso_utc "${last_update_epoch}")"
    status_label="$(composite_worktree_status "${issue_state}" "${git_state}" "${claim_state}" "${stale_state}")"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${issue_number}" \
      "${issue_state}" \
      "${git_state}" \
      "${claim_state}" \
      "${pr_claims}" \
      "${stale_state}" \
      "${age_days}" \
      "${last_updated_iso}" \
      "${branch_name}" \
      "${target_path}" \
      "${status_label}"
  done < <(
    git -C "${repo_root}" worktree list --porcelain | \
      awk -v prefix="${workspace_root}/issue-" '
        /^worktree / {
          path = substr($0, 10)
          if (index(path, prefix) == 1) {
            issue = substr(path, length(prefix) + 1)
            if (issue ~ /^[0-9]+$/) {
              printf "%s\t%s\n", issue, path
            }
          }
        }
      ' | sort -n
  )

  if (( found == 0 )); then
    echo "No repo-local issue worktrees found under ${workspace_root}"
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
  git -C "${repo_root}" worktree remove ${force_flag} "${target_path}"

  if [[ "${delete_branch}" -eq 1 && "${branch_name}" != "HEAD" ]]; then
    git -C "${repo_root}" branch -D "${branch_name}"
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
  status)
    shift
    show_worktree_status "$@"
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
