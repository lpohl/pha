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

my $LOOPTIME = 200;

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

my $Timeout=30*5;
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
		myusleep($LOOPTIME);
		udp_send();
        }
}

sub udp_send {
	my ($buf,$v,$k,$tmp,$msg,$crc);
	my %st = ();
	%st = read_status();
	if ($st{SENDER_RUN} == 1) {
		%st = read_status();
		#$msg = $NODES{local};
		$msg = $st{STATUS};
		# send datagramm
	        $CLsocket->send($msg, 0) or mylog "udp_send() ".$!;
		# $! == "No route to host" ^= peer firewalled
		# $! == "Connection refused" ^= peer receiver Port down
	} else {
		if ($Timeout==0) {
			update_status({SENDER_RUN=>1});
			$Timeout = 30*5;
		} else {
			$Timeout--;
		}
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

        # Cleanup and Terminate if SIGNAL was SIGINT (^c)
        if ($signal eq "INT") {
                $CLsocket->close();
		update_status({SENDER_RUN=>0});
		system("rm -f $CONFIG{INSTALLDIR}/var/run/sender >/dev/null 2>&1");
                exit 0
        } 
}

