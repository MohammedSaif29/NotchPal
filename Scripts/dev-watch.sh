#!/bin/bash
# NotchPal, the notch that's alive.
# Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
# SPDX-License-Identifier: GPL-3.0-only
# Developer mode: rebuilds and relaunches NotchPal every time the ".rebuild" file changes,
# and writes the full output to build.log. Press Ctrl+C to stop.
cd "$(dirname "$0")/.."

touch .rebuild
last=""
echo "NotchPal dev mode: watching for code changes. Press Ctrl+C to stop."
while true; do
    stamp="$(stat -f %m .rebuild 2>/dev/null || echo 0)"
    if [[ "$stamp" != "$last" ]]; then
        last="$stamp"
        echo "=== Build started $(date '+%H:%M:%S') ===" | tee build.log
        if bash Scripts/build-app.sh --run >> build.log 2>&1; then
            echo "BUILD OK $(date '+%H:%M:%S')" | tee -a build.log
        else
            echo "BUILD FAILED $(date '+%H:%M:%S') (details in build.log)" | tee -a build.log
        fi
    fi
    sleep 2
done
