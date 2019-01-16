#/bin/bash

# start rsync in daemon mode and load config
rsync --config=/etc/rsyncd.conf --server --daemon .

