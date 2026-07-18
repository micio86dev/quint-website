#!/usr/bin/env bash
# Publishes the Quint frontend, backend, and wrapper repositories without force-pushing.

set -euo pipefail

OWNER="micio86dev"
ROOT_REPO="quint-website"
FRONTEND_REPO="quint-website-frontend"
BACKEND_REPO="quint-website-backend"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_missing_repository() {
  local repository="$1"
  local output

  if output="$(gh api "repos/${repository}" 2>&1)"; then
    die "GitHub repository ${repository} already exists; refusing to overwrite it."
  fi

  [[ "$output" == *"HTTP 404"* ]] || die "Could not safely determine whether ${repository} exists: ${output}"
}

require_clean_repository() {
  local directory="$1"

  [[ -z "$(git -C "$directory" status --porcelain)" ]] || die "${directory} has uncommitted changes. Commit or stash them first."
}

require_expected_origin() {
  local directory="$1"
  local expected_url="$2"
  local current_url

  current_url="$(git -C "$directory" remote get-url origin 2>/dev/null || true)"
  [[ "$current_url" == "$expected_url" ]] || die "${directory} origin is ${current_url:-unset}, expected ${expected_url}."
}

publish_component() {
  local directory="$1"
  local repository="$2"
  local expected_url="git@github.com:${OWNER}/${repository}.git"
  local current_url
  local branch

  require_clean_repository "$directory"
  branch="$(git -C "$directory" branch --show-current)"
  [[ -n "$branch" ]] || die "${directory} is in detached HEAD state."

  current_url="$(git -C "$directory" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$current_url" ]]; then
    require_missing_repository "${OWNER}/${repository}"
    gh repo create "${OWNER}/${repository}" --public --source "$directory" --remote origin --push
  else
    [[ "$current_url" == "$expected_url" ]] || die "${directory} origin is ${current_url}, expected ${expected_url}."
    git -C "$directory" push origin "$branch"
  fi

  git -C "$directory" ls-remote --exit-code origin "refs/heads/${branch}" >/dev/null
}

printf '%s\n' 'Checking GitHub CLI authentication...'
gh auth status -h github.com

authenticated_user="$(gh api user --jq .login)"
[[ "$authenticated_user" == "$OWNER" ]] || die "Authenticated as ${authenticated_user}, expected ${OWNER}."

ssh_output="$(ssh -o BatchMode=yes -T git@github.com 2>&1 || true)"
[[ "$ssh_output" == *"successfully authenticated"* ]] || die "GitHub SSH authentication failed: ${ssh_output}"

cd "$ROOT_DIR"
git rev-parse --is-inside-work-tree >/dev/null || die "${ROOT_DIR} is not a Git repository."

printf '%s\n' 'Publishing component repositories...'
publish_component "$ROOT_DIR/$FRONTEND_REPO" "$FRONTEND_REPO"
publish_component "$ROOT_DIR/$BACKEND_REPO" "$BACKEND_REPO"

[[ -z "$(git diff --name-only)" ]] || die 'The wrapper has unstaged changes. Stage only the reviewed publication files first.'
[[ -z "$(git ls-files --others --exclude-standard)" ]] || die 'The wrapper has untracked files. Review them before publishing.'

allowed_staged_files=(
  .gitignore
  .gitmodules
  DEVELOPMENT.md
  README.md
  docker-compose.yml
  publish-quint-repositories.sh
  start-local.sh
  quint-website-backend
  quint-website-frontend
)

staged_files="$(git diff --cached --name-only)"
[[ -n "$staged_files" ]] || die 'The wrapper index is empty. Stage the reviewed publication files first.'

while IFS= read -r staged_file; do
  allowed=false
  for allowed_file in "${allowed_staged_files[@]}"; do
    if [[ "$staged_file" == "$allowed_file" ]]; then
      allowed=true
      break
    fi
  done
  "$allowed" || die "${staged_file} is not an approved wrapper publication file."
done <<< "$staged_files"

[[ "$(git config -f .gitmodules --get submodule.${FRONTEND_REPO}.url)" == "git@github.com:${OWNER}/${FRONTEND_REPO}.git" ]] || die 'Frontend submodule URL is incorrect.'
[[ "$(git config -f .gitmodules --get submodule.${BACKEND_REPO}.url)" == "git@github.com:${OWNER}/${BACKEND_REPO}.git" ]] || die 'Backend submodule URL is incorrect.'
[[ "$(git ls-files --stage "$FRONTEND_REPO" | cut -d' ' -f2)" == "$(git -C "$FRONTEND_REPO" rev-parse HEAD)" ]] || die 'Staged frontend gitlink does not match its HEAD.'
[[ "$(git ls-files --stage "$BACKEND_REPO" | cut -d' ' -f2)" == "$(git -C "$BACKEND_REPO" rev-parse HEAD)" ]] || die 'Staged backend gitlink does not match its HEAD.'

root_branch="$(git branch --show-current)"
[[ -n "$root_branch" ]] || die 'The wrapper is in detached HEAD state.'

expected_root_url="git@github.com:${OWNER}/${ROOT_REPO}.git"
root_url="$(git remote get-url origin 2>/dev/null || true)"
if [[ -n "$root_url" ]]; then
  require_expected_origin "$ROOT_DIR" "$expected_root_url"
else
  require_missing_repository "${OWNER}/${ROOT_REPO}"
fi

printf '%s\n' 'Committing wrapper repository...'
git commit -m 'chore: publish workspace'

printf '%s\n' 'Publishing wrapper repository...'
if [[ -n "$root_url" ]]; then
  git push origin "$root_branch"
else
  gh repo create "${OWNER}/${ROOT_REPO}" --public --source "$ROOT_DIR" --remote origin --push
fi

printf '%s\n' 'Published all three repositories successfully.'
