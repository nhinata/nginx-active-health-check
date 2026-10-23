#!/usr/bin/env bash
# Starts the demo, then checks that a stopped / paused backend is marked down,
# receives no traffic, and comes back up.
set -euo pipefail

cd "$(dirname "$0")/.."

STATUS_URL="http://localhost:8080/status?format=csv"
TIMEOUT=${TIMEOUT:-60}

status_of() {
    # $1: row number (1-5) -> up / down
    curl -fsS "$STATUS_URL" | sed -n "${1}p" | cut -d, -f4
}

wait_for() {
    # $1: description, $2...: command that must succeed
    local desc=$1; shift
    local start=$SECONDS
    until "$@" >/dev/null 2>&1; do
        if (( SECONDS - start > TIMEOUT )); then
            echo "FAIL: $desc (timed out after ${TIMEOUT}s)"
            docker compose logs nginx | tail -20
            exit 1
        fi
        sleep 1
    done
    echo "ok: $desc ($(( SECONDS - start ))s)"
}

check() {
    # $1: description, $2...: command that must succeed on the first try
    local desc=$1; shift
    if ! "$@"; then
        echo "FAIL: $desc"
        docker compose logs nginx | tail -20
        exit 1
    fi
    echo "ok: $desc"
}

all_up() {
    [ "$(curl -fsS "$STATUS_URL" | grep -c ',up,')" -eq 5 ]
}

row_is() {
    [ "$(status_of "$1")" = "$2" ]
}

no_traffic_to() {
    # $1: backend name; all requests must succeed and none may reach it
    local i body
    for i in $(seq 30); do
        body=$(curl -fsS http://localhost/) || return 1
        [ "$body" != "$1" ] || return 1
    done
}

trap 'docker compose down >/dev/null 2>&1' EXIT

docker compose up -d --build

wait_for "all backends up" all_up
wait_for "status page not exposed on port 80" \
    sh -c '[ "$(curl -s -o /dev/null -w "%{http_code}" http://localhost/status)" = 404 ]'

docker compose stop backend03
wait_for "stopped backend03 marked down" row_is 3 down
check "no traffic to backend03 while down" no_traffic_to backend03
docker compose start backend03
wait_for "backend03 back up" row_is 3 up

docker compose pause backend04
wait_for "paused backend04 marked down" row_is 4 down
check "no traffic to backend04 while down" no_traffic_to backend04
docker compose unpause backend04
wait_for "backend04 back up" row_is 4 up

echo "All checks passed"
