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

	# generate STATUS Prompt (like bash)
	my $state;
	%ST = read_status();
	if ($ST{STATUS} eq "ONLINE") {
		$state = "Active";
	}
	elsif ($ST{STATUS} eq "OFFLINE") {
		$state = "Standby";
	} else {
		$state = "NOTRUNNING";
	}
	
	# Hard workaround if status update on status.dat in sighandler is not working
	#if (	! -f $CONFIG{INSTALLDIR}."/var/run/receiver" or
	#	! -f $CONFIG{INSTALLDIR}."/var/run/sender" or
	#	! -f $CONFIG{INSTALLDIR}."/var/run/supervise" )
	#{
	#	$state = "NOTRUNNING";
	#}
	
	print "[".get_local_hostname.":$state] > ";
	
	# read user input
	my $in = <STDIN>;
	my $st = ();
	# switch through the commands
	if ($in =~ /^help$|^HELP$|^\?$|^h$/) {
		print <<EOS
start	start all services (sender,receiver,supervise)
stop	stop all services (sender,receiver,supervise)	

se_sta	start sender service
se_sto	stop sender service
re_sta	start receiver service
re_sto	stop receiver service
su_sta	start supervise service
su_sto	stop supervise service

res	Manage Ressources (parameter list|stop|start)
status	dump contents of var/status.dat and show daemons PIDs
config	show content of parsed config Data
quit|q	leave pha-cli shell

EOS
;
	} elsif ($in =~ /^se_dis|^disable$|^forceoffline$|^fo$|^offline$/) {
		$st{SENDER_RUN} = 0;
		update_status(\%st);
	} elsif ($in =~ /^se_en|^online$|^enable$|^on$/) {
		$st{SENDER_RUN} = 1;
		update_status(\%st);
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
        } elsif ($in =~ /^status$|^stat$/) {
		dump_status();
		print "sender: \t".get_pid('sender')."\n";
		print "receiver:\t".get_pid('receiver')."\n";
		print "supervise:\t".get_pid('supervise')."\n";
        } elsif ($in =~ /^res$/) {
		print "use: res <list|stop|start> [<resname>]\n";
        } elsif ($in =~ /^res (\w+)$/) {
		#print "BLA: ".Dumper(%CONFIG);
		my $cmd = $1;
		if ($cmd eq "list") {
	                foreach my $key (keys %CONFIG) {
        	        	if ($key !~ /RES_(\w+)/) {next;}
                	        print $1."\n";
			}
		} elsif($cmd eq "stop") {
			 foreach my $key (keys %CONFIG) {
                                if ($key !~ /RES_(\w+)/) {next;}
                               	stop_res_cli($1);
                        }
		} elsif($cmd eq "start") {
			 foreach my $key (keys %CONFIG) {
                                if ($key !~ /RES_(\w+)/) {next;}
                               	start_res_cli($1);
                        }
		} else {
			print "else?\n";
		}
		 
        } elsif ($in =~ /^res (\w+) (\w+)/) {
		if ($1 eq "start" and $2) {
			start_res_cli($2);
		} elsif ($1 eq "stop" and $2)  { 
			stop_res_cli($2);
		} else {
			print "else?\n";
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

