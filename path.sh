#!/usr/bin/env bash
###############################################################################
# Couchbase Info Fetcher (annotated)
# ----------------------------------
# This script connects to a locally‑running Couchbase Server (default
# http://localhost:8091) and collects information about:
#   • The node hostname and storage paths (via the REST API)
#   • The list of buckets (via the REST API)
#   • The set of bucket directories present on disk
#
# It demonstrates two complementary discovery techniques:
#   1. Querying the official REST endpoints (authoritative while the service
#      is up)
#   2. Walking the underlying data directory on the file‑system (useful when
#      the service is down or when you want to inspect raw files).
#
# Prerequisites:
#   * Couchbase Server up and listening on 8091
#   * `curl` for HTTP requests
#   * `jq` for JSON parsing ( https://stedolan.github.io/jq/ )
#
# Usage:
#   chmod +x couchbase_info_explained.sh
#   ./couchbase_info_explained.sh
###############################################################################

## ---------------------------------------------------------------------------
## 1) Configuration
## ---------------------------------------------------------------------------
# Administrator credentials – adjust if you use a different account.
CB_USERNAME="Admin"
CB_PASSWORD="redhat"

# Root REST URL for the local node
CB_HOST="http://localhost:8091"

# On‑disk data directory laid down by Couchbase; modify if you changed the
# installation path or used cbbackupmgr‑style restores.
CB_DATA_DIR="/opt/couchbase/var/lib/couchbase/data"

## ---------------------------------------------------------------------------
## 2) Helper functions
## ---------------------------------------------------------------------------

# die <msg>
# ----
# Print an error message to stderr and quit with a non‑zero status.
die () { echo "ERROR: $*" >&2; exit 1; }

# rest_get <endpoint>
# ----
# Convenience wrapper around curl for authenticated GET requests so the main
# script reads more clearly.
rest_get () {
  local endpoint="$1"
  curl -s -u "$CB_USERNAME:$CB_PASSWORD" "$CB_HOST$endpoint"
}

## ---------------------------------------------------------------------------
## 3) Gather info over the REST API
## ---------------------------------------------------------------------------

# `/nodes/self` gives node‑specific details such as host name and storage.
node_json=$(rest_get /nodes/self) || die "Cannot reach Couchbase REST API."

hostname=$(echo "$node_json" | jq -r '.hostname')
storage_json=$(echo "$node_json"  | jq '.storage')

# `/pools/default` offers cluster‑wide information including bucket names.
buckets_json=$(rest_get /pools/default)
rest_bucket_names=$(echo "$buckets_json" | jq -r '.bucketNames[]')

## ---------------------------------------------------------------------------
## 4) Output section
## ---------------------------------------------------------------------------

echo "==== Couchbase node: $hostname ===="
echo
echo "---- Storage configuration (as reported by REST) ----"
echo "$storage_json" | jq .
echo
echo "---- Buckets (via REST) ----"
printf '%s\n' $rest_bucket_names
echo

## ---------------------------------------------------------------------------
## 5) Optional: validate buckets by walking the data directory
## ---------------------------------------------------------------------------

echo "---- Buckets (detected on‑disk under $CB_DATA_DIR) ----"
if [[ -d "$CB_DATA_DIR" ]]; then
  # Iterate over immediate sub‑directories; ignore Couchbase metadata dirs
  for dir in "$CB_DATA_DIR"/*/ ; do
    bucket="${dir%/}"
    bucket="${bucket##*/}"       # trim parent path

    # Skip any directory whose name begins with '@' (Couchbase uses such dirs
    # for internal metadata like @attachments or @index).
    [[ $bucket == @* ]] && continue

    printf '%s\n' "$bucket"
  done
else
  echo "Directory $CB_DATA_DIR does not exist on this host."
fi
