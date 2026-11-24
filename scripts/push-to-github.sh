#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${1:-https://github.com/gao746700783/pjsip-ios-sdk.git}"
TAG="${2:-0.1.0}"

if [ ! -d ".git" ]; then
  git init -b main
fi

git add .
if ! git diff --cached --quiet; then
  git commit -m "feat: initial pjsip-ios-sdk wrapping PJSUA2 on swift-pjsip"
fi

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REPO_URL"
else
  git remote add origin "$REPO_URL"
fi

git push -u origin main

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag "$TAG"
  git push origin "$TAG"
fi

echo "Done! Pushed pjsip-ios-sdk to $REPO_URL (tag: $TAG)"
