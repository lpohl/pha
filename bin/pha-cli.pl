#!/usr/bin/perl

use lib qw(/opt/pha/lib);
use pha;
use Data::Dumper;


# catch SIGINT and SIGTERM:
$SIG{'INT'}  = 'sighandler';
$SIG{'TERM'} = 'sighandler';


# MAIN()
if (-f $CONFIG{INSTALLDIR}."/var/run/cli") {
	print STDERR "[*] ERR pha-cli allready running!\n";	
	exit 1;
}
# Write PID
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
	}
	elsif ($ST{STATUS} eq "PROGRESS") {
		# dont change prompt
	}
	else {
		$state = "NOTRUNNING";
	}
	
	print "[".get_local_hostname.":$state] > ";
	
	# read user input
	my $in = <STDIN>;
	my $st = ();
	# switch through the commands
	if ($in =~ /^help$|^HELP$|^\?$|^h$/) {
		print <<EOS
start	start all services (sender,receiver,supervise)
stop	stop all services (sender,receiver,supervise)	

disable stop sender, this WILL trigger a failover to other side
enable  enable sender

res	Manage Ressources (parameter list|stop|start)
status	dump contents of var/status.dat and show daemons PIDs
config	show content of parsed config Data
quit|q	leave pha-cli shell

EOS
;
	} elsif ($in =~ /^dis|^off/) {
		print "stop sending Heartbeat\n";
		update_status({SENDER_RUN=>0});
	} elsif ($in =~ /^ena|^on/) {
		print "starting to send Heartbeat\n";
		update_status({SENDER_RUN=>1});
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

	# Cleanup and Terminate if SIGNAL was SIGINT (^c)
        if ($signal eq "INT") {
		update_status({CLI=>0});
                system("rm -f $CONFIG{INSTALLDIR}/var/run/cli >/dev/null 2>&1");
                exit 0
        } 
}

