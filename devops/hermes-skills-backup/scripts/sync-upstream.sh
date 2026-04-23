#!/bin/bash
# ============================================================
# hermes-agent upstream sync script
# 用法: bash sync-upstream.sh
# ============================================================

set -e

cd ~/.hermes/hermes-agent

echo "=== Step 1: Fetch upstream (官方最新) ==="
git fetch upstream

echo ""
echo "=== Step 2: Rebase local changes on top of upstream/main ==="
# Count commits before rebase
COMMITS=$(git log --oneline upstream/main..main | wc -l)
echo "Local commits to preserve: $COMMITS"

git rebase upstream/main

echo ""
echo "=== Step 3: Push to your fork (origin) ==="
git push origin main

echo ""
echo "=== Done ==="
echo "Upstream is now: $(git log --oneline upstream/main -1)"
echo "Origin is now:   $(git log --oneline origin/main -1)"
echo ""
echo "如果 rebase 有冲突，手动解决后:"
echo "  git add <resolved-files>"
echo "  git rebase --continue"
echo ""
echo "如果想放弃 rebase 并重新开始:"
echo "  git rebase --abort"
echo "  git reset --hard origin/main"
