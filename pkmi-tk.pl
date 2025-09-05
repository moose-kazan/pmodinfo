#!/usr/bin/perl

use strict;
use warnings;
use diagnostics;

use Tk;
use Tk::HList;

use Data::Dumper;
use File::Basename;

use lib dirname(__FILE__) . "/libs";
use pmodinfo;

my $dataLoader = pmodinfo->new();

$dataLoader->loadData();

my $moduleList = $dataLoader->getData();

#print Dumper($moduleList);
#exit();

# Build UI
my $mw = MainWindow->new( -title => "perl Kernel Module Info" );
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
	foreach my $param (sort keys %{$moduleList->{$modname}->{params}}) {
		$listParam->add($param);
		$listParam->itemCreate($param, 0, -text => $param);
		$listParam->itemCreate($param, 1, -text => $moduleList->{$modname}->{params}->{$param}->{value});
		$listParam->itemCreate($param, 2, -text => $moduleList->{$modname}->{params}->{$param}->{desc});
	}
});

MainLoop;
