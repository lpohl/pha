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
	my %st = ();
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
		mylog "check_res(): down == 0 STATUS=ONLINE";
	} else {
		$st{STATUS} = 'OFFLINE';
		update_status(\%st);
		mylog "check_res(): down == $down STATUS=OFFLINE";
	}

	# get stat db
	%st = read_status();

	if ($st{RECEIVER_IN} eq "PROGRESS") {
		goto WAIT;
		mylog "somthing is going on... remote";
	}
#	if ($st{STATUS} eq "PROGRESS") {
#		goto WAIT;
#		mylog "somthing is going on... local";
#	}



	#if ($st{STATUS} eq "OFFLINE" and not defined($st{RECEIVER_IN})) {
	if (not defined($st{RECEIVER_IN})) {
		goto WAIT if ($st{STATUS} eq "ONLINE");
		mylog "[*] no new Data on Receiver";
		$st{STATUS} = 'PROGRESS';
		update_status(\%st);
		foreach my $key (keys %CONFIG) {
        	        if ($key !~ /RES_(\w+)/) {next;}
			if ($st{$key} ne "UP") {
	                	start_res_cli($1);
			}
	        }
		$st{STATUS} = 'ONLINE';
		update_status(\%st);
	} 
	if ($st{RECEIVER_IN} eq "OFFLINE") {
		goto WAIT if ($st{STATUS} eq "ONLINE");
		mylog "remote is offline might a problem docnt:$docnt";
		$st{STATUS} = 'PROGRESS';
		update_status(\%st);
		if ($docnt > 2) {
			mylog "remote problem consistent, taking over, starting resources!";
		        foreach my $key (keys %CONFIG) {
				if ($key !~ /RES_(\w+)/) {next;}
        			start_res_cli($1);
		        }
			$st{STATUS} = 'ONLINE';
			update_status(\%st);
			$docnt=0;
		} else {
			$docnt++;
		}
	}
	
	# split brain both active!? no good
	#if ($st{STATUS} eq "ONLINE" and $st{RECEIVER_IN} eq "ONLINE") {
	if ($st{RECEIVER_IN} eq "ONLINE") {
		goto WAIT if ($st{STATUS} eq "OFFLINE");
		mylog "[*] Otherside is online, stopping resources! ";
                foreach my $key (keys %CONFIG) {
                	if ($key !~ /RES_(\w+)/) {next;}
	                stop_res_cli($1);
                }
		$st{STATUS} = 'OFFLINE';
		update_status(\%st);
	}

	
	# hold the status.dat on current information
	#%st = read_status();
	#update_status(\%st);

	# Wait a bit
WAIT:
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
                update_status({SUPERVISE=>0});
                system("rm -f $CONFIG{INSTALLDIR}/var/run/supervise >/dev/null 2>&1");
                exit 0
        } # weiter in endlos-schleife sonst.
}

