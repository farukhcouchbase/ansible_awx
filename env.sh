#!/bin/bash
# -----------------------------------------------------------------------------
# For every Couchbase bucket directory, this script performs the following:
#   1. Navigates to the Couchbase bin directory.
#   2. Sets the COUCH_CHECK_PATH environment variable.
#   3. Runs couch_check_all.sh on the bucket's .couch* files.
#   4. Redirects all output to a per-bucket log in /home/ubuntu.
# -----------------------------------------------------------------------------

BIN_DIR="/opt/couchbase/bin"                            ## Directory where Couchbase check scripts reside
DATA_DIR="/opt/couchbase/var/lib/couchbase/data"        ## Parent directory that holds all Couchbase bucket data
OUT_DIR="/home/ubuntu"                                  ## Output directory where logs will be saved

## Ensure that the couch check scripts are executable (chmod +x), using sudo in case root privileges are needed
sudo chmod +x "$BIN_DIR"/couch_check72 \
             "$BIN_DIR"/couch_check76 \
             "$BIN_DIR"/couch_check_all.sh

## Check that the data directory actually exists
if [[ ! -d "$DATA_DIR" ]]; then
  echo "ERROR: $DATA_DIR does not exist." >&2           ## Print error to stderr if data directory is missing
  exit 1                                                ## Exit the script with a non-zero status
fi

## Loop over each immediate subdirectory (assumed to be a Couchbase bucket)
for bucket_dir in "$DATA_DIR"/*/; do
  bucket_name="${bucket_dir%/}"        ## Remove trailing slash
  bucket_name="${bucket_name##*/}"     ## Extract the bucket name (just the directory name)

  ## Skip system/internal buckets (usually prefixed with '@')
  [[ $bucket_name == @* ]] && continue

  echo "Processing bucket: $bucket_name"                ## Notify which bucket is being processed

  ## Run commands in a subshell to avoid polluting the outer environment
  (
    cd "$BIN_DIR" || { echo "Cannot cd to $BIN_DIR" >&2; exit 1; }   ## Change to bin directory, exit if it fails

    export COUCH_CHECK_PATH="$BIN_DIR"                  ## Set environment variable as required
    echo "$COUCH_CHECK_PATH"                            ## Echo the path for visibility/logging

    ## Run couch_check_all.sh on the current bucket directory
    ## Redirect both stdout and stderr to a log file named after the bucket
    ./couch_check_all.sh "$DATA_DIR/$bucket_name/" *.couch* \
      > "$OUT_DIR/couch_check_all_${bucket_name}.txt" 2>&1
  )
done

echo "All bucket checks completed. Logs are under $OUT_DIR."  ## Final message after processing all buckets
