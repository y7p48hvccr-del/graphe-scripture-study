#!/bin/zsh

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/git-commit-push.sh "Commit message" [--push]

Examples:
  scripts/git-commit-push.sh "Refine Search layout"
  scripts/git-commit-push.sh "Add Studio Graphe One theme" --push
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 1
fi

commit_message="$1"
push_after_commit="${2:-}"

if [[ -z "$commit_message" ]]; then
    echo "Commit message cannot be empty."
    exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not inside a git repository."
    exit 1
fi

current_branch="$(git branch --show-current)"

if [[ -z "$current_branch" ]]; then
    echo "Could not determine the current branch."
    exit 1
fi

echo
echo "Branch: $current_branch"
echo
echo "Status before add:"
git status --short

git add -A

if git diff --cached --quiet; then
    echo
    echo "No staged changes to commit."
    exit 0
fi

echo
echo "Staged changes:"
git status --short

git commit -m "$commit_message"

if [[ "$push_after_commit" == "--push" ]]; then
    git push origin "$current_branch"
    echo
    echo "Pushed to origin/$current_branch"
elif [[ -n "$push_after_commit" ]]; then
    usage
    exit 1
else
    echo
    echo "Commit created locally on $current_branch"
    echo "To push later, run:"
    echo "  git push origin $current_branch"
fi
