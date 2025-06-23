#!/usr/bin/env bash
#
# couchbase_health_check.sh
#
# Scans Couchbase *.couch.* files on the **local** node for corruption.
#
# Environment variables (set via AWX survey or export):
#   CB_USER  : Admin username (default: Admin)
#   CB_PASS  : Admin password (default: redhat)
#
# CLI flags (optional):
#   --data   : Scan only DATA_PATH (KV files)
#   --index  : Scan only INDEX_PATH (index/FTS checkpoint files)
#   --both   : Scan both paths (default)
#
# Author : <your name>
# Updated: 2025-06-23

set -euo pipefail
IFS=$'\n\t'

###############################################################################
# 0. Option parsing ───────────────────────────────────────────────────────────
###############################################################################
usage() {
  cat <<EOF
Usage: $(basename "$0") [--data | --index | --both]

  --data     Scan only the KV data directory (DATA_PATH)
  --index    Scan only the index directory (INDEX_PATH)
  --both     Scan both directories (default)

Only two environment variables are respected:
  CB_USER  : Couchbase admin user   (default Admin)
  CB_PASS  : Couchbase admin passwd (default redhat)
EOF
  exit 1
}

SCAN_TARGET="both"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --data)   SCAN_TARGET="data"  ;;
    --index)  SCAN_TARGET="index" ;;
    --both)   SCAN_TARGET="both"  ;;
    -h|--help) usage ;;
    *) echo "Unknown flag: $1" >&2; usage ;;
  esac
  shift
done

###############################################################################
# 1. Fixed configuration (only user/pass are overridable)
###############################################################################
CB_USER="${CB_USER:-Admin}"
CB_PASS="${CB_PASS:-redhat}"
CB_HOST="127.0.0.1"       # always localhost
CB_PORT="8091"
CB_ENDPOINT="/nodes/self"
CB_PROTO="http"

# Location of couch_checkXX binaries
export COUCH_CHECK_PATH="/opt/couchbase/bin"

###############################################################################
# 2. Discover data & index paths from REST API
###############################################################################
CB_URL="${CB_PROTO}://${CB_HOST}:${CB_PORT}${CB_ENDPOINT}"
JSON_RESPONSE=$(curl -s -u "${CB_USER}:${CB_PASS}" "${CB_URL}")

DATA_PATH=$(jq -r '.storage.hdd[0].path'        <<<"$JSON_RESPONSE")
INDEX_PATH=$(jq -r '.storage.hdd[0].index_path' <<<"$JSON_RESPONSE")

printf "Discovered paths:\n  Data  : %s\n  Index : %s\n\n" \
       "$DATA_PATH" "$INDEX_PATH"

###############################################################################
# 3. Select the correct couch_check binary
###############################################################################
SERVER_VERSION_RAW=$(/opt/couchbase/bin/couchbase-server --version)
CHECK_BIN=""

if   echo "$SERVER_VERSION_RAW" | grep -qE " 7\.2"; then
  CHECK_BIN="couch_check72"
elif echo "$SERVER_VERSION_RAW" | grep -qE " 7\.6"; then
  CHECK_BIN="couch_check76"
else
  echo "Unsupported Couchbase version detected:" >&2
  echo "$SERVER_VERSION_RAW" >&2
  exit 1
fi

printf "Using checker binary: %s/%s\n\n" "$COUCH_CHECK_PATH" "$CHECK_BIN"

###############################################################################
# 4. Helper to run couch_check and capture errors
###############################################################################
run_checks() {
  local error_found=0
  for file in "$@"; do
    if ! "${COUCH_CHECK_PATH}/${CHECK_BIN}" "$file"; then
      error_found=1
      if [[ $(basename "$file") =~ ^([0-9]+)\.couch\. ]]; then
        echo "Error with vb:${BASH_REMATCH[1]} (file: $file)" >&2
      else
        echo "Error checking file: $file" >&2
      fi
    fi
  done
  return $error_found
}

###############################################################################
# 5. Build the list of roots to scan
###############################################################################
ROOTS=()
case "$SCAN_TARGET" in
  data)  ROOTS+=("$DATA_PATH") ;;
  index) ROOTS+=("$INDEX_PATH") ;;
  both)  ROOTS+=("$DATA_PATH" "$INDEX_PATH") ;;
  *)     echo "Invalid scan target: $SCAN_TARGET" >&2; exit 1 ;;
esac

# Remove duplicates in case both paths are identical
ROOTS=($(printf "%s\n" "${ROOTS[@]}" | awk '!seen[$0]++'))

###############################################################################
# 6. Print summary and scan
###############################################################################
case "$SCAN_TARGET" in
  data)  echo "▶ Scanning the vBuckets of **Data Service** (DATA_PATH)" ;;
  index) echo "▶ Scanning the vBuckets of **Index Service** (INDEX_PATH)" ;;
  both)  echo "▶ Scanning the vBuckets of both **Data** and **Index Services**" ;;
esac
echo

last_corrupt_bucket=""

for ROOT in "${ROOTS[@]}"; do
  echo "Scanning root: $ROOT"
  for BUCKET_DIR in "$ROOT"/*; do
    [ -d "$BUCKET_DIR" ] || continue
    BUCKET_NAME="${BUCKET_DIR##*/}"

    # Skip system buckets
    if [[ "$BUCKET_NAME" == @* ]]; then
      echo "  Skipping system bucket: $BUCKET_NAME"
      continue
    fi

    echo "  Checking bucket: $BUCKET_NAME"

    shopt -s nullglob
    FILE_LIST=("$BUCKET_DIR"/*.couch.*)
    shopt -u nullglob

    if run_checks "${FILE_LIST[@]}"; then
      echo "  ✔ No issues detected in bucket: $BUCKET_NAME"
    else
      last_corrupt_bucket="$BUCKET_NAME"
      echo "  ✖ Corruption detected in bucket: $BUCKET_NAME" >&2
    fi
  done
  echo
done

###############################################################################
# 7. Placeholder for future node-lookup logic
###############################################################################
# TODO: Use REST API to fetch node info for \$last_corrupt_bucket if required.
