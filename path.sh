#!/bin/bash

################################################################################
## Script: Couchbase Info Fetcher
## Description:
##   This script connects to a Couchbase Server running locally and retrieves
##   information about the storage paths and list of buckets.
## 
## Usage:
##   Ensure `jq` is installed and Couchbase is running on localhost:8091.
##   Update username and password if necessary.
##
## Dependencies:
##   - curl: for making HTTP requests
##   - jq: for parsing JSON responses
################################################################################

## -------------------------------
## Credentials for Couchbase Admin
## -------------------------------
## username : Admin username for HTTP Basic Auth
## password : Corresponding password for the Admin
username="Admin"
password="redhat"

## -------------------------------
## Base URL of Couchbase Server
## -------------------------------
## base_url : Root URL used for all Couchbase REST API requests
base_url="http://localhost:8091"

## ---------------------------------------------------------
## Couchbase REST API endpoints used in this script
## ---------------------------------------------------------

## storage_endpoint : API endpoint to get the node-specific configuration,
##                    including storage paths and disk information.
##                    (/nodes/self returns data about the local node)
storage_endpoint="$base_url/nodes/self"

## buckets_endpoint : API endpoint to get general information about the Couchbase
##                    cluster, including list of buckets in the pool.
##                    (/pools/default gives details about the default cluster pool)
buckets_endpoint="$base_url/pools/default"

## ---------------------------------------------------------
## Fetch data from Couchbase REST APIs and parse with jq
## ---------------------------------------------------------

## storage_info : JSON object containing information about storage paths.
##                Extracted using jq from the /nodes/self endpoint.
storage_info=$(curl -s -u "$username:$password" "$storage_endpoint" | jq '.storage')
hostname_info=$(curl -s -u "$username:$password" "$storage_endpoint" | jq '.hostname')

## bucket_list : JSON array containing names of all buckets in the default pool.
##               Extracted using jq from the /pools/default endpoint.
bucket_list=$(curl -s -u "$username:$password" "$buckets_endpoint" | jq '.bucketNames')

## ---------------------------------------------------------
## Output the parsed information to the console
## ---------------------------------------------------------


echo "--------------- Hostname -------------------"
echo $hostname_info



echo "----------- List Of The Bucket -------------"

DATA_DIR="/opt/couchbase/var/lib/couchbase/data"

# Check if the directory exists
if [ -d "$DATA_DIR" ]; then
  for item in "$DATA_DIR"/*; do
    basename=$(basename "$item")
    if [[ "$basename" != @* ]]; then
      echo "$basename"
    fi
  done
else
  echo "Directory $DATA_DIR does not exist."
  exit 1
fi





#!/usr/bin/env bash
# Traverse Couchbase data buckets, skipping names that start with '@'

DATA_DIR="/opt/couchbase/var/lib/couchbase/data"

# Bail out early if the target directory is missing
if [[ ! -d "$DATA_DIR" ]]; then
  echo "ERROR: $DATA_DIR does not exist."
  exit 1
fi

# Jump into the data directory
cd "$DATA_DIR" || { echo "Cannot cd to $DATA_DIR"; exit 1; }

# Iterate over immediate sub‑directories
for dir in */ ; do
  # Strip trailing slash for a clean name
  name="${dir%/}"

  # Skip anything that begins with '@'
  [[ $name == @* ]] && continue

  # Enter the directory in a subshell so the outer loop stays in DATA_DIR
  (
    cd "$dir" || exit        # change into the bucket directory
    echo "Now inside: $PWD"  # placeholder — do whatever you need here
    # Example command: ls -lh
    # Add more operations as required
  )
done
