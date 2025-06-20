#!/usr/bin/env bash
#
# couchbase_health_check.sh
#
# Scans Couchbase *.couch.* files for corruption (per bucket), skips buckets
# whose names begin with '@', and prints the node hostnames of any buckets
# that show corruption.
#
# Variable precedence  (highest → lowest)
#   1. Positional args     ($1 HOST, $2 PORT, $3 USER, $4 PASS)
#   2. Environment vars    (CB_HOST, CB_PORT, CB_USER, CB_PASS)
#   3. Defaults            (localhost, 8091, ---, ---)
#
# Usage examples:
#   export CB_HOST=52.44.152.133 CB_PORT=8091 CB_USER=Admin CB_PASS=redhat
#   ./couchbase_health_check.sh
#
#   ./couchbase_health_check.sh 52.44.152.133 8091 Admin redhat
#
#   export CB_HOST=10.0.0.10; ./couchbase_health_check.sh "" "" Admin redhat
#
# Requirements:
#   curl, jq, Couchbase binaries in /opt/couchbase/bin
#
# Author: <your name>
# Date: 2025‑06‑20

set -euo pipefail
IFS=$'\n\t'

###############################################################################
# 1. Parameter / environment handling
###############################################################################
CB_HOST="${1:-${CB_HOST:-localhost}}"
CB_PORT="${2:-${CB_PORT:-8091}}"
CB_USER="${3:-${CB_USER-}}"
CB_PASS="${4:-${CB_PASS-}}"
CB_PROTO="http"
CB_ENDPOINT="/nodes/self"

if [[ -z "$CB_USER" || -z "$CB_PASS" ]]; then
  cat <<EOF >&2
Error: Couchbase credentials are required.

Provide them either:
  • Positional args 3 and 4   → USER PASS
  • Environment vars          → CB_USER CB_PASS

Usage: $0 [HOST [PORT [USER [PASS]]]]
EOF
  exit 2
fi

###############################################################################
# 2. Binary location
###############################################################################
export COUCH_CHECK_PATH="/opt/couchbase/bin"

###############################################################################
# 3. Discover data & index paths from REST API
###############################################################################
CB_URL="${CB_PROTO}://${CB_HOST}:${CB_PORT}${CB_ENDPOINT}"
JSON_RESPONSE=$(curl -sf -u "${CB_USER}:${CB_PASS}" "${CB_URL}")

DATA_PATH=$(jq -r '.storage.hdd[0].path'        <<<"$JSON_RESPONSE")
INDEX_PATH=$(jq -r '.storage.hdd[0].index_path' <<<"$JSON_RESPONSE")

printf "Discovered paths:\n  Data  : %s\n  Index : %s\n\n" \
       "$DATA_PATH" "$INDEX_PATH"

###############################################################################
# 4. Determine couch_check binary
###############################################################################
SERVER_VERSION_RAW=$(/opt/couchbase/bin/couchbase-server --version)
case "$SERVER_VERSION_RAW" in
  *" 7.2"* ) CHECK_BIN="couch_check72" ;;
  *" 7.6"* ) CHECK_BIN="couch_check76" ;;
  *        ) echo "Unsupported Couchbase version:" >&2
             echo "$SERVER_VERSION_RAW" >&2
             exit 1 ;;
esac
echo "Using checker: $COUCH_CHECK_PATH/$CHECK_BIN"
echo

###############################################################################
# 5. Structures to track corrupted buckets
###############################################################################
declare -A CORRUPTED_BUCKETS

run_checks() {
  local files=("$@")
  [ ${#files[@]} -gt 0 ] || return 0

  local corrupted=0
  for file in "${files[@]}"; do
    if ! "${COUCH_CHECK_PATH}/${CHECK_BIN}" "$file"; then
      corrupted=1
      if [[ $(basename "$file") =~ ^([0-9]+)\.couch\. ]]; then
        echo "Error with vb:${BASH_REMATCH[1]} (file: $file)" >&2
      else
        echo "Error checking file: $file" >&2
      fi
    fi
  done
  (( corrupted )) && CORRUPTED_BUCKETS["$BUCKET_NAME"]=1
}

###############################################################################
# 6. Iterate bucket directories
###############################################################################
for ROOT in "$DATA_PATH" "$INDEX_PATH"; do
  echo "Scanning root: $ROOT"
  for BUCKET_DIR in "$ROOT"/*; do
    [[ -d "$BUCKET_DIR" ]] || continue
    BUCKET_NAME="${BUCKET_DIR##*/}"

    # silently skip system buckets
    [[ "$BUCKET_NAME" == @* ]] && continue

    echo "  Checking bucket: $BUCKET_NAME"
    shopt -s nullglob
    FILE_LIST=("$BUCKET_DIR"/*.couch.*)
    shopt -u nullglob

    run_checks "${FILE_LIST[@]}"
  done
  echo
done

###############################################################################
# 7. Final summary
###############################################################################
if (( ${#CORRUPTED_BUCKETS[@]} > 0 )); then
  echo "====== Corrupted Buckets and Their Node Hosts ======"
  for bucket in "${!CORRUPTED_BUCKETS[@]}"; do
    echo "Bucket: $bucket"
    curl -s -u "${CB_USER}:${CB_PASS}" \
         "${CB_PROTO}://${CB_HOST}:${CB_PORT}/pools/default/buckets/${bucket}/nodes" \
      | jq -r '.servers[].hostname' \
      | cut -d: -f1 \
      | sed 's/^/  • /'
    echo
  done
else
  echo "✅ No corruption found in any bucket."
fi

echo "Done."
