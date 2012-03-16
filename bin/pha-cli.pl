#!/usr/bin/perl

use lib qw(/opt/pha/lib);
use pha;
use Data::Dumper;


# fange SIGINT, SIGTERM ab:
$SIG{'INT'}  = 'sighandler';
$SIG{'TERM'} = 'sighandler';


# MAIN()

open(FH,">",$CONFIG{INSTALLDIR}."/var/run/cli") or die $!;
print FH $$;
close(FH);
mylog "$0 Started";


# cli loop
while(1) {
	print get_local_hostname."> ";
	my $in = <STDIN>;

	if ($in =~ /^help$|^HELP$|^\?$|^h$/) {
		print "more to come!\n";
	} elsif ($in =~ /^se_dis/) {
		%ST = read_status();
		$ST{SENDER_RUN} = 0;
		write_status();
	} elsif ($in =~ /^se_en/) {
		%ST = read_status();
		$ST{SENDER_RUN} = 1;
		write_status();
	} elsif ($in =~ /^se_stop/) {
		stop_service('sender');
	} elsif ($in =~ /^se_start/) {
		system($CONFIG{INSTALLDIR}."/bin/pha-sender.pl");
	} elsif ($in =~ /^re_stop/) {
		stop_service('receiver');
	} elsif ($in =~ /^re_start/) {
		system($CONFIG{INSTALLDIR}."/bin/pha-receiver.pl");
	} elsif ($in =~ /^su_stop/) {
                stop_service('supervise');
        } elsif ($in =~ /^su_start/) {
                system($CONFIG{INSTALLDIR}."/bin/pha-supervise.pl");

	} elsif ($in =~ /^quit$|^exit$|^q$/) {
		print "Bye!\n";
		last;
	} else {
		print "wtf? try 'help'\n";
	}
	dump_status() if ($CONFIG{DEBUG} == 1);
}

sighandler('INT');

#
# Subs
#

sub dump_status {
	my $href = Storable::lock_retrieve($CONFIG{INSTALLDIR}."/var/status.dat");
	print Dumper($href);
}

sub dump_config {
	foreach (sort keys (%CONFIG)) {
		if (ref $CONFIG{$_} ) {
			print $_."=";
			foreach $v (@{$CONFIG{$_}}) {
				print "$v ";
			}
			print "\n";
		} else {
			print $_."=".$CONFIG{$_}."\n";
		}
	}
}

sub sighandler {
        my $signal = shift;      # signal-nummer besorgen

        $SIG{'INT'}  = 'sighandler'; # reinstall sig-handler
        $SIG{'TERM'} = 'sighandler'; # reinstall sig-handler

        mylog "sighandler() Signal: SIG$signal caught!";

        # raus, falls SIGINT
        if ($signal eq "INT") {
                system("rm -f $CONFIG{INSTALLDIR}/var/run/cli >/dev/null 2>&1");
                exit 0
        } # weiter in endlos-schleife sonst.
}

