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
@EXPORT 	= qw( checkconfig mylog var_getcopy var_get var_add var_del var_delall write_status read_status write_conf read_conf myusleep get_peer_hostname get_local_hostname %RES %CONFIG %ST %NODES get_pid stop_service start_service icmp_ping check_link_local check_defaultroute check_res stop_res_cli start_res_cli update_status);
@EXPORT_OK 	= qw( checkconfig mylog var_getcopy var_get var_add var_del var_delall write_status read_status write_conf read_conf myusleep get_peer_hostname get_local_hostname %RES %CONFIG %ST %NODES get_pid stop_service start_service icmp_ping check_link_local check_defaultroute check_res stop_res_cli start_res_cli update_status); 

##########################################
# ggf. Konfigurations Dateipfad anpassen #
##########################################

our %CONFIG		= read_configfile("/opt/pha/etc/config");

##############################################################
# ENDE ALLER ANPASSUNGEN, HIER DRUNTER NICHT MEHR EDITIEREN! #
##############################################################

# possible needed once, when no var/status.dat is around 
our %ST 	= ( SENDER_RUN => 1, SENDER_TS => 0, RECEIVER_IN => undef, STATUS => 'PROGRESS' ); 

#if (-f $CONFIG{INSTALLDIR}.'/var/status.dat') {
#	%ST = read_status();
#}

our %NODES	= get_nodes();

#
# gemeinsame Funktionen (pha-*.pl)
#

sub write_status {
	Storable::lock_store \%ST, $CONFIG{INSTALLDIR}.'/var/status.dat';
}
sub read_status {
	my $ref = Storable::lock_retrieve $CONFIG{INSTALLDIR}.'/var/status.dat';
	return %{$ref}; 
}
sub update_status {
	my $nref = shift || return;

	%ST = read_status();	
	foreach my $k (keys %$nref) {
		# die ganze logging un concat sachen machten warnungen 
		# die einfache zuweisung ist kein problem!
		$ST{$k} = $nref->{$k};
		
		# uninitialised warnung entfernen...
		#$ST{$k} = '' unless exists $ST{$k};
		# Update des status hash'es
		#if ($ST{$k} ne $nref->{$k}) {
		#	$ST{$k} = $nref->{$k};
		#	print STDERR "update_status key:$k val:".$nref->{$k}."\n";
		#}
	}
	write_status();
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
	my %st = ();
	my $down = 0;
	my $log = undef;
        foreach my $key (keys %CONFIG) {
		if ($key !~ /RES_(.*)/) {next;}
		my $res = $1;
		my $opt = undef;
		$opt = join (" ", @{$CONFIG{$key}}) if ref($CONFIG{$key});;
		$opt = $CONFIG{$key} if not ref($CONFIG{$key});
		
                my $r = system("$CONFIG{INSTALLDIR}/res/$res check $opt");
                if ($r != 0) {
                        mylog "check_res(): Ressource '$CONFIG{INSTALLDIR}/res/$res' is DOWN";
                        $st{"RES_$res"} = "DOWN";
			$down += 1;
                } else {
                        mylog "check_res(): Ressource '$CONFIG{INSTALLDIR}/res/$res' is UP";
                        $st{"RES_$res"} = "UP";
                }
		update_status(\%st);	
        }
	return $down;
}

sub start_res_cli {
	my $res = shift || return -1;
	
	my $key = "RES_".$res;
        my $opt = undef;
        $opt = join (" ", @{$CONFIG{$key}}) if ref($CONFIG{$key});;
        $opt = $CONFIG{$key} if not ref($CONFIG{$key});
        my $r = system("$CONFIG{INSTALLDIR}/res/$res start $opt");
	print "$CONFIG{INSTALLDIR}/res/$res start $opt    res:$r\n" if ($CONFIG{DEBUG} == 1); 
        if ($r != 0) { mylog "start_res_cli() [ERR] starting service $res" }
	else { mylog "start_res_cli() [OK]\n"; }
}
sub stop_res_cli {
	my $res = shift || return -1;
	
	my $key = "RES_".$res;
        my $opt = undef;
        $opt = join (" ", @{$CONFIG{$key}}) if ref($CONFIG{$key});;
        $opt = $CONFIG{$key} if not ref($CONFIG{$key});
        my $r = system("$CONFIG{INSTALLDIR}/res/$res stop $opt");
	print "$CONFIG{INSTALLDIR}/res/$res stop $opt   ret:$r\n" if ($CONFIG{DEBUG} == 1);
        if ($r != 0) { mylog "stop_res_cli() [ERR] stoping service $res" }
	else { mylog "stop_res_cli() [OK]\n"; }
}

sub get_nodes {
	my $i = 0;
	my %nodes = ();
	foreach my $n (@{$CONFIG{NODES}}) {
		if ($n eq hostname()) {
			$nodes{'local'} = $i;
			print STDERR "[DBG] local id: $i   local hostname: $n\n" if ($CONFIG{DEBUG});
		} else {
			$nodes{'peer'} = $i;
			print STDERR "[DBG] peer  id: $i   peer  hostname: $n\n" if ($CONFIG{DEBUG});
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
	return $CONFIG{NODES}[$NODES{local}];
}
sub get_pid {
	my $prg = shift;
	my $file = undef;
	my $pid = 0;

	if ($prg =~ /sender|receiver|cli|supervise/) {
		$file = $CONFIG{INSTALLDIR}."/var/run/$prg";
	} else {
		$0 =~ /(pha-)(.*)\.pl/;
		$file = $CONFIG{INSTALLDIR}."/var/run/$2";
	}
	if (-f $file) {
		open (FH,"<",$file) or mylog $!;
		$pid = <FH>;
		close (FH);
	}
	return $pid;
}
sub stop_service {
	my $srv = shift || return;
	mylog "stop_service: $srv  pid: ".get_pid($srv);
	#kill 9, get_pid($srv); 9 == KILL onyl in INT sig cleanup is done
	#kill 2, get_pid($srv);
	my $pid =  get_pid($srv);
	if ($pid != 0) {
		kill 'INT', $pid;
	}
}
sub start_service {
	my $srv = shift || return;
	my $pid =  get_pid($srv);
	if ($pid) {
		mylog "start_service: ERROR service \"$srv\" allready running!";
		return;
	}
	mylog "start_service: $srv";
	my $r = system($CONFIG{INSTALLDIR}."/bin/pha-$srv.pl");
	mylog "start_service: system ret: $r";
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

