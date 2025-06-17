#!/bin/bash

## Exit immediately if any command returns a non‑zero status.
set -e

###############################################################################
## BLOCK 1: Handle Couchbase Server 7.2 data files
###############################################################################
## – Detect whether the installed Couchbase Server reports version 7.2.
## – If so, run the couch_check72 utility on every file passed to the script.
## – On failure, show a friendly error that tries to include the vBucket (vb)
##   number when the filename follows the pattern <vb>.couch.*
###############################################################################
if /opt/couchbase/bin/couchbase-server --version | grep "7.2"; then
  for file in "$@"; do                                      ## Loop over all arguments
      if ! "$COUCH_CHECK_PATH/couch_check72" "$file"; then  ## Run the 7.2 checker
          ## If filename is like “123.couch.*”, capture the leading digits (vb no.)
          if [[ $file =~ ^([0-9]+)\.couch\. ]]; then
              echo "Error with vb:${BASH_REMATCH[1]}"       ## Print “Error with vb:123”
          else
              echo "Error checking file: $file"             ## Generic error message
          fi
      fi
  done
fi

###############################################################################
## BLOCK 2: Handle Couchbase Server 7.6 data files
###############################################################################
## – Same idea, but uses the couch_check76 utility for 7.6‑format files.
###############################################################################
if /opt/couchbase/bin/couchbase-server --version | grep "7.6"; then
  for file in "$@"; do
      if ! "$COUCH_CHECK_PATH/couch_check76" "$file"; then  ## Run the 7.6 checker
          if [[ $file =~ ^([0-9]+)\.couch\. ]]; then
              echo "Error with vb:${BASH_REMATCH[1]}"
          else
              echo "Error checking file: $file"
          fi
      fi
  done
fi

## All done!
echo "done"
