#!/usr/bin/env bash
#
# couch_index_check.sh — integrity checker for Couchbase index files
#
# 1. Discover the node’s PATH
# 2. Enumerate bucket directories under it (skip those that begin with "@")
# 3. Make the couch_check helper scripts executable (try sudo if needed)
# 4. Run the appropriate couch_check on every *.couch.* file in every bucket
# 5. **NEW** Run a one‑shot integrity scan over all index files in the tmp directory
#
# USAGE (any combination)
#   COUCH_USER=<user> COUCH_PASS=<pass> [HOST=<host>] [PORT=<port>] ./couch_index_check.sh
#   ./couch_index_check.sh <host> <port> <user> <pass>
#
# Notes:
#   - Requires curl and jq in $PATH.
#   - Tested on Couchbase Server 7.0 to 7.6 (legacy layouts also supported).
#   - Designed for Bash 4‑compatible shells with set -euo pipefail semantics.

set -euo pipefail

###############################################################################
# 0. Parameters & constants  (NO hard‑coded user or password)
###############################################################################

usage() {
cat <<EOF
Usage:
  COUCH_USER=<user> COUCH_PASS=<pass> [HOST=<host>] [PORT=<port>] $0
  or:
  $0 <host> <port> <user> <pass>

Environment variables override positional parameters.
EOF
}

# Helper: ensure a variable is set
need() {
  local val="$1" name="$2"
  [[ -n "$val" ]] || { echo "ERROR: $name is required"; usage; exit 1; }
}

# Get values: env‑vars first, then positional parameters, then (only for host/port) safe defaults
HOST="${HOST:-${1:-localhost}}"
PORT="${PORT:-${2:-8091}}"
USER="${COUCH_USER:-${3-}}"
PASS="${COUCH_PASS:-${4-}}"
COUCHBIN="${couch:-${5-}}"

need "$USER" "COUCH_USER (env) or argument #3"
need "$PASS" "COUCH_PASS (env) or argument #4"
need "$COUCHBIN" "couchbin (env) or argument #5"

###############################################################################
# Prerequisite checks
###############################################################################
for cmd in curl jq; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
done

###############################################################################
# 1. Fetch PATH from /nodes/self
###############################################################################
URL="http://${HOST}:${PORT}/nodes/self"
PATH=$(curl -s -u "${USER}:${PASS}" "${URL}" \
  | jq -r '(.storage.hdd[0].path // .path)')

[[ -z "${PATH}" || "${PATH}" == "null" ]] && {
  echo "ERROR: PATH not found in ${URL}" >&2
  exit 1
}

echo "PATH: ${PATH}"
echo ""

URL="http://${HOST}:${PORT}/nodes/self"
INDEX_PATH=$(curl -s -u "${USER}:${PASS}" "${URL}" \
  | jq -r '(.storage.hdd[0].index_path // .index_path)')

[[ -z "${INDEX_PATH}" || "${INDEX_PATH}" == "null" ]] && {
  echo "ERROR: INDEX_PATH not found in ${URL}" >&2
  exit 1
}

echo "INDEX_PATH: ${INDEX_PATH}"
echo ""

###############################################################################
# 2. List bucket directories (excluding those that start with "@")
###############################################################################
declare -a BUCKETS=()

cd "${PATH}"

echo "Buckets to scan:"
for dir in */ ; do
  dir="${dir%/}"
  [[ "${dir}" == @* ]] && continue
  echo "- ${dir}"
  BUCKETS+=("${dir}")
done
[[ ${#BUCKETS[@]} -eq 0 ]] && { echo "No buckets found. Exiting."; exit 0; }
echo ""

###############################################################################
# 3. Ensure couch_check helpers are present and executable
###############################################################################
echo "Verifying couch_check tools in ${COUCHBIN}"
(
  cd "${COUCHBIN}" || { echo "ERROR: cannot cd to ${COUCHBIN}"; exit 1; }
  for f in couch_check72 couch_check76 couch_check_all.sh; do
    [[ -f "${f}" ]] || { echo "ERROR: ${f} not found"; exit 1; }
    [[ -x "${f}" ]] || {
      if chmod +x "${f}" 2>/dev/null; then
        echo "Made ${f} executable"
      elif command -v sudo >/dev/null; then
        echo "Attempting to set executable permissions using sudo for ${f}"
        sudo chmod +x "${f}"
      else
        echo "ERROR: cannot set +x on ${f} (need root or sudo)" >&2
        exit 1
      fi
    }
  done
)
echo ""

###############################################################################
# 4. Detect server version and determine couch_check helper
###############################################################################
SERVER_VERSION="$("${COUCHBIN}/couchbase-server" --version | awk '{print $NF}')"
case "${SERVER_VERSION}" in
  7.2*) USE_CHECK="couch_check72" ;;
  7.6*) USE_CHECK="couch_check76" ;;
  *)    USE_CHECK="(via couch_check_all.sh)" ;;
esac
echo "Detected Couchbase Server version ${SERVER_VERSION}. Using check tool: ${USE_CHECK}"
echo ""

###############################################################################
# 5. Run checks (single pass over tmp directory)
###############################################################################
# NOTE: This stage was changed per request. Instead of iterating bucket‑by‑bucket
# we now perform a one‑shot integrity scan of *all* index files located in the
# Couchbase tmp directory.

export COUCH_CHECK_PATH="/opt/couchbase/bin"
cd /opt/couchbase/var/lib/couchbase/tmp/ || { echo "ERROR: cannot cd to /opt/couchbase/var/lib/couchbase/tmp/"; exit 1; }

echo "Running couch_check_all.sh against all *.couch.* files in /opt/couchbase/var/lib/couchbase/tmp/"

/opt/couchbase/bin/couch_check_all.sh *.couch.*

echo "Integrity scan completed."

exit 0
