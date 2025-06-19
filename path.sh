#!/usr/bin/env bash
#
# couch_index_check.sh — integrity checker for Couchbase index files
#
# 1. Discover the node’s PATH
# 2. Enumerate bucket directories under it (skip those that begin with "@")
# 3. Make the couch_check helper scripts executable (try sudo if needed)
# 4. Run the appropriate couch_check on every *.couch.* file in every bucket
# 5. Flag any corruption and list the nodes that hold the affected bucket
#
# USAGE (any combination)
#   COUCH_USER=<user> COUCH_PASS=<pass> [HOST=<host>] [PORT=<port>] ./couch_index_check.sh
#   ./couch_index_check.sh <host> <port> <user> <pass>
#
# Notes:
#   - Requires curl and jq in $PATH.
#   - Tested on Couchbase Server 7.0 to 7.6 (legacy layouts also supported).
#   - Designed for Bash 4‑compatible shells with set -euo pipefail semantics.

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
need "$couch" "couchbin (env) or argument #4"


export COUCH_CHECK_PATH="$COUCHBIN"   # couch_check_all.sh relies on this

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
# 5. Run checks and analyze results
###############################################################################
shopt -s nullglob

for bucket in "${BUCKETS[@]}"; do
  bucket_path="${PATH}/${bucket}"
  files=( "${bucket_path}"/*.couch.* )

  if (( ${#files[@]} == 0 )); then
    echo "No *.couch.* files found in bucket: ${bucket}"
    echo ""
    continue
  fi

  echo "Checking bucket: ${bucket}"

  set +e
  output=$(cd "${COUCHBIN}" && ./couch_check_all.sh "${files[@]}" 2>&1)
  exit_code=$?
  set -e

  echo "${output}"

  if (( exit_code != 0 )) || echo "${output}" | grep -qE 'Error checking file:|Error with vb:'; then
    echo "Corruption detected in bucket '${bucket}'"
    echo "Retrieving node hostnames for bucket '${bucket}'"

    node_json=$(curl -s -u "${USER}:${PASS}" \
      "http://${HOST}:${PORT}/pools/default/buckets/${bucket}/nodes")

    hostnames=$(echo "${node_json}" \
      | jq -r '.nodes[]?.hostname // .servers[]?.hostname')

    if [[ -n "${hostnames}" ]]; then
      echo "Bucket '${bucket}' resides on the following nodes:"
      echo "${hostnames}" | sed 's/^/  - /'
    else
      echo "Unable to parse hostnames from API response."
    fi
  else
    echo "Bucket '${bucket}' passed integrity checks."
  fi

  echo ""
done

echo "All buckets processed. Script completed successfully."

exit 0
