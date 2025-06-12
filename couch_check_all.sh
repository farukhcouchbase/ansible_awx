#!/bin/bash

# Exit if any command fails
set -e


if /opt/couchbase/bin/couchbase-server --version | grep "7.2"; then
  # Iterate through all provided filenames
  for file in "$@"; do
      # Run couch_check on the file and capture exit code
      if ! $COUCH_CHECK_PATH/couch_check72 "$file"; then
          # Check if filename matches *.couch.* pattern and extract first part
          if [[ $file =~ ^([0-9]+)\.couch\. ]]; then
              echo "Error with vb:${BASH_REMATCH[1]}"
          else
              echo "Error checking file: $file"
          fi
      fi
  done
fi

if /opt/couchbase/bin/couchbase-server --version | grep "7.6"; then
  # Iterate through all provided filenames
  for file in "$@"; do
      # Run couch_check on the file and capture exit code
      if ! $COUCH_CHECK_PATH/couch_check76 "$file"; then
          # Check if filename matches *.couch.* pattern and extract first part
          if [[ $file =~ ^([0-9]+)\.couch\. ]]; then
              echo "Error with vb:${BASH_REMATCH[1]}"
          else
              echo "Error checking file: $file"
          fi
      fi
  done
fi


echo "done"
