#!/usr/bin/env bash
# Collapse-safe last-line-of-defense CLI launcher for the rule engine.
# Mirrors scripts/launch_godot.sh's worktree-guard pattern: refuses repo-root
# Godot launches and only runs from a registered .agent-workspaces/issue-<n>/
# worktree, so the recovery surface stays out of the repo-root checkout.

set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  scripts/world_cli.sh <issue-number> [--project <path>] [--snapshot <path>]
                       [--json] [--allow-detached-head] [--dry-run]
                       -- <command> [args...]

Launch the headless Godot CLI for engine inspection / rule lifecycle / snapshot
operations from a repo-local issue worktree. Refuses to run against the
repository root.

Options:
  --project <path>         Godot project directory inside the issue worktree
                           (default: godot-world).
  --snapshot <path>        Snapshot file to load before running the command.
  --json                   Forward --json to the CLI (machine-parseable stdout).
  --allow-detached-head    Permit running from a detached-HEAD worktree.
  --dry-run                Validate and print the launch command without
                           starting Godot.
  --                       Mark the start of CLI subcommand arguments.

Subcommands handled by the CLI itself:
  inspect
  rule enable <rule_id>
  rule disable <rule_id>
  package list
  snapshot dump <path>
  snapshot load <path>
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
  git -C "${repo_root}" worktree list --porcelain | awk '/^worktree / { print substr($0, 10) }' | grep -Fx "${target_path}" >/dev/null
}

current_branch_for_worktree() {
  local target_path="$1"
  git -C "${target_path}" symbolic-ref --quiet --short HEAD 2>/dev/null || true
}

resolve_path_inside_worktree() {
  local target_worktree="$1"
  local requested_path="$2"

  python3 - "$target_worktree" "$requested_path" <<'PY'
from pathlib import Path
import sys

worktree = Path(sys.argv[1]).resolve(strict=True)
requested = Path(sys.argv[2])
candidate = requested if requested.is_absolute() else worktree / requested

try:
    resolved = candidate.resolve(strict=True)
except FileNotFoundError:
    print(candidate, file=sys.stderr)
    sys.exit(2)

try:
    resolved.relative_to(worktree)
except ValueError:
    sys.exit(3)

print(resolved)
PY
}

issue_number="${1:-}"
if [[ -z "${issue_number}" || "${issue_number}" == "-h" || "${issue_number}" == "--help" || "${issue_number}" == "help" ]]; then
  usage
  if [[ -z "${issue_number}" ]]; then
    exit 1
  fi
  exit 0
fi
issue_number="$(resolve_issue "${issue_number}")"
shift

project_path="godot-world"
snapshot_path=""
json_flag=0
allow_detached_head=0
dry_run=0
cli_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || die "--project requires a value"
      project_path="$2"
      shift 2
      ;;
    --snapshot)
      [[ $# -ge 2 ]] || die "--snapshot requires a value"
      snapshot_path="$2"
      shift 2
      ;;
    --json)
      json_flag=1
      shift
      ;;
    --allow-detached-head)
      allow_detached_head=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --)
      shift
      cli_args=("$@")
      break
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1 (did you forget '--' before the CLI subcommand?)"
      ;;
  esac
done

[[ "${#cli_args[@]}" -gt 0 ]] || die "Missing CLI subcommand. Use '-- <command>' to pass arguments through."

target_worktree="$(worktree_path_for_issue "${issue_number}")"
worktree_exists "${target_worktree}" || die "No registered worktree at ${target_worktree}. Create or reuse it before running the CLI."

branch_name="$(current_branch_for_worktree "${target_worktree}")"
if [[ -z "${branch_name}" ]]; then
  detached_sha="$(git -C "${target_worktree}" rev-parse --short HEAD)"
  if [[ "${allow_detached_head}" != "1" ]]; then
    die "Worktree ${target_worktree} is detached at ${detached_sha}. Reattach it to an issue branch or rerun with --allow-detached-head if that state is intentional."
  fi
fi

set +e
resolved_project="$(resolve_path_inside_worktree "${target_worktree}" "${project_path}" 2>&1)"
resolve_status=$?
set -e

if [[ "${resolve_status}" -eq 2 ]]; then
  die "Project path does not exist: ${resolved_project}"
elif [[ "${resolve_status}" -eq 3 ]]; then
  die "Refusing to launch ${project_path}: the resolved path must stay inside ${target_worktree}, not the repo root or another checkout."
elif [[ "${resolve_status}" -ne 0 ]]; then
  die "Unable to resolve project path ${project_path}"
fi

[[ -d "${resolved_project}" ]] || die "Project path must be a directory: ${resolved_project}"
[[ -f "${resolved_project}/project.godot" ]] || die "No project.godot found in ${resolved_project}"

repo_project_root="${repo_root}/godot-world"
if [[ "${resolved_project}" == "${repo_project_root}" || "${resolved_project}" == "${repo_project_root}/"* ]]; then
  die "Refusing to launch repo-root Godot content at ${resolved_project}. Use an issue worktree path under ${target_worktree}."
fi

[[ -f "${resolved_project}/scripts/cli/main.gd" ]] || die "CLI entrypoint not found at ${resolved_project}/scripts/cli/main.gd"

godot_bin="${GODOT_BIN:-godot}"
launch_command=("${godot_bin}" --headless --path "${resolved_project}" --script "res://scripts/cli/main.gd" "--")
if [[ "${json_flag}" == "1" ]]; then
  launch_command+=("--json")
fi
if [[ -n "${snapshot_path}" ]]; then
  launch_command+=("--snapshot" "${snapshot_path}")
fi
launch_command+=("${cli_args[@]}")

if [[ "${dry_run}" == "1" ]]; then
  if [[ -n "${branch_name}" ]]; then
    printf 'Validated issue #%s worktree %s on branch %s\n' "${issue_number}" "${target_worktree}" "${branch_name}"
  else
    printf 'Validated issue #%s worktree %s in detached HEAD mode\n' "${issue_number}" "${target_worktree}"
  fi
  printf 'Project: %s\n' "${resolved_project}"
  printf 'Command:'
  printf ' %q' "${launch_command[@]}"
  printf '\n'
  exit 0
fi

exec "${launch_command[@]}"
