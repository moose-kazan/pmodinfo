package pmodinfo;

sub new {
    my $class = shift;
    return bless { moduleList => {} }, $class;
}

sub _addModuleInfo {
    my ($self, $modName, $modType, $modDesc) = @_;
    $self->{moduleList}->{$modName} = {
        type => $modType,
        desc => $modDesc,
        params => {}
    };
}

sub _addModuleParam {
    my ($self, $modName, $paramName, $paramValue, $paramDesc) = @_;
    $self->{moduleList}->{$modName}->{params}->{$paramName} = {
        value => $paramValue,
        desc => $paramDesc,
    };
}

sub _getModulesLoaded {
    my $self = shift;
    my $fh;
    open $fh, "<", "/proc/modules" or $fh = undef;
    # Try to use lsmod util
    open $fh, "-|", "lsmod" or $fh = undef unless $fh;
    return 0 unless $fh;
    if ($fh) {
        while (my $modname = <$fh>) {
            next if $modname =~ m{Module.*Size.*Used}i;
            $modname =~ s|^([^ ]+).*$|$1|is;
            $self->_addModuleInfo($modname, "loaded", "");
        }
        close $fh;
    }
}

sub _getModulesFromSystem {
    my $self = shift;
	# if /sys mounted
	if ( -d "/sys/module") {
		opendir D, "/sys/module";
		while (my $modname = readdir D) {
			# If directory and not "up-level"
			if ( -d "/sys/module/$modname" && $modname !~ m{^\.\.?$} ) {
				$self->_addModuleInfo($modname, "built-in", "");
				# if module have params
				if ( -d "/sys/module/$modname/parameters" ) {
					opendir DP, "/sys/module/$modname/parameters";
					while (my $param = readdir DP) {
						if ( -f "/sys/module/$modname/parameters/$param" ) {
							my $val;
							{
								#print "Reading /sys/module/$modname/parameters/$param\n";
								open PV, "<", "/sys/module/$modname/parameters/$param" or next;
								local $/ = undef;
								$val = <PV>;
								close PV;
							}
							chomp $val if $val;
                            $self->_addModuleParam($modname, $param, $val, "");
						}
					}
					closedir DP;
				}
			}
		}
		closedir D;
	}
}

sub _updateAllDescriptions {
    my $self = shift;

	eval {
        # find loaded modules and split it for chunks
        my $chunks = [];
        my $chunk = [];
        foreach my $modname (keys %{$self->{moduleList}}) {
            if ($self->{moduleList}->{$modname}->{type} eq "loaded") {
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
                    if (!defined($self->{moduleList}->{$modname})) {
                        next;
                    }
                    # Parse other data
                    foreach my $line (split /\n/, $dataLine) {
                        if ($line =~ m|^([^:]+): +(.*)$|is) {
                            my $key = $1;
                            my $val = $2;
                            chomp($val);
                            if ($key eq "description") {
                                $self->{moduleList}->{$modname}->{desc} = $val;
                            }
                            elsif ($key eq "parm") {
                                if ($val =~ m|^([^:]+):(.*)$|is) {
                                    $self->{moduleList}->{$modname}->{params}->{$1}->{desc} = $2;
                                }		
                            }
                        }
                    }
                }
            }
            close F;
        }
    };
    if (my $error = $@) {
        print "Can't load module list!\n";
    }
}

sub loadData {
    my $self = shift;
    $self->_getModulesLoaded();
    $self->_getModulesFromSystem();
    $self->_updateAllDescriptions();
}

sub getData {
    my $self = shift;
    return $self->{moduleList};
}

1;