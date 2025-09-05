#!/usr/bin/perl

use strict;
use warnings;
use diagnostics;

use Data::Dumper;

use Curses::UI;
use File::Basename;

use lib dirname(__FILE__) . "/libs";
use pmodinfo;

my $dataLoader = pmodinfo->new();

$dataLoader->loadData();

my $moduleList = $dataLoader->getData();


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
