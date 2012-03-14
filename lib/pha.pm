package pha;

use strict;
use warnings;

use Storable;
use Fcntl;
use SDBM_File;
use Sys::Hostname qw(hostname);
use Net::Ping;

# Export in Callernamespace (@EXPORT)  
require Exporter;
use vars qw( @ISA @EXPORT @EXPORT_OK );
@ISA = qw(Exporter AutoLoader);
@EXPORT 	= qw( checkconfig mylog var_getcopy var_get var_add var_del var_delall write_status read_status write_conf read_conf myusleep get_peer_hostname get_local_hostname %RES %CONFIG %ST %NODES get_pid stop_service icmp_ping check_link_local check_defaultroute );
@EXPORT_OK 	= qw( checkconfig mylog var_getcopy var_get var_add var_del var_delall write_status read_status write_conf read_conf myusleep get_peer_hostname get_local_hostname %RES %CONFIG %ST %NODES get_pid stop_service icmp_ping check_link_local check_defaultroute ); 

##########################################
# ggf. Konfigurations Dateipfad anpassen #
##########################################

our %CONFIG		= read_configfile("/opt/pha/etc/config");

##############################################################
# ENDE ALLER ANPASSUNGEN, HIER DRUNTER NICHT MEHR EDITIEREN! #
##############################################################

# possible needed once, when no var/status.dat is around 
#our %ST 			= (SENDER_RUN => 1, SENDER_TS => 0, RECEIVER_IN => undef); 

our %ST 			= read_status();
our %NODES			= get_nodes();

#
# gemeinsame Funktionen (pha-*.pl)
#

sub write_status {
	Storable::lock_nstore \%ST, $CONFIG{INSTALLDIR}.'/var/status.dat';
}
sub read_status {
	my $ref = Storable::lock_retrieve $CONFIG{INSTALLDIR}.'/var/status.dat';
	return %{$ref}; 
}

sub write_conf {
	Storable::lock_nstore \%CONFIG, $CONFIG{INSTALLDIR}.'/var/conf.dat';
}
sub read_conf {
	my $ref = Storable::lock_retrieve $CONFIG{INSTALLDIR}.'/var/conf.dat';
	return %{$ref}; 
}
sub mylog {
        my $msg = shift || "(null)";
        my $level = shift || "0";
        my $logf;

        if ($0 =~ /(pha-)(.*)\.pl/) {
                $logf = $CONFIG{LOGPATH}.".$2";
        }

        my $ts = scalar localtime;
        if ($CONFIG{DAEMON} == 0) {
                print STDERR "[LOG] $ts: $msg\n";
        } else {
                open (LOG, ">>", $logf) or die $!;
                        print LOG "$ts: $msg\n";
                close (LOG);
        }
}
sub read_configfile {
	my $file = shift;

	my %conf;

	open(FH, "<", $file) or die $!;
	while(<FH>) {
		if ($_ !~ /(.*)=(.*)/) {next;}
		if ($_ =~ /^#/) {next;}
		my ($key, $val) = split(/=/,$_);
		$val =~ s/"|'//;
		$val =~ s/\r|\n//;
		my @v = split(/ /,$val);
		if (@v > 1) {
			$conf{$key} = [@v];
		} else {
			$conf{$key} = $v[0];
		}
	}
	close(FH);

#	foreach (keys (%CONFIG)) {
#	        if (ref $CONFIG{$_} ) {
#                	print $_."=";
#        	        foreach $v (@{$CONFIG{$_}}) {
#	                        print "$v ";
#                	}
#        	        print "\n";
#	        } else {
#                	print $_."=".$CONFIG{$_}."\n";
#        	}
#	}

	return %conf; 
}

sub icmp_ping {
        my $host = shift;
        return -1 unless defined $host;

        # Like tcp protocol, but with many hosts
        my $p = Net::Ping->new("icmp");
        $p->hires(1);
        my ($ret, $duration, $ip) = $p->ping($host, $CONFIG{PINGTIMEOUT});
        my $ok = $ret || "-1";
        if ($ok != -1) {
                return sprintf ("%.2f", 1000 * $duration);
        } else {
                return -1;
        }
}

sub check_defaultroute {
        my $gw = shift || $CONFIG{GW};
        my $ret = `ip r s|grep $gw |grep default 2>/dev/null`;
        chomp($ret);
        #mylog "check_defaultroute() $ret";
        if ($ret) { return 1; } else { return undef;}
}

sub check_res {
        # Check Ressources with the corresponding script action "check"
        foreach my $key (keys %CONFIG) {
		if ($key !~ /RES_(.*)/) {next;}
		my $res = $1;
                my $opt = $CONFIG{$key};

                my $r = system("$CONFIG{INSTALLDIR}/res/$res check $opt");
		%ST = read_status();
                if ($r != 0) {
                        mylog "check_res(): Ressource '$CONFIG{INSTALLDIR}/res/$res' is DOWN";
                        $ST{"RES_$res"} = "DOWN";
                        $ST{"STATUS"} = "OFFLINE";
                } else {
                        mylog "check_res(): Ressource '$CONFIG{INSTALLDIR}/res/$res' is UP";
                        $ST{"RES_$res"} = "UP";
                        $ST{"STATUS"} = "ONLINE";
                }
		write_status();
        }
}

sub get_nodes {
	my $i = 0;
	my %nodes = ();
	foreach my $n (@{$CONFIG{NODES}}) {
		if ($n eq hostname()) {
			$nodes{'local'} = $i;
			print STDERR "[DBG] local id: $i   local hostname: $n\n" if ($CONFIG{DEBUG} == 1);
		} else {
			$nodes{'peer'} = $i;
			print STDERR "[DBG] peer  id: $i   peer  hostname: $n\n" if ($CONFIG{DEBUG} == 1);
		}
		#$nodes{$n} = $i;
		$i++;
	}
	# neede some place to make sure status.dat is actually there, before the pha-* runs
	write_status();
	return %nodes;
}

sub get_peer_hostname {
	return $CONFIG{NODES}[$NODES{peer}];
}
sub get_local_hostname {
	return $CONFIG{NODES}[$NODES{peer}];
}
sub get_pid {
	my $prg = shift;
	my $file = undef;

	if ($prg =~ /sender|receiver|cli/) {
		$file = $CONFIG{INSTALLDIR}."/var/run/$prg";
	} else {
		$0 =~ /(pha-)(.*)\.pl/;
		$file = $CONFIG{INSTALLDIR}."/var/run/$2";
	}
	open (FH,"<",$file) or mylog $!;
	my $pid = <FH>;
	close (FH);

	return $pid;
}
sub stop_service {
	my $srv = shift || return;
	mylog "stop_service: $srv  pid: ".get_pid($srv);
	kill 9, get_pid($srv);
}
sub myusleep($) {
	my $msec = shift;
	$msec = $msec / 1000;
	select(undef, undef, undef, $msec);
}

#
# Old and deprecated
#
sub var_getcopy {
	my %H;
	my ($key,$val)=("","");
	
	# TIE datafile
	tie(%H, 'SDBM_File', "$CONFIG{INSTALLDIR}/var/hash", O_RDWR|O_CREAT, 0666) or die "Couldn't tie SDBM file '$CONFIG{INSTALLDIR}/var/hash': $!; aborting";
	# Debug OUT PUT
	if ($CONFIG{DEBUG}) {
		while (($key,$val) = each %H) {
			print STDERR $key, ' = ', $val, "\n";
		}
	}
	# Copy data
	my %h = %H;
	# release TIE
	untie(%H);
	
	return %h;
}

sub var_get {
	my $key = shift;
        my $val = undef;
	my %H = ();

	if (!$key) {
		mylog "var_get() empty key";
		return "";
	}
	# TIE datafile
        tie(%H, 'SDBM_File', "$CONFIG{INSTALLDIR}/var/hash", O_RDWR|O_CREAT, 0666) or die "Couldn't tie NDBM file '$CONFIG{INSTALLDIR}/var/hash': $!; aborting";
	$val = $H{$key};

	# release TIE
        untie(%H);

	return $val || undef;
}

sub var_add {
	my $nKEY = shift;
	my $nVAL = shift||"(null)";

	return -1 unless defined ($nKEY || $nVAL);

	my %H = ();
	my $k = undef;
	my ($key,$val)=("","");
	
	tie(%H, 'SDBM_File', "$CONFIG{INSTALLDIR}/var/hash", O_RDWR|O_CREAT, 0666) or die "Couldn't tie NDBM file '$CONFIG{INSTALLDIR}/var/hash': $!; aborting";

	if ($nKEY) {
		$k = $nKEY;
	} else {
		$k = keys %H;
	}

	$H{$k} = $nVAL;
	#mylog "var_add() (nKEY=VAL: '$k'=>'$nVAL')";
		
	# Debug OUT PUT
	if ($CONFIG{DEBUG}) {
		while (($key,$val) = each %H) {
			mylog $key.' = '.$val;
		}
	}
	untie(%H);
	
	return 0;		
}

sub var_del {
	my $dKEY = shift;
	my $dVAL = shift || "(null)";
	
	return -1 unless defined ($dKEY || $dVAL);

	my %H=();
	my ($key,$val)=("","");
	my $k = undef;
		
	tie(%H, 'SDBM_File', "$CONFIG{INSTALLDIR}/var/hash", O_RDWR|O_CREAT, 0666) or die "Couldn't tie NDBM file '$CONFIG{INSTALLDIR}/var/hash': $!; aborting";
	
	if ($dKEY) {
		#mylog "var_del() key: $dKEY";
		delete ($H{$dKEY});
	} else {
		foreach $k (sort keys %H) {
			if ($H{$k} eq $dVAL) {
				mylog " var_del() H{$k}: $H{$k} found the one to delete (dVAL: $dVAL)";
				delete ($H{$k});
			}
		}
	}
	untie(%H);
	
	return 0;
}

sub var_delall {
	my %H=();
        my ($key,$val)=("","");
        my $k = undef;

        tie(%H, 'SDBM_File', "$CONFIG{INSTALLDIR}/var/hash", O_RDWR|O_CREAT, 0666) or die "Couldn't tie NDBM file '$CONFIG{INSTALLDIR}/var/hash': $!; aborting";
	%H = ();
        untie(%H);
        return 0;
}

1;

