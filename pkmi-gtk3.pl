#!/usr/bin/perl

use strict;
use warnings;
use diagnostics;

use Data::Dumper;

use Gtk3 '-init';
use Glib qw/TRUE FALSE/;

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

my $modelMod = Gtk3::ListStore->new(
		'Glib::String',
		'Glib::String',
		'Glib::String',
	);
foreach my $modName (sort keys(%$moduleList)) {
	my $iter = $modelMod->append();
	$modelMod->set(
			$iter,
			0, $modName,
			1, $moduleList->{$modName}->{type},
			2, $moduleList->{$modName}->{desc}
		);
}
my $modelParam = Gtk3::ListStore->new(
		'Glib::String',
		'Glib::String',
		'Glib::String',
	);

my $MainWindow = Gtk3::Window->new();
$MainWindow->set_title("Perl Kernel Module Info");

my $paned = Gtk3::HPaned->new;
my $listMod = Gtk3::TreeView->new($modelMod);
my $listParam = Gtk3::TreeView->new($modelParam);

foreach (['Module', 0], ['Type', 1], ['Description', 2]) {
	$listMod->append_column(Gtk3::TreeViewColumn->new_with_attributes(
			$_->[0],
			Gtk3::CellRendererText->new,
			text => $_->[1]
		));
}

foreach (['Param', 0], ['Value', 1], ['Description', 2]) {
	$listParam->append_column(Gtk3::TreeViewColumn->new_with_attributes(
			$_->[0],
			Gtk3::CellRendererText->new,
			text => $_->[1]
		));
}

my $scroll1 = Gtk3::ScrolledWindow->new;
$scroll1->set_size_request(360, -1);
$scroll1->add($listMod);
$paned->pack1($scroll1, 1, 0);

my $scroll2 = Gtk3::ScrolledWindow->new;
$scroll2->set_size_request(360, -1);
$scroll2->add($listParam);
$paned->pack2($scroll2, 1, 0);


# Create main menu
my $mainMenu = Gtk3::MenuBar->new;
my $menuFile = Gtk3::MenuItem->new('_File');
my $subMenuFile = Gtk3::Menu->new;
my $menuExit = Gtk3::MenuItem->new('Exit');
$menuExit->signal_connect(activate => sub {Gtk3->main_quit});
$subMenuFile->append($menuExit);
$menuFile->set_submenu($subMenuFile);
$mainMenu->append($menuFile);

my $menuHelp = Gtk3::MenuItem->new('_Help');
my $subMenuHelp = Gtk3::Menu->new;
my $menuAbout = Gtk3::MenuItem->new('About');
$menuAbout->signal_connect(activate => sub {
		my $dialog = Gtk3::MessageDialog->new(
				$MainWindow,
				'modal',
				'info',
				'close',
				'With this tool you can get info about loaded kernel modules'
			);
		$dialog->run;
		$dialog->destroy;
	});
$subMenuHelp->append($menuAbout);
$menuHelp->set_submenu($subMenuHelp);
$mainMenu->append($menuHelp);

# Pack UI
my $vbox = Gtk3::VBox->new;
$vbox->pack_start($mainMenu, 0, 0, 0);
$vbox->add($paned);


$MainWindow->add($vbox);
$MainWindow->set_default_size(720, 400);

$MainWindow->signal_connect(destroy => sub {Gtk3->main_quit});
$listMod->get_selection->signal_connect (changed => \&selectModule);

$MainWindow->show_all;

Gtk3->main;

sub selectModule {
	my $selection = $listMod->get_selection();
	my ($modelM, $iterM) = $selection->get_selected();
	my $modName = $modelM->get_value($iterM, 0);
	$modelParam->clear();
	foreach (sort keys %{$moduleList->{$modName}->{params}}) {
		my $iter = $modelParam->append();
		$modelParam->set(
				$iter,
				0, $_,
				1, $moduleList->{$modName}->{params}->{$_}->{value},
				2, $moduleList->{$modName}->{params}->{$_}->{desc}
			);
	}
}