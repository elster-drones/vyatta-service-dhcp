tmplscriptdir = $(datadir)/tmplscripts

sbin_SCRIPTS =

sbin_SCRIPTS += scripts/system/dhcpd-config.pl
sbin_SCRIPTS += scripts/system/dhcpdv6-config.pl
sbin_SCRIPTS += scripts/system/dhcpd.init
sbin_SCRIPTS += scripts/system/dhcpdv6.init
sbin_SCRIPTS += scripts/system/listento-intfs.pl
sbin_SCRIPTS += scripts/system/vyatta-validate-duid.pl
sbin_SCRIPTS += scripts/dhcpdv6-show-leases.pl
sbin_SCRIPTS += scripts/dhcpdv6-show-status.pl

opdir		 = $(datadir)/vyatta-op/templates
netplug_deladdrdir = /etc/netplug/deladdr.d
netplug_newaddrdir = /etc/netplug/newaddr.d

bin_SCRIPTS = scripts/vyatta-clear-dhcp-lease.pl
bin_SCRIPTS += scripts/vyatta-show-dhcp-server.pl
bin_SCRIPTS += scripts/dhcp-show-leases.pl

share_perl5dir   = $(datarootdir)/perl5/Vyatta/
share_perl5_DATA = lib/DHCPServerOpMode.pm
share_perl5_DATA += lib/DHCPv6Duid.pm

netplug_deladdr_SCRIPTS = scripts/netplug/deladdr.d/dhcpd

netplug_newaddr_SCRIPTS = scripts/netplug/newaddr.d/dhcpd

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
	cpio -0pd

install-exec-hook:
	mkdir -p $(DESTDIR)$(tmplscriptdir)
	cd tmplscripts && $(cpiop) $(DESTDIR)$(tmplscriptdir)

	mkdir -p $(DESTDIR)$(opdir)
	cd templates; $(cpiop) $(DESTDIR)$(opdir)
