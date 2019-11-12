#!/opt/vyatta/bin/cliexpr
end:expression: exec "dhcv6relay-starter.pl --rtinst=$VAR(../../@) --config_action=${COMMIT_ACTION}"
