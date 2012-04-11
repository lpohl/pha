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

my $docnt = 0;
my $down = 0;
while (1) {
	## default gw check?
	#if(check_defaultroute()) {
	#
	#} else {
	#	mylog "ERROR no Default GW set!"; 
	#}
	#
	## Ping check Gateway
        #if (icmp_ping($CONFIG{GW}) > 0) {
	#	
        #} else { 
	#	mylog "Default GW unreachable!"; 
	#}
	## Ping check PeerHost
        #if (icmp_ping(get_peer_hostname()) > 0) {
	#	 
        #} else { 
	#	mylog "Peer Host unreachable!"; 
	#}

	# check Ressouces
	$down = check_res();
	if ($down == 0) {
		$st{STATUS} = 'ONLINE';
		update_status(\%st);
	}

	%st = read_status();
	if ($st{STATUS} eq "OFFLINE" and not defined($st{RECEIVER_IN})) {
		mylog "[*] OFFLINE an no new Data on Receiver, possible Cluster DOWN!";
		# adding some delay to change
		mylog "[*] starting resources!";
		$st{STATUS} = 'PROGRESS';
		update_status(\%st);
		foreach my $key (keys %CONFIG) {
        	        if ($key !~ /RES_(\w+)/) {next;}
                	start_res_cli($1);
	        }
		$st{STATUS} = 'ONLINE';
		update_status(\%st);
	} 
	if ($st{STATUS} eq "OFFLINE" and $st{RECEIVER_IN} eq "OFFLINE") {
		mylog "OK remote is offline problem, starting resources!";
		$st{STATUS} = 'PROGRESS';
		update_status(\%st);
	        foreach my $key (keys %CONFIG) {
			if ($key !~ /RES_(\w+)/) {next;}
        		start_res_cli($1);
	        }
		$st{STATUS} = 'ONLINE';
		update_status(\%st);
	}
	
	# split brain both active!? no good
	if ($st{STATUS} eq "ONLINE" and $st{RECEIVER_IN} eq "ONLINE") {
		mylog "[*] stopping resources!";
                foreach my $key (keys %CONFIG) {
                	if ($key !~ /RES_(\w+)/) {next;}
	                stop_res_cli($1);
                }
	}

	if ($st{STATUS} eq "PROGRESS" or $st{RECEIVER_IN} eq "PROGRESS") {
		mylog "somthing is going on...";
	}
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

