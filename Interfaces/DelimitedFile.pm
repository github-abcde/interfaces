package Interfaces::DelimitedFile;

# RFC 4180-compliant.
use v5.10;
use Smart::Comments;
use Moose::Role;    # automatically turns on strict and warnings
use MooseX::Method::Signatures;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater

BEGIN {
	$Interfaces::DelimitedFile::VERSION = '2.0.0'; # 18-11-2013
}

requires qw(columns displayname datatype decimals signed allownull default decimalseparator thousandseparator);

has 'field_delimiter'		=> (is => 'rw', isa => 'Str',  lazy_build => 1, trigger => \&_field_delimiter_set);
has 'record_delimiter'		=> (is => 'rw', isa => 'Str',	lazy_build => 1,);
has 'delimited_mask'    	=> (is => 'rw', isa => 'Str',  lazy_build => 1,);
has 'delimited_columns' 	=> (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 1,);
has 'DelimitedFile_ar_useinfile'			=> (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 0,);
has 'DelimitedFile_hr_fileindex'			=> (is => 'rw', isa => 'HashRef[Int]', lazy_build => 0, clearer => 'clear_DelimitedFile_hr_fileindex');
has 'DelimitedFile_ar_writemask'			=> (is => 'rw', isa => 'Str', lazy_build => 0, clearer => 'clear_DelimitedFile_ar_writemask');
has 'delimiter'				=> (is => 'rw', isa => 'Str',  lazy_build => 1, trigger => \&_field_delimiter_set); # backwards compatibility for v1.0.0
has 'escapechar'			=> (is => 'rw', isa => 'Str',	lazy_build => 1, trigger => \&_escapechar_set);

after 'BUILD' => sub {
	my $self = shift;
	# Initialize our own attributes with default values and set all columns with a displayname to be used
	my ($field_delimiter, $escapechar) = (',', '"');
	$self->field_delimiter($field_delimiter);
	$self->record_delimiter("\r\n");
	$self->escapechar($escapechar);
	$self->DelimitedFile_ConfigureUseInFile($self->displayname());
	$self->{ESCAPEFIELD_ESCAPECHAR_INPUT1} = qr/^"(([^${escapechar}]|${escapechar}{2})*)"(?:[$field_delimiter]|$)/p;
	$self->{ESCAPEFIELD_NONESCAPE_INPUT1} = qr/^"(.*)"(?:[$field_delimiter]|$)/p;
	$self->{NONESCAPE_ESCAPECHAR_INPUT1} = qr/^([^${field_delimiter}${escapechar}]*)(?:[$field_delimiter]|$)/p;
	$self->{NONESCAPE_NONESCAPE_INPUT1} = qr/^([^${field_delimiter}]*)(?:[${field_delimiter}]|$)/p;
};

after 'Check' => sub {
	my $self = shift;
	print ("Checking DelimitedFile constraints...") if defined $Interfaces::Interface::DEBUGMODE;
	# Check if all fields that are marked with "useinfile" have a displayname
	for (0 .. $#{$self->columns}) {
		if ($self->{DelimitedFile_ar_useinfile}->[$_] && !($self->displayname->[$_] // "")) {
			Interfaces::Interface::Crash("DelimitedFile field [" . $self->columns->[$_] . "] is configured to be used, but has no displayname");
		}
	}
	# Check if the delimiter is set
	if (!$self->has_field_delimiter || $self->field_delimiter eq '') {
		Interfaces::Interface::Crash("Field delimiter not set");
	}
	if (!$self->has_record_delimiter || $self->record_delimiter eq '') {
		Interfaces::Interface::Crash("Record delimiter not set");
	}
	print("[OK]\n") if defined $Interfaces::Interface::DEBUGMODE;
	1;
};

after 'ReConfigureFromHash' => sub {
	my $self = shift;
	$self->clear_delimited_mask;
	$self->clear_DelimitedFile_hr_fileindex;
	$self->clear_DelimitedFile_ar_writemask;
	$self->clear_delimiter;
	# Initialize default values
	my ($field_delimiter, $escapechar) = (',', '"');
	$self->field_delimiter($field_delimiter);
	$self->record_delimiter("\r\n");
	$self->escapechar($escapechar);
	$self->DelimitedFile_ConfigureUseInFile($self->displayname());
	$self->{ESCAPEFIELD_ESCAPECHAR_INPUT1} = qr/^"(([^${escapechar}]|${escapechar}{2})*)"(?:[$field_delimiter]|$)/p;
	$self->{ESCAPEFIELD_NONESCAPE_INPUT1} = qr/^"(.*)"(?:[$field_delimiter]|$)/p;
	$self->{NONESCAPE_ESCAPECHAR_INPUT1} = qr/^([^${field_delimiter}${escapechar}]*)(?:[$field_delimiter]|$)/p;
	$self->{NONESCAPE_NONESCAPE_INPUT1} = qr/^([^${field_delimiter}]*)(?:[${field_delimiter}]|$)/p;
};

after 'AddField' => sub {
	my ($self, $hr_config) = @_;
};

method _escapechar_set(Str $value !, Str $old_value ?) {
	my $delimiter = $self->field_delimiter;
	my $string;
	if ($value ne '') {
		$string = '^"(([^' . $value . ']|' . $value . '{2})*)"(?:[' . $delimiter . ']|$)';
	} else {
		$string = '^([^' . $delimiter . ']*)(?:[' . $delimiter . ']|$)';
	}
	$self->{ESCAPEFIELD_ESCAPECHAR_INPUT1} = qr/$string/p;
	$string = '^([^' . $delimiter . $value . ']*)(?:[' . $delimiter . ']|$)';
	$self->{NONESCAPE_ESCAPECHAR_INPUT1} = qr/$string/p;
}

method _field_delimiter_set(Str $value !, Str $old_value ?) {
	my $string = '^([^' . $value . ']*)(?:[' . $value . ']|$)';
	$self->{NONESCAPE_NONESCAPE_INPUT1} = qr/$string/p;
	$string = '^\"(.*)\"(?:[' . $value . ']|$)';
	$self->{ESCAPEFIELD_NONESCAPE_INPUT1} = qr/$string/p;
	my $escapechar = $self->escapechar;
	if ($self->escapechar ne '') {
		$string = '^\"(([^' . $escapechar . ']|' . $escapechar . '{2})*)"(?:[' . $value . ']|$)';
		$self->{ESCAPEFIELD_ESCAPECHAR_INPUT1} = qr/$string/p;
		$string = '^([^' . $value . $escapechar . ']*)(?:[' . $value . ']|$)';
		$self->{NONESCAPE_ESCAPECHAR_INPUT1} = qr/$string/p;
	} else {
		$self->{ESCAPEFIELD_ESCAPECHAR_INPUT1} = $self->{ESCAPEFIELD_NONESCAPE_INPUT1};
		$self->{NONESCAPE_ESCAPECHAR_INPUT1} = $self->{NONESCAPE_NONESCAPE_INPUT1};
	}
}

method DelimitedHeader() {
	if (!$self->has_field_delimiter) {
		Interfaces::Interface::Crash("Field delimiter is not set");
	}
	# Returned alleen die displaynames waarvan useinfile op 1 staat.
	return join ($self->{field_delimiter}, map { $self->{displayname}->[$_]; } grep { $self->{DelimitedFile_ar_useinfile}->[$_]; } (0 .. $#{$self->{columns}}));
} ## end sub DelimitedHeader ($)

# WriteRecord ($hr_data) returns string
method WriteRecord(HashRef $hr_data !) {
	my $mask    = "";
	my @data;
	if (!$self->has_field_delimiter || !$self->has_record_delimiter) {
		Interfaces::Interface::Crash("Field- or Record-delimiter is not set");
	}
	my $field_delimiter = $self->field_delimiter;
	# Filter kolomindices die geen DelimitedFile_ar_useinfile hebben
	my @process_these_columns = grep { $self->{DelimitedFile_ar_useinfile}->[$_]; } (0 .. $#{$self->{columns}});
	# Maak printf-masks
	if (!$self->has_delimited_mask) {
		for my $index (@process_these_columns) {
			if (!defined $self->{DelimitedFile_ar_writemask}->[$index]) {
				$self->{DelimitedFile_ar_writemask}->[$index] = "%";
				given ($self->{internal_datatype}->[$index]) {
					when ($Interfaces::Interface::DATATYPE_TEXT) {
						$self->{DelimitedFile_ar_writemask}->[$index] .= "s";
					}
					when ($Interfaces::Interface::DATATYPE_NUMERIC) {
						$self->{DelimitedFile_ar_writemask}->[$index] .= $self->{signed}->[$index] == 1 ? "d" : "u";
					}
					when ($_ > $Interfaces::Interface::DATATYPE_NUMERIC) {
						$self->{DelimitedFile_ar_writemask}->[$index] .= "." . $self->{decimals}->[$index] . "f";
					}
					default {
						$self->{DelimitedFile_ar_writemask}->[$index] .= "s";
					}
				} ## end given
			} ## end if (!defined $Interfaces::DelimitedFile::hr_writemask...)
			$self->{delimited_mask} .= $self->{DelimitedFile_ar_writemask}->[$index] . $field_delimiter;
		} ## end for my $index (0 .. $#{...})
		substr($self->{delimited_mask}, -length($field_delimiter)) = ''; # Remove trailing field delimiter
		if (!defined $self->{DelimitedFile_ar_writemask}) {
			Interfaces::Interface::Crash("No columns were identified as being used in file (have you forgot to use ConfigureUseInFile?).");
		}
	}
	my $evalstring;
	foreach my $index (@process_these_columns) { 
		if (!defined $self->{DelimitedFile_ar_writemask}->[$index]) {
			push(@data, 'ERROR_NO_WRITE_MASK');
			next;
		}
		my $CurrentColumnDecimals = $self->{decimals}->[$index];
		my $field_value = $hr_data->{$self->{columns}->[$index]} // ($self->write_defaultvalues ? $self->{default}->[$index] : undef);

		if (!$self->{speedy} && $self->{internal_datatype}->[$index] >= $Interfaces::Interface::DATATYPE_NUMERIC) {
			$field_value = defined $field_value ? $self->minmax($index, $field_value) : 0;
		} else {
			if (defined $field_value) {
				if (index($field_value, $self->{escapechar}) + 1) { # 7772520	6.33s
					$field_value =~ s/"/""/g;
					$field_value = "\"$field_value\"";
				} elsif (index($field_value, $field_delimiter) + 1 || index($field_value, $self->{record_delimiter}) + 1) {
					$field_value = "\"$field_value\"";
				}
			} else {
				$field_value //= '';
			}
		}
		push(@data, $field_value);
	} 
	return sprintf($self->{delimited_mask}, @data);
} ## end sub WriteRecord

# WriteData ($filename, $ar_data, $hr_options)
# Options consist of:	header = 0 | 1 # Write a header to the file (default = 1)
#						append = 0 | 1 # Append to file (default = 0)
#						encoding = <value> # ascii, iso-8859-1, utf8 or any other encoding supported by Encode (default = utf8)
method WriteData(Str $filename !, ArrayRef $ar_data !, HashRef $hr_options ?) {
	if (!$self->has_field_delimiter || !$self->has_record_delimiter) {
		Interfaces::Interface::Crash("Field- or Record-delimiter is not set");
	}
	my $filemode = '>';
	$hr_options->{header} //= 1;
	$hr_options->{append} //= 0;
	$hr_options->{encoding} //= 'utf8';
	if ($hr_options->{append}) {
		$filemode .= '>';
	}
	$filemode .= ':' . $hr_options->{encoding};
	open (my $filehandle, $filemode, $filename) or Interfaces::Interface::Crash("Error opening outputfile [$filename]: $!");
	if ($hr_options->{header}) {
		print $filehandle Interfaces::DelimitedFile::DelimitedHeader($self) . $self->record_delimiter;
	}
	foreach my $hr_data (@{$ar_data}) { ### Writing [===[%]    ]
		print $filehandle Interfaces::DelimitedFile::WriteRecord($self, $hr_data) . $self->record_delimiter;
	}
	close ($filehandle);
} ## end sub WriteData ($$$)

# ReadRecord ($inputstring) returns $hr_record
method ReadRecord(Str $inputstring !, HashRef $hr_options ?) {
	# Default options
	$hr_options->{trim} //= 1;
	
	if (!$self->has_field_delimiter) {
		Interfaces::Interface::Crash("Field-delimiter is not set");
	}
	my $original_input = $inputstring; # Backup for debug dumps
	my $hr_returnvalue = {};
	my $input_column_index  = 0;
	my $max_input_columns = List::Util::max(keys %{$self->{DelimitedFile_hr_fileindex}});
	my $output_column_index = -1;
	my $field_value;
	my $delimiter         = $self->{field_delimiter};
	my $escapechar        = $self->{escapechar};
	my $thousandseparator = $self->{thousandseparator};
	my $decimalseparator  = $self->{decimalseparator};
	my ($CurrentColumnDecimals, $CurrentColumnDatatype, $current_field_default);
	while ($inputstring ne '' or $input_column_index <= $max_input_columns) {
		undef $field_value;
		$output_column_index = $self->{DelimitedFile_hr_fileindex}->{$input_column_index};
		if (!defined $output_column_index) {
			Carp::carp("Line read: [$inputstring]");
			Interfaces::Interface::Crash("Column index [$input_column_index] not found in DelimitedFile_hr_fileindex. Have you used ConfigureUseInFile or ParseHeaders? (Or are there more fields in the file than you defined)");
		}
		$CurrentColumnDecimals = $self->{decimals}->[$output_column_index];
		$CurrentColumnDatatype = $self->{datatype}->[$output_column_index];
		$current_field_default = $self->{default}->[$output_column_index];
		if (substr($inputstring,0,1) eq '"') { # 7707749	6.07s	
			$field_value = $inputstring;
			my $qr_match = $escapechar ne '' ? $self->{ESCAPEFIELD_ESCAPECHAR_INPUT1} : $self->{ESCAPEFIELD_NONESCAPE_INPUT1};
			if ($inputstring =~ /$qr_match/p) {
				($field_value, $inputstring) = ($1, ${^POSTMATCH});
				# Unescape escaped quotes
				$field_value =~ s/""/"/g;
			} else {
				Interfaces::Interface::Crash("Parsing error with data [$inputstring], current index [$input_column_index]");
			}
		} else {
			$field_value = $inputstring;
			my $qr_match = $escapechar ne '' ? $self->{NONESCAPE_ESCAPECHAR_INPUT1} : $self->{NONESCAPE_NONESCAPE_INPUT1};
			if ($inputstring =~ /$qr_match/p) {
				($field_value, $inputstring) = ($1, ${^POSTMATCH});
			}
		} ## end else [ if ($inputstring =~ /^"/)]
		if ($Interfaces::Interface::DEBUGMODE) {
			Carp::carp("Field [$self->{columns}->[$output_column_index]] read with value [$field_value]");
		}
		if ($output_column_index >= 0) {
			# Trim field
			if ($hr_options->{trim}) {
				$field_value =~ s/^\s+//;
				$field_value =~ s/\s+$//;
			}
			if ($field_value eq '') {
				undef $field_value;
			}
			if (!defined $field_value && !$self->{allownull}->[$output_column_index] && !$self->{read_defaultvalues}) {
				
				Data::Dump::dd($original_input);
				Interfaces::Interface::Crash('Input Field [' . $input_column_index . '], output [' . $output_column_index . '].[' . $self->{columns}->[$output_column_index] . '] requires a value, but has none, and no default value either');
			}
			if ($self->{internal_datatype}->[$output_column_index] >= $Interfaces::Interface::DATATYPE_NUMERIC) {
				if (!defined $field_value) {
					if (!$self->{allownull}->[$output_column_index]) {
						if (defined $current_field_default) {
							if ($self->{read_defaultvalues}) {
								$field_value = 0 + $current_field_default;
							}
						}
					} else {
						$input_column_index++;
						next;
					}
				} else {
					$field_value = 0 + $field_value;
					if ($self->{speedy} && $field_value == ($current_field_default // 0) && $self->{allownull}->[$output_column_index] && !$self->{read_defaultvalues}) {
						# Skip numeric fields that equal (default value // 0)
						$input_column_index++;
						next; 
					} 
					if (!$self->{speedy}) {
						# Check if there are trailing negators, and fix it to be a heading negator
						if (substr($field_value, -1) eq '-') {
							#$field_value =~ s/^(.*)-$/-$1/; # 11.2s, 2.67s
							$field_value = '-' . substr($field_value, 0, -1);
						}
						if (defined $thousandseparator and $thousandseparator ne '') {
							# Remove thousandseparator, if present
							while (my $ts_loc = index($field_value, $thousandseparator) + 1) {
								substr($field_value, $ts_loc - 1, 1) = '';
							}
						}
						# Range check
						$field_value = $self->minmax($output_column_index, $field_value);
					}
				}
				$hr_returnvalue->{$self->{columns}->[$output_column_index]} = $field_value;
			} else { # Not DATATYPE_NUMERIC
				if (!defined $field_value) {
					if (!$self->allownull->[$output_column_index] && $self->{read_defaultvalues} && defined $current_field_default) {
						# If NULL values are not allowed, store default value or undef (if no default value exists)
						$hr_returnvalue->{$self->{columns}->[$output_column_index]} = $current_field_default;
					}
					# else don't store the value at all..saves a key-value pair
				} else {
					$hr_returnvalue->{$self->{columns}->[$output_column_index]} = $field_value;
				}
			}
		} ## end if ($output_column_index...)
		$input_column_index++;
	} ## end while ($inputstring)
	return $hr_returnvalue;
} ## end sub ReadRecord 

# ParseHeaders ($headerstring)
# Matches headers in string with @self->displayname and sets useinfile=1 for the matching headers
# Also sets the matching header's fileindex to the columnnumber (0-based) where the header matched in the string.
method ParseHeaders(Str $inputstring !) {
	if (!$self->has_field_delimiter || !$self->has_record_delimiter) {
		Interfaces::Interface::Crash("Field- or Record-delimiter is not set");
	}
	# Zero all useinfiles and fileindex
	for (0 .. $#{$self->columns}) {
		$self->{DelimitedFile_ar_useinfile}->[$_] = 0;
		$self->{DelimitedFile_ar_fileindex}->[$_] = undef;
	}
	my $num_file_index = 0;
	my $delimiter      = $self->field_delimiter;
	while ($inputstring ne '') {
		my $header = $inputstring;
		if ($inputstring =~ /^"(([^"]|"")*)"(?:[$delimiter]|$)/) {
			($header, $inputstring) = ($1, ${^POSTMATCH});
		} elsif ($inputstring =~ /^([^$delimiter"]+)(?:[$delimiter]|$)/) {
			($header, $inputstring) = ($1, ${^POSTMATCH});
		}
		my $HeaderIndex = (grep( { $self->{displayname}->[$_] eq $header; } (0 .. $#{$self->{displayname}})))[0];
		if ($HeaderIndex >= 0) {
			$self->{DelimitedFile_ar_useinfile}->[$HeaderIndex] = 1;
			$self->{DelimitedFile_hr_fileindex}->{$num_file_index} = $HeaderIndex;
		} else {
			print ("Header [$header] not found\n");
		}
		$num_file_index++;
	} ## end while ($inputstring)
} ## end sub ParseHeaders ($$)

# reconfigure_and_read(filename)
# Creates columns "Column_nn" for each column detected in inputstring with type "VARCHAR(max detected length * 2)"
# returns data read
method reconfigure_and_read(Str $filename !, HashRef $hr_options ?) {
	if (!$self->has_field_delimiter || !$self->has_record_delimiter) {
		Interfaces::Interface::Crash("Field- or Record-delimiter is not set");
	}
	$hr_options->{no_header} = $hr_options->{no_header} // 0;
	$hr_options->{skip_header} = $hr_options->{skip_header} // 0;
	if ($hr_options->{no_header}) {
		$hr_options->{skip_header} = 0;
	}
	my ($field_delimiter, $record_delimiter, $escapechar) = ($self->field_delimiter, $self->record_delimiter, $self->escapechar);
	my $ar_returnvalue = [];
	my $record;
	my $ar_maxlen = [];
	my $ar_allownull = [];
	my $old_INPUT_RECORD_SEPARATOR = $/;
	local $/ = $record_delimiter;
	open (my $filehandle, '<', $filename) or Interfaces::Interface::Crash("Cannot open file [$filename]: $!");

	while (<$filehandle>) { ### Reading [===[%]    ]
		chomp;
		$record = $_;
		# If a line contains an odd amount of doublequotes ("), then we'll need to continue reading until we find another line that contains an odd amount of doublequotes.
		# This is in order to catch fields that contain recordseparators (but are encased in ""'s).
		if (($escapechar // '' ) ne '' and grep { $_ eq $escapechar; } split ('', $_) % 2 == 1) { # 64771	8.75s
			# Keep reading data and appending to $record until we find another line with an odd number of doublequotes.
			while (<$filehandle>) {
				$record .= $_;
				if (grep { $_ eq $escapechar; } split ('', $_) % 2 == 1) { last; }
			}
		} ## end if (grep ($_ eq '"', split...))
		# Read line
		$hr_options->{trim} //= 1;
		my $input_column_index  = 0;
		my $hr_record         = {};
		while ($record ne '') {
			$ar_allownull->[$input_column_index] //= 0;
			$ar_maxlen->[$input_column_index] //= 0;
			my $field_value;
			if (substr($record,0,1) eq $escapechar) { # 7707749	6.07s	
				$field_value = $record;
				my $qr_match = $escapechar ne '' ? $self->{ESCAPEFIELD_ESCAPECHAR_INPUT1} : $self->{ESCAPEFIELD_NONESCAPE_INPUT1};
				if ($record =~ /$qr_match/p) {
					($field_value, $record) = ($1, ${^POSTMATCH});
					# Unescape escaped quotes
					$field_value =~ s/""/"/g;
				} else {
					Interfaces::Interface::Crash("Parsing error with data [$record], current index [$input_column_index]");
				}
			} else {
				$field_value = $record;
				my $qr_match = $escapechar ne '' ? $self->{NONESCAPE_ESCAPECHAR_INPUT1} : $self->{NONESCAPE_NONESCAPE_INPUT1};
				if ($record =~ /$qr_match/p) {
					($field_value, $record) = ($1, ${^POSTMATCH});
				}
			} ## end else [ if ($record =~ /^"/)]
			if ($Interfaces::Interface::DEBUGMODE >= 2) {
				Carp::carp("Field [$input_column_index] read with value [$field_value]");
			}
			# Since we're assuming all fields as VARCHAR, we don't have to perform any of the numerical checks/fixes
			# Trim field
			if ($hr_options->{trim}) {
				$field_value =~ s/^\s*(.*?)\s*$/$1/;
			}
			if (length($field_value) > $ar_maxlen->[$input_column_index]) {
				$ar_maxlen->[$input_column_index] = length($field_value);
			}
			if ($field_value eq '') {
				$field_value = undef;
				$ar_allownull->[$input_column_index] |= 1;
			}
			$hr_record->{'Column_' . $input_column_index} = $field_value;
			$input_column_index++;
		}
		push (@{$ar_returnvalue}, $hr_record);
	} ## end while (<DELIMFILE>)
	close ($filehandle);
	# Configure interface
	$self->ClearConfig(); # Scary
	$self->name($hr_options->{name} // ('Generated' . time));
	$self->field_delimiter($field_delimiter);
	$self->record_delimiter($record_delimiter);
	$self->escapechar($escapechar);
	foreach my $index (0 .. $#$ar_maxlen) {
		if ($ar_maxlen->[$index] == 0) { $ar_maxlen->[$index]++; } # Avoid VARCHAR(0)
		$self->AddField({ fieldname => 'Column_' . $index, displayname => 'Column ' . $index, allownull => $ar_allownull->[$index], datatype => 'VARCHAR', length => 2 * $ar_maxlen->[$index], });
		$self->{DelimitedFile_ar_useinfile}->[$index] = 1;
		$self->{DelimitedFile_hr_fileindex}->{$index} = $index;
	}
	$self->Check();
	return $ar_returnvalue;
}

# ConfigureUseInFile ($ar_headers)
# Matches headers in $ar_headers with @self->displayname and sets useinfile=1 for the matching headers
# Also sets the matching header's fileindex to the columnnumber (0-based) where the header matched in the arrayref.
method ConfigureUseInFile(ArrayRef $ar_headers !) {
	# Zero all useinfiles and fileindex
	for (0 .. $#{$self->columns}) {
		$self->{DelimitedFile_ar_useinfile}->[$_] = 0;
		#		$Interfaces::DelimitedFile::ar_fileindex->[$_] = undef;
		undef $self->{DelimitedFile_hr_fileindex};
	}
	my $num_file_index = 0;
	foreach my $header (@{$ar_headers}) {
		my $HeaderIndex = (grep( { $self->{displayname}->[$_] eq $header; } (0 .. $#{$self->{displayname}})))[0];
		if ($HeaderIndex >= 0) {
			$self->{DelimitedFile_ar_useinfile}->[$HeaderIndex] = 1;
			$self->{DelimitedFile_hr_fileindex}->{$num_file_index} = $HeaderIndex;
		} else {
			Carp::carp("Header [$header] not found\n");
		}
		$num_file_index++;
	} ## end foreach my $header (@{$ar_headers...})
	1;
} ## end sub ConfigureUseInFile ($$)

# ReadFile ($filename, [$hr_options]) returns \@data with \%records
# Options consist of:	skip_header		= 0 | 1 # Skip the header in the file (default = 0)
#						no_header		= 0 | 1 # There is no header in the file (default = 0) (implies skip_header=0)
method ReadData(Str $filename !, HashRef $hr_options ?) {
	if (!$self->has_field_delimiter || !$self->has_record_delimiter) {
		Interfaces::Interface::Crash("Field- or Record-delimiter is not set");
	}
	$hr_options->{no_header} = $hr_options->{no_header} // 0;
	$hr_options->{skip_header} = $hr_options->{skip_header} // 0;
	if ($hr_options->{no_header}) {
		$hr_options->{skip_header} = 0;
	}
	my $ar_returnvalue = [];
	my $record;
	my $old_INPUT_RECORD_SEPARATOR = $/;
	local $/ = $self->record_delimiter;
	open (my $filehandle, '<', $filename) or Interfaces::Interface::Crash("Cannot open file [$filename]: $!");
	if (!$hr_options->{no_header}) {
		# There is a header
		my $Headers = <$filehandle>;
		chomp($Headers);
		if ($hr_options->{skip_header}) {
			if (scalar keys (%{$self->{DelimitedFile_hr_fileindex}}) == 0) {
				Interfaces::Interface::Crash("ReadData called but no fields have been configured to use and the option to skip the header was given (which means no fields will be autoconfigured for use either).");
			}
		} else {
			Interfaces::DelimitedFile::ParseHeaders($self, $Headers);
		}
	}
	while (<$filehandle>) { ### Reading [===[%]    ]
		chomp;
		$record = $_;
		# If a line contains an odd amount of doublequotes ("), then we'll need to continue reading until we find another line that contains an odd amount of doublequotes.
		# This is in order to catch fields that contain recordseparators (but are encased in ""'s).
		if (grep { $_ eq '"'; } split ('', $_) % 2 == 1) { # 64771	8.75s
			# Keep reading data and appending to $record until we find another line with an odd number of doublequotes.
			while (<$filehandle>) {
				$record .= $_;
				if (grep { $_ eq '"'; } split ('', $_) % 2 == 1) { last; }
			}
		} ## end if (grep ($_ eq '"', split...))
		push (@{$ar_returnvalue}, Interfaces::DelimitedFile::ReadRecord($self, $record));
	} ## end while (<DELIMFILE>)
	close ($filehandle);
	#print("Returning size: [" . Devel::Size::total_size($ar_returnvalue) . "]\n");
	return $ar_returnvalue;
} ## end sub ReadData ($$)

1;

=head1 NAME

Interfaces::DelimitedFile - Delimited file format extension to Interfaces::Interface

=head1 VERSION

This document refers to Interfaces::DelimitedFile version 2.0.0.

=head1 SYNOPSIS

  use Interfaces::Interface;
  my $interface = Interfaces::Interface->new();
  $interface->ReConfigureFromHash($hr_config);
  my $ar_data = $interface->DelimitedFile_ReadData("foobar.csv");
  $interface->DelimitedFile_WriteData("foobar.csv", $ar_data);

=head1 DESCRIPTION

This module extends the Interfaces::Interface with the capabilities to read from - and
write to files in a character or string-delimited file.

=head2 Attributes for C<Interfaces::DelimitedFile>

=over 4

=item * C<field_delimiter>
Contains the field-delimiter character (or string). This is ',' by default.

=item * C<record_delimiter>
Contains the record-delimiter character (or string). This is "\r\n" by default.

=back

=head2 Methods for C<Interfaces::DelimitedFile>

=over 4

=item * C<$interface-E<gt>DelimitedHeader();>

Returns a string containing all headers specified to be used in file separated by the field_delimiter.
The record_separator is not appended to the resulting string.

=item * C<$interface-E<gt>ConfigureUseInFile($ar_headers);>

Supplied an arrayref of strings, matches those with $self->displayname to determine which columns in
the file are to be linked with which columns of the interface. 

=item * C<$interface-E<gt>ParseHeaders($headerstring);>

Performs an identical function to ConfigureUseInFile, except this takes a string from which it extracts
the headers.

=item * C<$interface-E<gt>ReadRecord($string);>

Parses the supplied line of text as a character/string-delimited record. Returns an hashref with the data 
with the columnnames as key. Only reads the columns configured by ConfigureUseInFile or ParseHeaders.
If $self->thousandseparator is configured, it is removed from the data read.
If $self->decimalseparator is configured, it is replaced in the data by a period (thus enabling the value to
be properly parsed).

=item * C<$interface-E<gt>WriteRecord($hr_data);>

Converts the supplied hashref datarecord to a line of text. Returns a string of text containing the
character/string-delimeted data. The record_separator is not appended to the resulting string.

=item * C<$interface-E<gt>ReadData($fullpath_to_file, $hr_options);>

Options consist of:	skip_header		= 0 | 1 # Skip the header in the file (default = 0)
					no_header		= 0 | 1 # There is no header in the file (default = 0) (implies skip_header=0)

Reads the given file and returns its data as an arrayref with a hashref per datarecord.
If the header is to be parsed (skip_header == 0 and no_header == 0), it is read and parsed with ParseHeaders.

=item * C<$interface-E<gt>WriteData($fullpath_to_file, $ar_data, $hr_options);>

Writes the given data to the file specified by $fullpath_to_file.
Options consist of:	header = 0 | 1 # Write a header to the file (default = 1)
					append = 0 | 1 # Append to file (default = 0)
					
=back

=head1 DEPENDENCIES

L<Interfaces::Interface>, L<Moose> and L<Carp>.

=head1 AUTHOR

The original author is Herbert Buurman

=head1 LICENSE

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See L<perlartistic>.

=cut

