#!/bin/bash

LOG_DIR="/opt/couchbase/var/lib/couchbase/logs"
NODE_NAME=$(hostname)
WEBHOOK_URL="https://outlook.office.com/webhook/your-webhook-url-here"  # 🔁 Replace with your real webhook URL

#KEYWORDS="vbucket.*corrupt|corrupt.*vbucket|vbucket.*fail|vbucket.*error|corruption detected|failed to open vbucket|cannot read vbucket|vbucket.*not valid"

KEYWORDS="vbucket.malformed" 

echo "🔎 Scanning for vbucket corruption logs in memcached logs on node: $NODE_NAME"
echo "==========================================================================="

FOUND=0

send_teams_alert() {
    local vb_id="$1"
    local node="$2"
    local log_line="$3"
    local logfile="$4"

    PAYLOAD=$(cat <<EOF
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "summary": "⚠️ VBucket Corruption Alert",
    "themeColor": "FF0000",
    "title": "🚨 Corrupted VBucket Detected",
    "sections": [{
        "facts": [
            { "name": "Node", "value": "$node" },
            { "name": "VBucket ID", "value": "$vb_id" },
            { "name": "Log File", "value": "$logfile" },
            { "name": "Log Entry", "value": "$log_line" }
        ],
        "markdown": true
    }]
}
EOF
    )

    curl -s -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL" > /dev/null
}

for LOG in "$LOG_DIR"/memcached.log*; do
    [[ ! -e "$LOG" ]] && continue

    if [[ $LOG == *.gz ]]; then
        MATCHES=$(sudo zgrep -iE "$KEYWORDS" "$LOG")
    else
        MATCHES=$(sudo grep -iE "$KEYWORDS" "$LOG")
    fi

    if [[ -n "$MATCHES" ]]; then
        echo "✅ Matches found in $LOG"
        echo "------------------------------------------------------------------------"

        while IFS= read -r line; do
            VB_ID=$(echo "$line" | grep -oE 'vbucket[[:space:]#:-]*[0-9]+' | grep -oE '[0-9]+')
            NODE_IN_LOG=$(echo "$line" | grep -oE 'node-[0-9a-zA-Z._-]+')
            NODE="${NODE_IN_LOG:-$NODE_NAME}"

            echo "⚠️  Corruption Detected!"
            echo "Log File   : $LOG"
            echo "Node       : $NODE"
            echo "VBucket ID : ${VB_ID:-Unknown}"
            echo "Log Line   : $line"
            echo "------------------------------------------------------------------------"

            # Send Teams alert
            send_teams_alert "${VB_ID:-Unknown}" "$NODE" "$line" "$LOG"
            FOUND=1
        done <<< "$MATCHES"
    fi
done

[[ $FOUND -eq 0 ]] && echo "✅ No corruption logs found in memcached logs."

echo "✅ Search completed."
