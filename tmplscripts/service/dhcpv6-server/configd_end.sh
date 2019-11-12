#!/bin/bash

RTINST=$1
if [ -z "$RTINST" ]; then
    $RTINST = "default"
fi

dhcpdv6-config.pl --rtinst=$RTINST

RTVALUE=$?
if [ $RTVALUE -eq  "1" ]; then
    echo "Can not start DHCPv6 server due to configuration errors!"
    exit 1
elif [ $RTVALUE -eq 2 ]; then  # special case for AT&T
    echo "Can not start DHCPv6 server due to no shared network is configed!"
    #stop dhcpdv6 if running
    dhcpdv6.init stop $RTINST
    exit 0 
elif [ $RTVALUE -eq 255 ]; then
    echo "Can not start DHCPv6 server due to configuration errors!"
    exit 1
fi

if [ "$COMMIT_ACTION" = "SET" ]; then
    dhcpdv6.init start $RTINST
elif [ "$COMMIT_ACTION" = "DELETE" ]; then
    dhcpdv6.init stop $RTINST
elif [ "$COMMIT_ACTION" = "ACTIVE" ]; then
    dhcpdv6.init restart $RTINST
else
    echo "Error: COMMIT_ACTION environment variable is not set!"
    exit 0
fi
echo "Done."
