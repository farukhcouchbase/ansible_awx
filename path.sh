#!/usr/bin/env bash
#
# get_index_path.sh
#
# 1. Fetch Couchbase node’s index_path
# 2. List buckets (directories inside index_path that do NOT start with "@")
# 3. Make couch_check helper scripts executable, export COUCH_CHECK_PATH
# 4. Execute couch_check_all.sh on each bucket’s *.couch.* files
#
# USAGE
#   ./get_index_path.sh [HOST] [PORT] [USER] [PASS]
#
# DEFAULTS
#   HOST: localhost
#   PORT: 8091
#   USER: Admin
#   PASS: redhat
#
# EXAMPLE
#   ./get_index_path.sh 52.44.152.133 8091 Admin redhat
#

set -euo pipefail

HOST="${1:-localhost}"
PORT="${2:-8091}"
USER="${3:-Admin}"
PASS="${4:-redhat}"

URL="http://${HOST}:${PORT}/nodes/self"

# --------------------------------------------------------------------------- #
# 1. Fetch the index_path (handles both modern & legacy Couchbase JSON layouts)
# --------------------------------------------------------------------------- #
INDEX_PATH=$(
  curl -s -u "${USER}:${PASS}" "${URL}" |
  jq -r '(.storage.hdd[0].index_path // .index_path)'
)

if [[ -z "${INDEX_PATH}" || "${INDEX_PATH}" == "null" ]]; then
  echo "ERROR: index_path not found in ${URL}" >&2
  exit 1
fi

echo "###### INDEX PATH ######"
echo "${INDEX_PATH}"
echo ""

# --------------------------------------------------------------------------- #
# 2. List buckets (sub‑directories) under the index_path, skipping "@*"
#    Store them in an array for later processing
# --------------------------------------------------------------------------- #
declare -a BUCKETS=()

if ! cd "${INDEX_PATH}"; then
  echo "ERROR: Cannot cd to ${INDEX_PATH}" >&2
  exit 1
fi

echo "##### List of the Buckets ######"
for dir in */ ; do
  dir="${dir%/}"        # remove trailing slash
  [[ "${dir}" == @* ]] && continue
  echo "${dir}"
  BUCKETS+=("${dir}")
done
echo ""

# --------------------------------------------------------------------------- #
# 3. Ensure couch_check helper scripts are executable & set environment var
# --------------------------------------------------------------------------- #
COUCHBIN="/opt/couchbase/bin"

if cd "${COUCHBIN}" 2>/dev/null; then
  echo "##### Setting permissions for couch_check helpers in ${COUCHBIN} #####"
  for f in couch_check72 couch_check76 couch_check_all.sh; do
    [[ -f "${f}" ]] || { echo "WARNING: ${f} not found" >&2; continue; }
    sudo chmod +x "${f}" 2>/dev/null || true
    echo "Made ${f} executable"
  done
  export COUCH_CHECK_PATH="${COUCHBIN}"
  echo "Exported COUCH_CHECK_PATH=${COUCH_CHECK_PATH}"
else
  echo "WARNING: ${COUCHBIN} not found; skipping couch_check permission steps" >&2
  exit 1
fi
echo ""

# --------------------------------------------------------------------------- #
# 4. Execute couch_check_all.sh over each bucket’s *.couch.* files
# --------------------------------------------------------------------------- #
if [[ -x "${COUCHBIN}/couch_check_all.sh" ]]; then
  echo "##### Running couch_check_all.sh for each bucket #####"
  for dir in "${BUCKETS[@]}"; do
    TARGET_PATH="${INDEX_PATH}/${dir}/*.couch.*"
    echo "→ ${dir}: ${TARGET_PATH}"
    "${COUCHBIN}/couch_check_all.sh" ${TARGET_PATH}
  done
else
  echo "ERROR: couch_check_all.sh not executable — skipping checks" >&2
fi
