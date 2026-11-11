#!/bin/bash
# 실기 웹 렌더 캡처: tool/shots/shoot.sh <phase> <out.png> [paused=true]
set -e
cd /home/user/flutter_app
P=$1; OUT=$2; PAUSED=${3:-true}
flutter build web --release -t tool/shots/running_shot.dart --dart-define=PHASE=$P --dart-define=PAUSED=$PAUSED -o build/web_shot >/dev/null 2>&1
(lsof -ti:5061 | xargs -r kill -9) 2>/dev/null || true; sleep 0.5
cd build/web_shot && setsid -f python3 -m http.server 5061 --bind 0.0.0.0 >/dev/null 2>&1 < /dev/null
sleep 1; cd /home/user/flutter_app && tool/shot.sh "$OUT" http://localhost:5061/
