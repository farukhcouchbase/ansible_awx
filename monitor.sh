#!/usr/bin/env bash

# === SCRIPT 1: Check for bucket write failures (cluster-wide) ===

CB_USERNAME=${CB_USERNAME:='Administrator'}
CB_PASSWORD=${CB_PASSWORD:='password'}
CLUSTER=${CLUSTER:='localhost'}
PORT=${PORT:='8091'}
PROTOCOL=${PROTOCOL:='http'}

explicit_port=false
explicit_protocol=false

# Parse CLI arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --username=*) CB_USERNAME="${1#*=}" ;;
    --password=*) CB_PASSWORD="${1#*=}" ;;
    --cluster=*)  CLUSTER="${1#*=}" ;;
    --port=*)     PORT="${1#*=}"; explicit_port=true ;;
    --protocol=*) PROTOCOL="${1#*=}"; explicit_protocol=true ;;
    *) echo "* Error: Invalid argument."; exit 1 ;;
  esac
  shift
done

# Protocol/Port fallback logic
if [ "$explicit_port" = true ] && [ "$PORT" = "18091" ] && [ "$explicit_protocol" = false ]; then
  PROTOCOL="https"
elif [ "$explicit_protocol" = true ] && [ "$PROTOCOL" = "https" ] && [ "$explicit_port" = false ]; then
  PORT="18091"
fi

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
  echo >&2 "❗ 'jq' is required. Install: https://stedolan.github.io/jq/"
  exit 1
fi

# Get cluster and bucket info
RESPONSE=$(curl -k --user "$CB_USERNAME:$CB_PASSWORD" --silent --request GET "$PROTOCOL://$CLUSTER:$PORT/pools/default")
CLUSTER_NAME=$(echo "$RESPONSE" | jq -r '.clusterName')

# Flag for any failure detected
failure_detected=false

# Process each bucket
echo "----------------------------------------------"
echo "🔍 Checking Write Failures (Cluster: $CLUSTER_NAME)"
echo "----------------------------------------------"
echo "$RESPONSE" | jq -r '.bucketNames[].bucketName' | while read -r bucket; do
  STATS=$(curl -k --user "$CB_USERNAME:$CB_PASSWORD" --silent --request GET "$PROTOCOL://$CLUSTER:$PORT/pools/default/buckets/$bucket/stats")
  write_failed_values=($(echo "$STATS" | jq -r '.op.samples.ep_data_write_failed[]'))

  has_failure=0
  for val in "${write_failed_values[@]}"; do
    if [[ "$val" -ne 0 ]]; then
      has_failure=1
      break
    fi
  done

  if [[ "$has_failure" -eq 1 ]]; then
    echo "❌ ERROR: Bucket '$CLUSTER_NAME::$bucket' has detected write failures!"
    failure_detected=true
  else
    echo "✅ OK: Bucket '$CLUSTER_NAME::$bucket' has no write failures."
  fi
done

# === CONDITIONAL EXECUTION OF SCRIPT 2 ===
# If failure_detected is true, run deeper node diagnostics
if $failure_detected; then
  echo
  echo "----------------------------------------------"
  echo "⚠️ Write failures detected - Running extended diagnostics..."
  echo "----------------------------------------------"

  # Re-use existing CB_USERNAME, CB_PASSWORD, CLUSTER, PORT, PROTOCOL

  CLUSTER_INFO=$(curl -k -s --user "$CB_USERNAME:$CB_PASSWORD" "$PROTOCOL://$CLUSTER:$PORT/pools/default")
  CLUSTER_NAME=$(echo "$CLUSTER_INFO" | jq -r '.clusterName')
  BUCKET_NAMES=$(echo "$CLUSTER_INFO" | jq -r '.bucketNames[].bucketName')
  NODES=$(echo "$CLUSTER_INFO" | jq -r '.nodes[].hostname')

  echo "----------------------------------------------"
  echo "🔍 Checking Bucket Read/Write Errors (Cluster-wide)"
  echo "----------------------------------------------"

  for BUCKET in $BUCKET_NAMES; do
    STATS=$(curl -k -s --user "$CB_USERNAME:$CB_PASSWORD" "$PROTOCOL://$CLUSTER:$PORT/pools/default/buckets/$BUCKET/stats")

    read_failed=($(echo "$STATS" | jq -r '.op.samples.ep_data_read_failed[]?'))
    write_failed=($(echo "$STATS" | jq -r '.op.samples.ep_data_write_failed[]?'))

    total_read_failed=0
    total_write_failed=0

    for val in "${read_failed[@]}"; do
      total_read_failed=$((total_read_failed + val))
    done
    for val in "${write_failed[@]}"; do
      total_write_failed=$((total_write_failed + val))
    done

    echo "📦 Bucket: '$CLUSTER_NAME::$BUCKET'"
    echo "   - ep_data_read_failed  = $total_read_failed"
    echo "   - ep_data_write_failed = $total_write_failed"
    if [[ $total_read_failed -eq 0 && $total_write_failed -eq 0 ]]; then
      echo "   ✅ Status: OK"
    else
      echo "   ❌ Status: ERROR - Failures detected"
    fi

    echo "   🔍 Per-node failures:"
    for NODE in $NODES; do
      NODE_STATS=$(curl -k -s --user "$CB_USERNAME:$CB_PASSWORD" "$PROTOCOL://$CLUSTER:$PORT/pools/default/buckets/$BUCKET/nodes/$NODE/stats")
      node_read=$(echo "$NODE_STATS" | jq -r '.op.samples.ep_data_read_failed[-1] // 0')
      node_write=$(echo "$NODE_STATS" | jq -r '.op.samples.ep_data_write_failed[-1] // 0')
      echo "     - Node $NODE: read=$node_read, write=$node_write"
    done
    echo
  done

  echo "----------------------------------------------"
  echo "📊 Node Resource Utilization"
  echo "----------------------------------------------"

  NODES_DATA=$(echo "$CLUSTER_INFO" | jq '.nodes')
  NODE_COUNT=$(echo "$NODES_DATA" | jq 'length')

  for i in $(seq 0 $((NODE_COUNT - 1))); do
    NODE=$(echo "$NODES_DATA" | jq ".[$i]")
    HOSTNAME=$(echo "$NODE" | jq -r '.hostname')
    CPU=$(echo "$NODE" | jq -r '.systemStats.cpu_utilization_rate // 0')
    MEM_USED=$(echo "$NODE" | jq -r '.systemStats.mem_used // 0')
    MEM_TOTAL=$(echo "$NODE" | jq -r '.systemStats.mem_total // 0')
    DISK_USED=$(echo "$NODE" | jq -r '.systemStats.disk_used // 0')
    DISK_TOTAL=$(echo "$NODE" | jq -r '.systemStats.disk_total // 0')

    if [[ $MEM_TOTAL -gt 0 ]]; then
      MEM_PCT=$(awk "BEGIN {printf \"%.1f\", ($MEM_USED/$MEM_TOTAL)*100}")
    else
      MEM_PCT="Unavailable"
    fi

    if [[ $DISK_TOTAL -gt 0 ]]; then
      DISK_PCT=$(awk "BEGIN {printf \"%.1f\", ($DISK_USED/$DISK_TOTAL)*100}")
    else
      DISK_PCT="Unavailable"
    fi

    echo "🖥️ Node: $HOSTNAME"
    echo "   CPU Utilization : $CPU%"
    echo "   RAM Usage       : $MEM_PCT% ($MEM_USED / $MEM_TOTAL bytes)"
    echo "   Disk Usage      : $DISK_PCT% ($DISK_USED / $DISK_TOTAL bytes)"
    echo ""
  done

  echo "----------------------------------------------"
  echo "✅ Complete: Cluster and node-level stats reported."
  echo "----------------------------------------------"
else
  echo
  echo "✅ No write failures detected. Skipping extended diagnostics."
fi
