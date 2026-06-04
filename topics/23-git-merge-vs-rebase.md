# Git Merge vs Rebase

### Comparison

| | git merge | git rebase |
|-|-----------|-----------|
| History | Non-linear — merge commits | Linear — clean |
| Use when | Integrating to main | Updating feature branch |
| Rewrites history | No | Yes |
| Safe on shared branches | Yes | No |

### Merge Example
```bash
git checkout main
git merge feature/my-feature
# Creates a merge commit — history preserved
```

### Rebase Example
```bash
git checkout feature/my-feature
git rebase main
# Replays your commits on top of main — clean history
```

> **Golden rule:** Never rebase `main` or `develop`. Only rebase your own local feature branches before opening a PR.
