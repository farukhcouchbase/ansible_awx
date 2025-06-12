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

## bucket_list : JSON array containing names of all buckets in the default pool.
##               Extracted using jq from the /pools/default endpoint.
bucket_list=$(curl -s -u "$username:$password" "$buckets_endpoint" | jq '.bucketNames')

## ---------------------------------------------------------
## Output the parsed information to the console
## ---------------------------------------------------------
echo "Following are the path and bucket list:"
echo "---- Storage Paths ----"
echo "$storage_info"
echo "---- Bucket List ----"
echo "$bucket_list"



DATA_DIR="/opt/couchbase/var/lib/couchbase/data"

for dir in "$DATA_DIR"/*; do
  # Only enter if it's a directory and not a symlink or special file
  if [ -d "$dir" ]; then
    echo "Storage of $dir:"
    ls "$dir"
    echo "---------------------------"
  fi
done




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
