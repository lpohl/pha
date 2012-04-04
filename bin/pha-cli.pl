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
mylog "$0 started";


# cli loop
while(1) {
	my $state;
	%ST = read_status();
	if ($ST{STATUS} eq "ONLINE") {
		$state = "Active";
	}
	elsif ($ST{STATUS} eq "OFFLINE") {
		$state = "Standby";
	}
	print "[".get_local_hostname.":$state] > ";
	my $in = <STDIN>;

	if ($in =~ /^help$|^HELP$|^\?$|^h$/) {
		print <<EOS
more to come!
EOS
;
	} elsif ($in =~ /^se_dis|^forceoffline|^fo|^offline/) {
		%ST = read_status();
		$ST{SENDER_RUN} = 0;
		write_status();
	} elsif ($in =~ /^se_en|^online|^enable/) {
		%ST = read_status();
		$ST{SENDER_RUN} = 1;
		write_status();
	} elsif ($in =~ /^start/) {
		start_service('sender');
		start_service('receiver');
		start_service('supervise');
	} elsif ($in =~ /^stop/) {
		stop_service('sender');
		stop_service('receiver');
		stop_service('supervise');
	} elsif ($in =~ /^se_sto/) {
		stop_service('sender');
	} elsif ($in =~ /^se_sta/) {
		start_service('sender');
	} elsif ($in =~ /^re_sto/) {
		stop_service('receiver');
	} elsif ($in =~ /^re_sta/) {
		start_service('receiver');
	} elsif ($in =~ /^su_sto/) {
                stop_service('supervise');
        } elsif ($in =~ /^su_sta/) {
		start_service('supervise');
        } elsif ($in =~ /^status|^stat/) {
		dump_status();
		print "sender: \t".get_pid('sender')."\n";
		print "receiver:\t".get_pid('receiver')."\n";
		print "supervise:\t".get_pid('supervise')."\n";
        } elsif ($in =~ /^res$/) {
		print "use: res <list|stop|start> [<resname>]\n";
        } elsif ($in =~ /^res (\w+) (\w+)$|^res (\w+)$/) {
		if ($1 eq "list") {
			foreach my $key (keys %CONFIG) {
               			if ($key !~ /RES_(\w+)/) {next;}
				print $1."\n";
			}
		} elsif ($1 eq "start" and $2) {
			start_res_cli($2);
		} elsif ($1 eq "stop" and $2)  { 
			stop_res_cli($2);
		}
        } elsif ($in =~ /^show conf|^conf/) {
		dump_config();
	} elsif ($in =~ /^quit$|^exit$|^q$/) {
		print "Bye!\n";
		last;
	} else {
		#print "wtf? try 'help'\n";
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

