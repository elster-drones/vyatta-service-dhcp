#!/opt/vyatta/bin/cliexpr
#only serve default vrf so far. it will support non-vrf-aware daemon in the future
end:expression: exec "dhcv6relay-starter.pl --rtinst=default --config_action=${COMMIT_ACTION}"
