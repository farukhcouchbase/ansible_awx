#!/bin/bash

# Move zip files and script to Couchbase binary directory
sudo mv couch_check72.zip /opt/couchbase/bin/
sudo mv couch_check76.zip /opt/couchbase/bin/
sudo mv couch_check_all.sh /opt/couchbase/bin/

# Unzip the check files
sudo unzip -o /opt/couchbase/bin/couch_check72.zip
sudo unzip -o /opt/couchbase/bin/couch_check76.zip

# Make the scripts executable
sudo chmod +x /opt/couchbase/bin/couch_check72
sudo chmod +x /opt/couchbase/bin/couch_check76
sudo chmod +x /opt/couchbase/bin/couch_check_all.sh

# Set environment variable
export COUCH_CHECK_PATH=/opt/couchbase/bin

# Run the check script on all .couch.* files in the travel-sample bucket
cd /opt/couchbase/var/lib/couchbase/data/travel-sample || exit 1
$COUCH_CHECK_PATH/couch_check_all.sh *.couch.*
