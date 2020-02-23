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
		my $modname;
		# RUn modinfo
		open F, "-|", "modinfo " . join(" ", @$chunk);
		# Parsing output of modinfo
		while (my $line = <F>) {
			if ($line =~ m|^([^:]+): +(.*)$|is) {
				my $key = $1;
				my $val = $2;
				chomp($val);
				# Module name
				if ($key eq "name") {
					# If name is outside our data - it's very strange
					$modname = defined($moduleList->{$val}) ? $val : undef;
				}
				# Module param
				elsif ($key eq "parm" && $modname) {
					#print "Key: $key\nVal: $val\n\n";
					if ($val =~ m|^([^:]+):(.*)$|is) {
						$moduleList->{$modname}->{params}->{$1}->{desc} = $2;
					}
				}
				# Module description
				elsif ($key eq "description" && $modname) {
					$moduleList->{$modname}->{desc} = $val;
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

# Build UI
my $mw = MainWindow->new( -title => "perl Module Info" );
$mw->geometry("720x400");
my $lBox = $mw->Listbox()->pack( -side => "left", -expand => 1, -fill => "both" );
my $hList = $mw->HList(-columns => 3, -header => 1, -itemtype => "text")->pack( -side => "right", -expand => 1, -fill => "both" );
my $sBar= $mw->Scrollbar(-command => ["yview", $lBox])->pack(-side => 'right', -fill => 'y');
$lBox->configure(-yscrollcommand => ["set", $sBar]);
$lBox->configure( -font => [ -size => 12 ] );
$hList->configure( -font => [ -size => 12 ] );

# Put initial Data
$lBox->insert("end", sort(keys(%{$moduleList})));
$hList->headerCreate(0, -text => "Param");
$hList->headerCreate(1, -text => "Value");
$hList->headerCreate(2, -text => "Description");

# Handle events
$lBox->bind('<<ListboxSelect>>' => sub {
	my $modname = $lBox->get($lBox->curselection);
	$hList->delete("all");
	foreach my $param (keys %{$moduleList->{$modname}->{params}}) {
		$hList->add($param);
		$hList->itemCreate($param, 0, -text => $param);
		$hList->itemCreate($param, 1, -text => $moduleList->{$modname}->{params}->{$param}->{value});
		$hList->itemCreate($param, 2, -text => $moduleList->{$modname}->{params}->{$param}->{desc});
	}
});

MainLoop;
