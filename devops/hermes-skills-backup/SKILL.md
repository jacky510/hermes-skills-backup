---
name: hermes-skills-backup
description: Backup hermes skills to GitHub repo
---

# Hermes Skills Backup

Backup skills from `~/.hermes/skills/` to https://github.com/jacky510/hermes-skills-backup

Token 存在 memory 中（查找 `GitHub backup token`）。Skill 运行时从 memory 读取。

## Setup (one-time, already done)

Repo already created and initial push done. Skip setup unless repo was deleted.

## Backup (ongoing)

```bash
cd ~/.hermes/skills && git add -A && git commit -m "update - $(date +'%Y-%m-%d %H:%M')" && git push
```

## Verification

```bash
git log --oneline -3
git remote -v
```
