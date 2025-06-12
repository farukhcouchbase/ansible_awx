#!/bin/bash

# Move zip files and script to Couchbase binary directory
sudo mv couch_check72.zip /opt/couchbase/bin/
sudo mv couch_check76.zip /opt/couchbase/bin/
sudo mv couch_check_all.sh /opt/couchbase/bin/

# Change to binary directory
cd /opt/couchbase/bin/ || exit 1

# Unzip the check files
sudo unzip -o couch_check72.zip
sudo unzip -o couch_check76.zip

# Make the scripts executable
sudo chmod +x couch_check72
sudo chmod +x couch_check76
sudo chmod +x couch_check_all.sh

# Set environment variable
export COUCH_CHECK_PATH=/opt/couchbase/bin

# Run the check script on all .couch.* files in the travel-sample bucket
cd /opt/couchbase/var/lib/couchbase/data/travel-sample || exit 1
$COUCH_CHECK_PATH/couch_check_all.sh *.couch.*
