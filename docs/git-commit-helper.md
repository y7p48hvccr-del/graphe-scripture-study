# Git Commit Helper

Helper script:

- [git-commit-push.sh](/Users/richardbillings/XcodeOffline/ScriptureStudy2/scripts/git-commit-push.sh)

## Usage

Create a local commit:

```zsh
scripts/git-commit-push.sh "Your commit message"
```

Create a local commit and push it to GitHub:

```zsh
scripts/git-commit-push.sh "Your commit message" --push
```

## What It Does

- shows the current branch
- shows `git status`
- stages all current changes with `git add -A`
- creates the commit
- optionally pushes to `origin/<current-branch>`

## Suggested Workflow

For the current handoff boundary:

```zsh
scripts/git-commit-push.sh "Refine Search layout and sidebar behavior"
```

Then, if the commit looks right:

```zsh
git push origin "$(git branch --show-current)"
```
