package pha;

use strict;
use warnings;

use Storable;
use Fcntl;
use SDBM_File;
use Sys::Hostname qw(hostname);
use File::Basename qw(basename);
use Net::Ping;

# Export in Callernamespace (@EXPORT)  
require Exporter;
use vars qw( @ISA @EXPORT @EXPORT_OK );
@ISA = qw(Exporter AutoLoader);
@EXPORT 	= qw( checkconfig mylog var_getcopy var_get var_add var_del var_delall write_status read_status write_conf read_conf myusleep get_peer_hostname get_local_hostname %RES %CONFIG %ST %NODES get_pid stop_service start_service icmp_ping check_link_local check_defaultroute check_res stop_res_cli start_res_cli update_status);
@EXPORT_OK 	= qw( checkconfig mylog var_getcopy var_get var_add var_del var_delall write_status read_status write_conf read_conf myusleep get_peer_hostname get_local_hostname %RES %CONFIG %ST %NODES get_pid stop_service start_service icmp_ping check_link_local check_defaultroute check_res stop_res_cli start_res_cli update_status); 

sub mylog;

##########################################
# ggf. Konfigurations Dateipfad anpassen #
##########################################

our %CONFIG		= read_configfile("/opt/pha/etc/config");

##############################################################
# ENDE ALLER ANPASSUNGEN, HIER DRUNTER NICHT MEHR EDITIEREN! #
##############################################################

# possible needed once, when no var/status.dat is around 
our %ST 	=();
if (-f $CONFIG{INSTALLDIR}.'/var/status.dat') {
	%ST = read_status();
} 

our $NAME = basename($0);
if ($NAME eq "pha-sender.pl") {
	$ST{SENDER_RUN} = 1; 
	write_status(\%ST);
} elsif ($NAME eq "pha-receiver.pl") {
	$ST{RECEIVER_IN} = undef; 
	write_status(\%ST);
} elsif ($NAME eq "pha-supervise.pl") {
	$ST{SUPERVISE} = 1; 
	write_status(\%ST);
} elsif ($NAME eq "pha-cli.pl") {
	$ST{CLI} = 1;
	write_status(\%ST);
} else {
	mylog "[ERR] pha.pm init \$NAME : $NAME ($0)";
}


our %NODES	= get_nodes();


#
# common functions (pha-*.pl)
#

sub write_status {
	my $ref = shift || return;
	return unless ref($ref);
	Storable::lock_nstore $ref, $CONFIG{INSTALLDIR}.'/var/status.dat';
}
sub read_status {
	my $ref = Storable::lock_retrieve $CONFIG{INSTALLDIR}.'/var/status.dat';
	return %{$ref}; 
}
sub update_status {
	my $nref = shift || return;

	my %st = read_status();	
	foreach my $k (keys %$nref) {
		# update %st with supported dataref
		$st{$k} = $nref->{$k};
	}
	write_status(\%st);
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
# check all resopurces, and return number of downs
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
                        mylog "check_res(): Ressource '$CONFIG{INSTALLDIR}/res/$res' is DOWN" if ($CONFIG{DEBUG}>0);
                        $st{"RES_$res"} = "DOWN";
			$down += 1;
                } else {
                        mylog "check_res(): Ressource '$CONFIG{INSTALLDIR}/res/$res' is UP" if ($CONFIG{DEBUG}>0);
                        $st{"RES_$res"} = "UP";
                }
		update_status(\%st);	
        }
	return $down;
}

# start resource script
sub start_res_cli {
	my $res = shift || return -1;
	
	my $key = "RES_".$res;
        my $opt = undef;
        $opt = join (" ", @{$CONFIG{$key}}) if ref($CONFIG{$key});;
        $opt = $CONFIG{$key} if not ref($CONFIG{$key});
        my $r = system("$CONFIG{INSTALLDIR}/res/$res start $opt");
	print "$CONFIG{INSTALLDIR}/res/$res start $opt    res:$r\n" if ($CONFIG{DEBUG} == 1); 
        if ($r != 0) { 
		mylog "start_res_cli() [ERR] starting service $res" 
	} else { 
		mylog "start_res_cli() [OK] started $res"; 
		update_status({"RES_$res"=>"UP"}); 
	}
}
# stop resource script
sub stop_res_cli {
	my $res = shift || return -1;
	
	my $key = "RES_".$res;
        my $opt = undef;
        $opt = join (" ", @{$CONFIG{$key}}) if ref($CONFIG{$key});;
        $opt = $CONFIG{$key} if not ref($CONFIG{$key});
        my $r = system("$CONFIG{INSTALLDIR}/res/$res stop $opt");
	print "$CONFIG{INSTALLDIR}/res/$res stop $opt   ret:$r\n" if ($CONFIG{DEBUG} == 1);
        if ($r != 0) { 
		mylog "stop_res_cli() [ERR] stoping service $res";
	} else { 
		mylog "stop_res_cli() [OK] stopped $res"; 
		update_status({"RES_$res"=>"DOWN"});
	}
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
# stop pha daemon
sub stop_service {
	my $srv = shift || return;
	mylog "stop_service: $srv  pid: ".get_pid($srv);
	my $pid =  get_pid($srv);
	kill('INT', $pid) if ($pid != 0);
}
# start pha daemon
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

# sleep param1 millisec
sub myusleep($) {
	my $msec = shift;
	$msec = $msec / 1000;
	select(undef, undef, undef, $msec);
}

