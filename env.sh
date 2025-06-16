#!/bin/bash
# -----------------------------------------------------------------------------
# Run couch_check_all.sh against every Couchbase bucket directory.
# - Skips any bucket whose directory name starts with '@'.
# - Creates a separate log file for each bucket under /home/ubuntu.
# -----------------------------------------------------------------------------

BIN_DIR="/opt/couchbase/bin"                            # location of check scripts
DATA_DIR="/opt/couchbase/var/lib/couchbase/data"        # buckets live here
OUT_DIR="/home/ubuntu"                                  # where logs will be stored

# Ensure the helper scripts are executable (use sudo in case root perms are required)
sudo chmod +x "$BIN_DIR"/couch_check72 \
             "$BIN_DIR"/couch_check76 \
             "$BIN_DIR"/couch_check_all.sh

# Make the path visible to couch_check_all.sh, in case it spawns sub‑checks
export COUCH_CHECK_PATH="$BIN_DIR"

# Bail out early if the data directory is missing
if [[ ! -d "$DATA_DIR" ]]; then
  echo "ERROR: $DATA_DIR does not exist."
  exit 1
fi

# Traverse immediate sub‑directories (i.e., the buckets)
for bucket_dir in "$DATA_DIR"/*/; do
  bucket_name="${bucket_dir%/}"        # strip trailing slash
  bucket_name="${bucket_name##*/}"     # leave just the directory name

  # Skip dirs that start with '@'
  [[ $bucket_name == @* ]] && continue

  # Run the check inside a subshell so we stay rooted at DATA_DIR
  (
    cd "$bucket_dir" || {
      echo "Cannot cd to $bucket_dir"
      exit 1
    }

    echo "Running couch_check_all.sh in $PWD"
    # Scan all .couch.* files in the current bucket dir
    "$BIN_DIR"/couch_check_all.sh "$PWD"/*.couch.* \
      > "$OUT_DIR/couch_check_all_${bucket_name}.txt" 2>&1
  )
done


