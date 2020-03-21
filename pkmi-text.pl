#!/usr/bin/perl

use strict;
use warnings;
use diagnostics;

use Data::Dumper;

use Curses::UI;

# all info will be stored here
my $moduleList = {};

# Init module data in main structure
sub initModuleData {
	my ($modname, $modtype) = @_;
	$moduleList->{$modname} = {
		type => "$modtype",
		desc => "",
		params => {},
	} unless defined $moduleList->{$modname};
}

# Get loaded modules
sub getLoadedModules {
	my $fh;
	open $fh, "<", "/proc/modules" or $fh = undef;
	# Try to use lsmod util
	open $fh, "-|", "lsmod" or $fh = undef unless $fh;
	return 0 unless $fh;
	if ($fh) {
		while (my $modname = <$fh>) {
			next if $modname =~ m{Module.*Size.*Used}i;
			$modname =~ s|^([^ ]+).*$|$1|is;
			initModuleData($modname, "loaded");
		}
		close $fh;
	}
}

# Get all from /sys
sub getFromSys {
	# if /sys mounted
	if ( -d "/sys/module") {
		opendir D, "/sys/module";
		while (my $modname = readdir D) {
			# If directory and not "up-level"
			if ( -d "/sys/module/$modname" && $modname !~ m{^\.\.?$} ) {
				initModuleData($modname, "built-in");
				# if module have params
				if ( -d "/sys/module/$modname/parameters" ) {
					opendir DP, "/sys/module/$modname/parameters";
					while (my $param = readdir DP) {
						if ( -f "/sys/module/$modname/parameters/$param" ) {
							$moduleList->{$modname}->{params}->{$param} = {
								value => "",
								desc => "",
							};
							my $val;
							{
								#print "Reading /sys/module/$modname/parameters/$param\n";
								open PV, "<", "/sys/module/$modname/parameters/$param" or next;
								local $/ = undef;
								$val = <PV>;
								close PV;
							}
							chomp $val if $val;
							$moduleList->{$modname}->{params}->{$param}->{value} = $val;
						}
					}
					closedir DP;
				}
			}
		}
		closedir D;
	}
}

# Try to load module list
eval {
	getLoadedModules();
	getFromSys();


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
my $CUI = Curses::UI->new(
	-clear_on_exit => 1,
	-color_support => 1,
	-debug => 0
);

# Create Menu
my $mainMenu = $CUI->add(
	"menu", "Menubar",
	-menu => [
		{
			-label => "File",
			-submenu => [
				{
					-label => "Quit",
					-value => \&command_quit
				}
			],
		},
		{
			-label => "Help",
			-submenu => [
				{
					-label => "Help",
					-value => \&command_help
				},
				{
					-label => "About",
					-value => \&command_about
				}
			],
		}
	],
	-fg => "blue",
);

# keyboard shortcuts
$CUI->set_binding(sub {$mainMenu->focus()}, 'm');
$CUI->set_binding(\&command_quit, 'q');
$CUI->set_binding(\&command_help, 'h');

# Create mainwindow
my $mainWindow = $CUI->add(
	'mainWin',
	'Window',
	-y => 1,
	-bg => "black",
	-fg => "green"
);

# List of modules
my $listMod = $mainWindow->add(
	'listModules',
	'Listbox',
	-title => sprintf("% -18s %s", "Module", "Description"),
	-titlefullwidth => 1,
	-onselchange => \&select_module,
	-width => int $mainWindow->width()/2,
	-border => 1,
	-vscrollbar => 1,
	-values => [ sort keys %$moduleList ],
	-labels => { map { $_, sprintf(" % -18s %s", substr($_, 0, 18), $moduleList->{$_}->{desc}); } keys %$moduleList },
);

# List of module params
my $listParams = $mainWindow->add(
	'listParameters',
	'Listbox',
	-title => sprintf("% -12s   % -8s %s", "Param", "Value", "Description"),
	-titlefullwidth => 1,
	-width => int $mainWindow->width()/2,
	-x => int $mainWindow->width()/2,
	-border => 1,
	-vscrollbar => 1,
	-values => [ ]
);

# Start UI 
$listMod->focus;
$CUI->mainloop;

# event handler: select module in list
sub select_module {
	my $moduleName = $listMod->get_active_value();
	if (defined($moduleList->{$moduleName})) {
		$listParams->values([ sort keys %{$moduleList->{$moduleName}->{params}} ]);
		$listParams->labels({
			map {
				my $item = $moduleList->{$moduleName}->{params}->{$_};
				$_,
				sprintf(
					" % -12s   % -8s %s",
					substr($_, 0, 12),
					substr($item->{value} ? $item->{value} : '[NULL]', 0, 8),
					$item->{desc} ? $item->{desc} : ''
				)
			} %{$moduleList->{$moduleName}->{params}}
		});
	}
	else {
		$listParams->values([]);
		$listParams->labels({});
	}
	$CUI->draw();
}

# Event handler: exit (menu, shortcut)
sub command_quit {
	$CUI->mainloopExit;
}

# Event handler: about (menu)
sub command_about {
	$CUI->dialog(
		-message => "With this tool you can get info about loaded kernel modules",
		-title => "About",
		-buttons => [{
			-label => "< OK >",
			-value => 1,
			-shortcut => "o"
		}]
	);
}

# Event handler: help (menu, shortcut)
sub command_help {
	$CUI->dialog(
		-message => "M: Activate menu\nQ: Quit\nH: This help",
		-title => "Help",
		-buttons => [{
			-label => "< OK >",
			-value => 1,
			-shortcut => "o"
		}]
	);
}
