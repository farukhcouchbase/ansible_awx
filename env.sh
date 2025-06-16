#!/bin/bash
# -----------------------------------------------------------------------------
# For every Couchbase bucket directory, perform **exactly** the sequence you
# demonstrated:
#   cd /opt/couchbase/bin
#   export COUCH_CHECK_PATH=/opt/couchbase/bin
#   echo $COUCH_CHECK_PATH
#   ./couch_check_all.sh /opt/couchbase/var/lib/couchbase/data/<bucket>/ *.couch*
# Redirect all output (stdout + stderr) to a per‑bucket log under /home/ubuntu.
# -----------------------------------------------------------------------------

BIN_DIR="/opt/couchbase/bin"                            # location of check scripts
DATA_DIR="/opt/couchbase/var/lib/couchbase/data"        # buckets live here
OUT_DIR="/home/ubuntu"                                  # where logs will be stored

# Ensure the helper scripts are executable (use sudo in case root perms are required)
sudo chmod +x "$BIN_DIR"/couch_check72 \
             "$BIN_DIR"/couch_check76 \
             "$BIN_DIR"/couch_check_all.sh

# Verify data directory exists
if [[ ! -d "$DATA_DIR" ]]; then
  echo "ERROR: $DATA_DIR does not exist." >&2
  exit 1
fi

# Loop over immediate sub‑directories (bucket names)
for bucket_dir in "$DATA_DIR"/*/; do
  bucket_name="${bucket_dir%/}"        # strip trailing slash
  bucket_name="${bucket_name##*/}"     # leave just the directory name

  # Skip dirs that start with '@'
  [[ $bucket_name == @* ]] && continue

  echo "Processing bucket: $bucket_name"

  # Run the commands exactly as requested inside a subshell
  (
    cd "$BIN_DIR" || { echo "Cannot cd to $BIN_DIR" >&2; exit 1; }

    export COUCH_CHECK_PATH="$BIN_DIR"
    echo "$COUCH_CHECK_PATH"  # for visibility, as per the requirement

    ./couch_check_all.sh "$DATA_DIR/$bucket_name/" *.couch* \
      > "$OUT_DIR/couch_check_all_${bucket_name}.txt" 2>&1
  )
done

echo "All bucket checks completed. Logs are under $OUT_DIR."
