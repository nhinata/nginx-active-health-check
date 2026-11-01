#!/usr/bin/env bash
# Reports whether the bundled module and the pinned nginx version are behind upstream.
# Exits 1 when an update is available, and 2 when the check itself fails.
# Requires the gh CLI.
set -euo pipefail

cd "$(dirname "$0")/.."

# Keep in sync with the commit linked from README.md
MODULE_COMMIT=${MODULE_COMMIT:-02c6c9de14ca1e60adb9f48179707c57d532d622}
NGINX_VERSION=${NGINX_VERSION:-$(sed -n 's/^ARG NGINX_VERSION=//p' docker/nginx/Dockerfile)}

fail() {
  echo "error: $1" >&2
  exit 2
}

latest_commit=$(gh api repos/yaoweibin/nginx_upstream_check_module/commits/HEAD --jq .sha) ||
  fail "could not get the latest module commit"
# nginx stable releases have an even minor version
latest_nginx=$(gh api 'repos/nginx/nginx/releases?per_page=50' --jq '.[].tag_name' |
  sed -n 's/^release-//p' | awk -F. '$2 % 2 == 0' | sort -V | tail -n 1) ||
  fail "could not get the latest nginx release"
[ -n "$latest_commit" ] || fail "empty module commit"
[ -n "$latest_nginx" ] || fail "no stable nginx release found"

outdated=0

if [ "$latest_commit" = "$MODULE_COMMIT" ]; then
  echo "nginx_upstream_check_module: up to date (${MODULE_COMMIT:0:7})"
else
  echo "nginx_upstream_check_module: ${MODULE_COMMIT:0:7} -> ${latest_commit:0:7}"
  echo "  https://github.com/yaoweibin/nginx_upstream_check_module/compare/${MODULE_COMMIT}...${latest_commit}"
  outdated=1
fi

if [ "$latest_nginx" = "$NGINX_VERSION" ]; then
  echo "nginx stable: up to date ($NGINX_VERSION)"
else
  echo "nginx stable: $NGINX_VERSION -> $latest_nginx"
  echo "  https://nginx.org/en/CHANGES-${latest_nginx%.*}"
  outdated=1
fi

exit "$outdated"
