#!/usr/bin/env bash
# 把 index.html 上傳到 VM(ssh 別名 focus)的 ~/caddy/motion-trace/,Caddy 立刻就會提供新版,不需要 reload。
# 站台設定在 Caddy repo 的 sites/motion-trace.caddy(網域 motion-trace.duckdns.org)。
set -euo pipefail
cd "$(dirname "$0")"
HOST="${HOST:-focus}"
ssh "$HOST" 'mkdir -p ~/caddy/motion-trace'
scp -q index.html "$HOST":~/caddy/motion-trace/index.html
echo "OK: https://motion-trace.duckdns.org/ ($(md5 -q index.html 2>/dev/null || md5sum index.html | cut -d' ' -f1))"
