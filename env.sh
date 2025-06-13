#!/bin/bash

# Make the scripts executable
sudo chmod +x /opt/couchbase/bin/couch_check72
sudo chmod +x /opt/couchbase/bin/couch_check76
sudo chmod +x /opt/couchbase/bin/couch_check_all.sh

# Set environment variable
export COUCH_CHECK_PATH=/opt/couchbase/bin

cd /opt/couchbase/bin/

./couch_check_all.sh /opt/couchbase/var/lib/couchbase/data/travel-sample/* > /home/ubuntu/couch_check_all.txt
