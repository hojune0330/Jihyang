#!/bin/bash
# 사용: tool/shot.sh <출력.png> [url]  — 390x844 세로 폰 화면 캡처
OUT=$1; URL=${2:-http://localhost:5060/}
timeout 90 google-chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage \
  --explicitly-allowed-ports=5060,5061 --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=390,844 --virtual-time-budget=${BUDGET:-20000} --screenshot="$OUT" "$URL" >/dev/null 2>&1
ls -la "$OUT"
