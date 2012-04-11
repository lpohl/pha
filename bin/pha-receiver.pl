#!/usr/bin/perl

use lib qw(/opt/pha/lib);
use pha;
use IO::Socket::INET;
use IO::Select;

sub init_receiver;
sub udp_server;
sub sighandler;

my ($SRVsocket, $SRVselect);

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

init_receiver();

exit 0;

#
# Subs
#

sub init_receiver {
	# Server Socket zum empfangen / wird in eigenen Thread durchgeführt
        $SRVsocket = IO::Socket::INET->new(     Proto => 'udp',
                                                Type => SOCK_DGRAM,
                                                LocalPort => $CONFIG{PORT},
                                                Blocking => 0,
                                                ) or
                        die "error: failed to create udp Listener - $!";
	# Select for NonBlocking
        $SRVselect = IO::Select->new();
        $SRVselect->add($SRVsocket);

	open(FH,">",$CONFIG{INSTALLDIR}."/var/run/receiver") or die $!;
        print FH $$;
        close(FH);

	my %st=();
        $st{RECEIVER_IN} = undef;
        update_status(\%st);

	mylog "$0 process startet";

        while (1) {
                udp_server();
                myusleep(150)
        }
}


sub udp_server {
        my ($sock,$buf,$bytes_read);
        $bytes_read = 0;
	my %st = ();

        my @ready = $SRVselect->can_read(1);
        foreach $sock (@ready) {
                $bytes_read = sysread($SRVsocket, $buf, 1500);
        }
        if ($bytes_read != 0) {
                print STDERR "[DBG] udp_server_loop() Read $bytes_read\n" if ($CONFIG{DEBUG} == 1);
                #mylog "udp_server_loop() Read $bytes_read";
                $bytes_read = 0;
        } else {
		$st{RECEIVER_IN} = undef;
		update_status(\%st);
	}
        if (length($buf) > 0) {
		$st{RECEIVER_IN} = $buf;
		update_status(\%st);
                $buf = undef;
        }
}

sub sighandler {
        my $signal = shift;      # signal-nummer besorgen

        $SIG{'INT'}  = 'sighandler'; # reinstall sig-handler
        $SIG{'TERM'} = 'sighandler'; # reinstall sig-handler

        mylog "sighandler() Signal: SIG$signal caught!";

        # raus, falls SIGINT
        if ($signal eq "INT") {
                $SRVsocket->close();
		#my %st = (RECEIVER_IN=>undef);
                #update_status(\%st);
		system("rm -f $CONFIG{INSTALLDIR}/var/run/receiver >/dev/null 2>&1");
                exit 0;
        } # weiter in endlos-schleife sonst.
}

