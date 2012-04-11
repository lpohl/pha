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
	mylog "[*] receiver prozess not running";
}
if (! -f $CONFIG{INSTALLDIR}."/var/run/sender") {
	mylog "[*] sender prozess not running";
}

my $docnt=0;
while (1) {
	# default gw check?
	# 
	check_defaultroute();

	# Ping check Gateway
        if (icmp_ping($CONFIG{GW}) > 0) {
		
        } else { 
		mylog "Default GW unreachable!"; 
	}
	# Ping check PeerHost
        if (icmp_ping(get_peer_hostname()) > 0) {
		 
        } else { 
		mylog "Peer Host unreachable!"; 
	}
	# check Ressouces
	check_res();

	%ST = read_status();
	if ($ST{STATUS} eq "OFFLINE" and not defined($ST{RECEIVER_IN})) {
		mylog "[*] OFFLINE an no new Data on Receiver, possible Cluster DOWN!";
		# adding some delay to change
		$docnt++;
		if ($docnt>1) {
			mylog "[*] starting resources!";
			foreach my $key (keys %CONFIG) {
        	                if ($key !~ /RES_(\w+)/) {next;}
                		start_res_cli($1);
	                }
			$docnt = 0;
		}
	} 
	if ($ST{STATUS} eq "OFFLINE" and defined($ST{RECEIVER_IN})) {
		mylog "OK remote is active no problem"
	}
	#mylog "rec_in: ".$ST{RECEIVER_IN};

	# Wait a bit
	myusleep($CONFIG{SUPERVISE_INT});
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
		my %st = (SENDER_RUN=>0, STATUS=>'', SUPERVISE=>0);
                update_status(\%st);
                system("rm -f $CONFIG{INSTALLDIR}/var/run/supervise >/dev/null 2>&1");
                exit 0
        } # weiter in endlos-schleife sonst.
}

