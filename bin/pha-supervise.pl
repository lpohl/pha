#!/usr/bin/perl

use lib qw(/opt/pha/lib);
use pha;

sub sighandler;


# MAIN()
mylog "$0 Started";

# fange SIGINT, SIGTERM ab:
$SIG{'INT'}  = 'sighandler';
$SIG{'TERM'} = 'sighandler';

# MAIN()
if ($CONFIG{DAEMON} == 1) {
        # we are a Daemon, Fork into background
        my $pid=fork();
        if ($pid > 0) {
                exit 0;
        } else {
                chdir ($CONFIG{INSTALLDIR});
        }
}

open(FH,">",$CONFIG{INSTALLDIR}."/var/run/supervise") or die $!;
	print FH $$;
close(FH);

if (! -f $CONFIG{INSTALLDIR}."/var/run/receiver") {
	mylog "[*] reciver prozess not running";
}
if (! -f $CONFIG{INSTALLDIR}."/var/run/sender") {
	mylog "[*] sender prozess not running";
}

while (1) {
	# default gw check?
	# 
	check_defaultroute();

	# Ping check
        if (icmp_ping($CONFIG{GW}) > 0) {
		
        } else { mylog "Default GW nicht erreichbar!"; }
		
        if (icmp_ping(get_peer_hostname()) > 0) {
		 
        } else { mylog "Peer Host nicht erreichbar!"; }
	
	check_res();

	myusleep(1000);
}

exit 0;

#
# Subs
# 
sub sighandler {
        my $signal = shift;      # signal-nummer besorgen

        $SIG{'INT'}  = 'sighandler'; # reinstall sig-handler
        $SIG{'TERM'} = 'sighandler'; # reinstall sig-handler

        mylog "sighandler() Signal: SIG$signal caught!";

        # raus, falls SIGINT
        if ($signal eq "INT") {
                system("rm -f $CONFIG{INSTALLDIR}/var/run/supervise >/dev/null 2>&1");
                exit 0
        } # weiter in endlos-schleife sonst.
}
