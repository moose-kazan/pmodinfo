#!/usr/bin/perl

use strict;
use warnings;
use diagnostics;

use Tk;
use Tk::HList;

use Data::Dumper;

# all info will be stored here
my $moduleList = {};

# Try to load module list
eval {
	# if /sys mounted
	if ( -d "/sys/module") {
		opendir D, "/sys/module";
		while (my $modname = readdir D) {
			# If directory and not "up-level"
			if ( -d "/sys/module/$modname" && $modname !~ m{^\.\.?$} ) {
				$moduleList->{$modname} = {
					type => "built-in",
					desc => "",
					params => {},
				};
				# if module have params
				if ( -d "/sys/module/$modname/parameters" ) {
					opendir DP, "/sys/module/$modname/parameters";
					while (my $param = readdir DP) {
						if ( -f "/sys/module/$modname/parameters/$param" ) {
							my $val;
							{
								#print "Reading /sys/module/$modname/parameters/$param\n";
								open PV, "<", "/sys/module/$modname/parameters/$param";
								local $/ = undef;
								$val = <PV>;
								close PV;
							}
							chomp $val;
							$moduleList->{$modname}->{params}->{$param} = {
								value => $val,
								desc => "",
							}
						}
					}
					closedir DP;
				}
			}
		}
		closedir D;
	}
	# If /proc mounted
	if ( -f "/proc/modules") {
		open F, "<", "/proc/modules";
		while (my $modname = <F>) {
			$modname =~ s|^([^ ]+).*$|$1|is;
			$moduleList->{$modname}->{type} = "loaded";
		}
		close F;
	}
	
	# find loaded modules and split it for chunks
	my $chunks = [];
	my $chunk = [];
	foreach my $modname (keys %{$moduleList}) {
		if ($moduleList->{$modname}->{type} eq "loaded") {
			push @$chunk, $modname;
			if (@$chunk == 10) {
				push @$chunks, $chunk;
				$chunk = [];
			}
		}
	}
	push @$chunks, $chunk if @$chunk > 0;
	
	# load module info
	foreach my $chunk (@{$chunks}) {
		#my $modname;
		# Run modinfo
		open F, "-|", "modinfo " . join(" ", @$chunk);
		my $modinfoDataLine;
		{
			$/ = undef;
			$modinfoDataLine = <F>;
		}
		my @modinfoData = split /filename: /is, $modinfoDataLine;
		foreach my $dataLine (@modinfoData) {
			# Try to find module name
			if ($dataLine =~ m{name: +(.*?)(\n|$)}is) {
				my $modname = $1;
				# Something wrong
				if (!defined($moduleList->{$modname})) {
					next;
				}
				# Parse other data
				foreach my $line (split /\n/, $dataLine) {
					if ($line =~ m|^([^:]+): +(.*)$|is) {
						my $key = $1;
						my $val = $2;
						chomp($val);
						if ($key eq "description") {
							$moduleList->{$modname}->{desc} = $val;
						}
						elsif ($key eq "parm") {
							if ($val =~ m|^([^:]+):(.*)$|is) {
								$moduleList->{$modname}->{params}->{$1}->{desc} = $2;
							}		
						}
					}
				}
			}
		}
		close F;
	}
	
	#print Dumper($moduleList);
	
};
if (my $error = $@) {
	print "Can't load module list!\n";
	exit(1);
}


#print Dumper($moduleList);
#exit();

# Build UI
my $mw = MainWindow->new( -title => "perl Module Info" );
$mw->geometry("720x400");
my $listMod = $mw->HList(-columns => 3, -header => 1, -itemtype => "text", -selectmode => "browse")->pack( -side => "left", -expand => 1, -fill => "both" );
my $listParam = $mw->HList(-columns => 3, -header => 1, -itemtype => "text")->pack( -side => "right", -expand => 1, -fill => "both" );
my $sBar= $mw->Scrollbar(-command => ["yview", $listMod])->pack(-side => 'right', -fill => 'y');
$listMod->configure(-yscrollcommand => ["set", $sBar]);
$listMod->configure( -font => [ -size => 12 ] );
$listParam->configure( -font => [ -size => 12 ] );

# Put initial Data
$listMod->headerCreate(0, -text => "Module");
$listMod->headerCreate(1, -text => "Type");
$listMod->headerCreate(2, -text => "Description");

$listParam->headerCreate(0, -text => "Param");
$listParam->headerCreate(1, -text => "Value");
$listParam->headerCreate(2, -text => "Description");

#$listMod->insert("end", sort(keys(%{$moduleList})));
foreach my $modname (sort(keys(%{$moduleList}))) {
	$listMod->add($modname);
	$listMod->itemCreate($modname, 0, -text => $modname);
	$listMod->itemCreate($modname, 1, -text => $moduleList->{$modname}->{type});
	$listMod->itemCreate($modname, 2, -text => $moduleList->{$modname}->{desc});
}



# Handle events
$listMod->configure( -browsecmd => sub{
	my $modname = shift;
	$listParam->delete("all");
	foreach my $param (keys %{$moduleList->{$modname}->{params}}) {
		$listParam->add($param);
		$listParam->itemCreate($param, 0, -text => $param);
		$listParam->itemCreate($param, 1, -text => $moduleList->{$modname}->{params}->{$param}->{value});
		$listParam->itemCreate($param, 2, -text => $moduleList->{$modname}->{params}->{$param}->{desc});
	}
});

MainLoop;
