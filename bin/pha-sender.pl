#!/usr/bin/perl

use lib qw(/opt/pha/lib);
use pha;
use IO::Socket::INET;

sub init_sender;
sub udp_send;
sub sighandler;

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

init_sender();

#
# Subs
#
sub init_sender {
        # Client Socket zum senden an die Broadcast
        $CLsocket = IO::Socket::INET->new(      Broadcast => 1,
                                                Blocking => 1,
                                                ReuseAddr => 1,
                                                Type => SOCK_DGRAM,
                                                Proto => 'udp',
                                                PeerPort => $CONFIG{PORT},
                                                LocalPort => 0,
                                                PeerAddr => get_peer_hostname) or
                        die "error: failed to create broadcast udp  Client socket - $!";
                                                #PeerAddr => inet_ntoa(INADDR_BROADCAST)) or

	open(FH,">",$CONFIG{INSTALLDIR}."/var/run/sender") or die $!;
		print FH $$;
	close(FH);

	mylog "$0 process startet";
        # udp Server with own prozess
        while (1) {
		udp_send();
		myusleep(200)
        }
}

sub udp_send {
	my ($buf,$v,$k,$tmp,$msg,$crc);

	%ST = read_status();
	if ($ST{SENDER_RUN} == 1) {
        	$ST{SENDER_TS} = time()."";
		write_status();
		$msg = $NODES{local};
	        $CLsocket->send($msg, 0) or mylog $!;
		# $! == "No route to host" ^= peer firewalled
		# $! == "Connection refused" ^= peer receiver Port down
	}

	# Old way
        # Send Data as Storable
        #$buf = Storable::freeze(\%ST);
        #$crc = unpack ("%16C*", $buf);
        #$msg = sprintf ("%.4d", $crc ).$buf;

}


sub sighandler {
        my $signal = shift;      # signal-nummer besorgen

        $SIG{'INT'}  = 'sighandler'; # reinstall sig-handler
        $SIG{'TERM'} = 'sighandler'; # reinstall sig-handler

        mylog "sighandler() Signal: SIG$signal caught!";

        # raus, falls SIGINT
        if ($signal eq "INT") {
                $CLsocket->close();
		my %st = (SENDER_RUN=>0, STATUS=>'');
		update_status(\%st);
		system("rm -f $CONFIG{INSTALLDIR}/var/run/sender >/dev/null 2>&1");
                exit 0
        } # weiter in endlos-schleife sonst.
}

