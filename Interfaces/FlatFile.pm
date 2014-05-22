package Interfaces::FlatFile;

use Smart::Comments;
use Moose::Role;
use MooseX::Method::Signatures;
use Encode;
use v5.10;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater

BEGIN {
	$Interfaces::FlatFile::VERSION = '1.2.0'; # 6-02-2013
	# 1.1.1	08-03-2012	HB	WriteRecord aangepast zodat deze met mask %-x.xs print ipv %-xs  (met x = lengte van het veld)
	# 1.2.0	06-02-2013	HB	Geoptimaliseerd, datatypes, recordlength als attribuut toegevoegd.
}

has 'flat_mask'        		=> (is => 'rw', isa => 'Str',                  lazy_build => 1,);
has 'flat_columns'     		=> (is => 'rw', isa => 'ArrayRef[Int]',        lazy_build => 1,);
has 'flatfield_start'  		=> (is => 'rw', isa => 'ArrayRef[Maybe[Int]]', lazy_build => 1,);
has 'flatfield_length' 		=> (is => 'rw', isa => 'ArrayRef[Maybe[Int]]', lazy_build => 1,);
has 'FlatFile_recordlength'	=> (is => 'rw', isa => 'Maybe[Int]',			lazy_build => 1,);
has 'explicit_numeric_separators'	=> (is => 'rw', isa => 'Bool',			lazy_build => 1,);

after 'BUILD' => sub {
	my $self = shift;
	$self->explicit_numeric_separators(0);
};

after 'ReConfigureFromHash' => sub {
	my $self = shift;
	$self->explicit_numeric_separators(0);
	$self->clear_flat_mask;
};

after 'AddField' => sub {
	my $self = shift;
	my ($hr_config) = @_;
	$self->clear_flat_mask;
};


after 'Check' => sub {
	my $self = shift;
	my $previousfield = undef;
	# Order the flatfields by flatfield_start
	my @fields_ordered = sort { $self->flatfield_start->[$a] <=> $self->flatfield_start->[$b] } grep { defined $self->flatfield_start->[$_] && defined $self->flatfield_length->[$_]; } (0 .. $#{$self->columns});
	for (@fields_ordered) {
		if (defined $self->flatfield_start->[$_]) { $previousfield = $_; last; }
	}
	if (!defined $previousfield) { return; }    # Interface does not contain flatfields
	for (@fields_ordered) {
		# Skip check for fields we're not going to use due to not being (fully) configured.
		if (!(defined $self->flatfield_start->[$_] && defined $self->flatfield_length->[$_])) {
			next;
		}
		if (defined $previousfield && $previousfield != $_) {
			if ($self->flatfield_start->[$_] <= $self->flatfield_start->[$previousfield]) {
				Interfaces::Interface::Crash("Flatfield_start is not always increasing: Column [" . $self->columns->[$_] . "] doesn't start after [" . $self->columns->[$previousfield] . "]");
			}
			if ($self->flatfield_start->[$_] < $self->flatfield_start->[$previousfield] + $self->flatfield_length->[$previousfield]) {
				Interfaces::Interface::Crash('Interface [' . $self->name . ']: ' . 
						'Flatfields [' . $self->columns->[$previousfield] . '] (' . $self->flatfield_start->[$previousfield] . '/' . $self->flatfield_length->[$previousfield] . ') ' . 
						'and [' . $self->columns->[$_] . '] (' . $self->flatfield_start->[$_] . ') overlap');
			}
		}
		$previousfield = $_;
	} ## end for (1 .. $#{$self->columns...
	1;
};

method generate_flat_mask() {
	$self->clear_flat_columns;
	my $ar_flat_columns = [];
	my $flatline_counter = 0;
	my $mask = "";
	foreach my $index (0 .. $#{$self->{columns}}) {
		if (!(defined $self->{flatfield_start}->[$index] && defined $self->{flatfield_length}->[$index])) {
			# Field is missing interface_start, interface_length or both, skip it.
			next;
		}
		if ($flatline_counter > $self->{flatfield_start}->[$index]) {
			Interfaces::Interface::Crash(  "Error in interface ["
						  . $self->{tablename}
						  . "]: field ["
						  . $self->{columns}->[$index]
						  . "] starts at position ["
						  . $self->{flatfield_start}->[$index]
						  . "] but we have already [$flatline_counter] bytes of data.");
		} ## end if ($flatline_counter ...
		if ($flatline_counter < $self->{flatfield_start}->[$index]) {
			# Defined fields are non-contiguous, inserting filler
			$mask .= " " x ($self->{flatfield_start}->[$index] - $flatline_counter);
			$flatline_counter = $self->{flatfield_start}->[$index];
		}
		$mask .= '%';
		if ($self->{internal_datatype}->[$index] == $Interfaces::Interface::DATATYPE_TEXT) {
			$mask .= "-" . $self->{flatfield_length}->[$index] . '.' . $self->{flatfield_length}->[$index] . "s";
		} elsif ($self->{signed}->[$index]) {
			$mask .= "0" . $self->{flatfield_length}->[$index] . ($] < 5.012 ? "s" : "d");
		} else {
			$mask .= "0" . $self->{flatfield_length}->[$index] . ($] < 5.012 ? "s" : "u");
		}
		$flatline_counter += $self->{flatfield_length}->[$index];
		push(@{$ar_flat_columns}, $index);
	} ## end for (0 .. $#{$self->columns...
	$self->flat_mask($mask);
	$self->flat_columns($ar_flat_columns);
}

# Options consist of:
# encoding_in	=> <value>		Where <value> is any valid value in http://search.cpan.org/dist/Encode/lib/Encode/Supported.pod. Determines the input encoding, does nothing without encoding_out
# encoding_out	=> <value>		Where <value> is any valid value in http://search.cpan.org/dist/Encode/lib/Encode/Supported.pod. Determines the output encoding, requires encoding_in to be specified as well.
method WriteRecord(HashRef $hr_data !, HashRef $hr_options ?) {
	if (defined $hr_options && defined $hr_options->{encoding_out} && !defined $hr_options->{encoding_in}) {
		Interfaces::Interface::Crash("encoding_out supplied without encoding_in.");
	}
	my @data;
	# Maak printf-mask als deze nog niet bestaat
	if (!$self->has_flat_mask) {
		$self->generate_flat_mask;
	} ## end if (!$self->has_mask)
	my $evalstring;
	foreach my $index (@{$self->{flat_columns}}) {
		my $datafield;
		my $columnname = $self->{columns}->[$index];
		if ($self->{internal_datatype}->[$index] == $Interfaces::Interface::DATATYPE_TEXT) {
			# Text
			$datafield = $hr_data->{$columnname} // ($self->write_defaultvalues ? $self->{default}->[$index] : '');
		} else {
			# Numeric
			if (($hr_data->{$columnname} // '')  eq '') {
				$datafield = ($self->write_defaultvalues ? $self->{default}->[$index] : 0);
			} else {
				if (!$self->{speedy} && $hr_data->{$columnname} =~ /[^-.0-9]/) {
					Data::Dump::dd($hr_data);
					print("Column [$index]\n");
					Interfaces::Interface::Crash('Interface [' . $self->name . '] datatype [' . $self->datatype->[$index] . '] column [' . $columnname . '] error converting data [' . $hr_data->{$columnname} . ']');
				} else {
					$datafield = $hr_data->{$columnname};
				}
			}
			if (!$self->{speedy} && defined $datafield) {
				$datafield = $self->minmax($index, $datafield);
			}
			if (defined $self->{decimals}->[$index] && $self->{decimals}->[$index] > 0) {
				# DOUBLE, FLOAT, DECIMAL
				$datafield *= 10**$self->{decimals}->[$index];
				if ($self->{signed}->[$index] and $datafield < 0) {
					$datafield -= 10**-($self->{decimals}->[$index]); # For fixing floating-point errors (4.06 -> 4.06) without fear of changing the outcome.
				} else {
					$datafield += 10**-($self->{decimals}->[$index]); # For fixing floating-point errors (4.06 -> 4.06) without fear of changing the outcome.
				}
				# Destroy remaining decimals (not needed, because sprintf("%u" or "%d") doesn't write decimals.
				# But only v5.012+ because before that we're using %s to print
				if ($] < 5.012) {
					$datafield = int($datafield);
				}
			} else {
				# TINYINT, SMALLINT, MEDIUMINT, INT, INTEGER, BIGINT
				$datafield = int($datafield); # Truncaten...getallen achter de komma kunnen weg.
			}
		}
		# If output-encoding is supplied, encode it
		if (defined $hr_options && defined $hr_options->{encoding_in} && defined $hr_options->{encoding_out}) {
			$datafield = Encode::encode($hr_options->{encoding_out}, Encode::decode($hr_options->{encoding_in}, $datafield));
		}
		# Truncate field to maximum allowed length
		#$datafield = substr($datafield, 0, $self->flatfield_length->[$index]);
		push(@data, $datafield);
	} ## end for (0 .. $#{$self->columns...
	return sprintf ($self->{flat_mask}, @data);
} ## end sub WriteRecord ($$)

method ReadRecord(Str $textinput !, HashRef $hr_options ?) {
	# Default settings
	$hr_options->{trim} //= 1;
#Data::Dump::dd("Called with [$textinput]\n");	
	my $hr_returnvalue = {};
	my ($current_column_name, $current_field_start, $current_field_length, $current_field_decimals, $current_field_default);
	my $decimalseparator = $self->has_decimalseparator ? $self->decimalseparator : '.';
	my $thousandseparator = $self->has_thousandseparator ? $self->thousandseparator : '';
	# Check if textinput is long enough
	if (!$self->{speedy} && defined $self->{FlatFile_recordlength} && length($textinput) < $self->{FlatFile_recordlength}) {
		Data::Dump::dd($textinput);
		Interfaces::Interface::Crash("field [" . $self->columns->[$_] . "] [" . $self->flatfield_start->[$_] . "," . $self->flatfield_length->[$_] . "] is outside the text inputstring (length [" . length($textinput) . "])");
	}
	foreach my $index (0 .. $#{$self->columns}) {
		my $field_value;
		$current_column_name = $self->{columns}->[$index]; # 15.5s for 6704698 calls with proper accessor
		$current_field_start = $self->{flatfield_start}->[$index]; # 14.1s for 6704698 calls with proper accessor
		$current_field_length = $self->{flatfield_length}->[$index]; # 15.1s for 6704698 calls with proper accessor
#print("Processing column [$current_column_name], [$current_field_start - $current_field_length]\n");
		if (!(defined $current_field_start && defined $current_field_length)) {
			# Field is missing interface_start, interface_length or both, skip it.
			#			Carp::carp("Field [$current_column_name] is missing flatfield_start, flatfield_length or both, skip it.");
			next;
		}
		$field_value = substr ($textinput, $current_field_start, $current_field_length);
		#$field_value =~ s/^([ ]*)(.*?)([ ]*)$/$2/;    # Trim, takes 3.83us/call (38.9s for 23900499 calls)
		#$field_value = SleLib::trim($field_value);	# Takes 7us/call
		# The two regexes below took respectively 1us/call and 478ns/call
		if ($hr_options->{trim}) {
			$field_value =~ s/^\s+//; # 6592014	18.8s	6592014	6.05s
			$field_value =~ s/\s+$//; # 6592014	12.8s	6592014	2.71s
			#$field_value =~ s/^\s*(.*?)\s*$/$1/; # 6592014	61.9s	19776042	28.7s
		}
		$current_field_default = $self->{default}->[$index];
		# Lege velden weggooien.
		if ($field_value eq '') {
			undef $field_value;
		}
		if (!defined $field_value) {
			if (!$self->{allownull}->[$index]) {
				if (defined $current_field_default) {
					if ($self->{read_defaultvalues}) {
						given ($self->{internal_datatype}->[$index]) {
							when ([$Interfaces::Interface::DATATYPE_TEXT, $Interfaces::Interface::DATATYPE_FIXEDPOINT, $Interfaces::Interface::DATATYPE_FLOATINGPOINT]) {
								$field_value = sprintf ("%s", $current_field_default);
							}
							when ($Interfaces::Interface::DATATYPE_NUMERIC) {
								$field_value = 0 + $current_field_default;
							}
						}
					}
				} else {
					Data::Dump::dd($textinput);
					Interfaces::Interface::Crash('Field [' . $current_column_name . '] requires a value, but has none, and no default value either');
				}
			} else {
				next;
			}
		} else {
			if ($self->{internal_datatype}->[$index] >= $Interfaces::Interface::DATATYPE_NUMERIC) {
				# Niet-leeg numeriek veld
				$field_value = 0 + $field_value;
				if ($field_value eq ($current_field_default // '0') && $self->{allownull}->[$index] && !$self->{read_defaultvalues}) { next; } # Skip numeric fields that equal (default value // 0)
				# Speedy setting implies the data is neat and tidy and doesn't need correcting
				if (!$self->{speedy}) {
					# Check if there are trailing negators, and fix it to be a heading negator
					if (substr($field_value, -1) eq '-') {
						#$field_value =~ s/^(.*)-$/-$1/; # 11.2s, 2.67s
						$field_value = '-' . substr($field_value, 0, -1);
					}
				}
				if ($self->{internal_datatype}->[$index] > $Interfaces::Interface::DATATYPE_NUMERIC) {
					# Decimaal-correctie toepassen
					$current_field_decimals = $self->{decimals}->[$index] // 0; # spent 14.0s making 5239806 calls with proper accessor
					if ($current_field_decimals > 0) {
						$field_value /= 10**$current_field_decimals;
					}
				}
				if (!$self->{speedy} ) {
					$field_value = $self->minmax($index, $field_value);
				}
			}
		}
		$hr_returnvalue->{$current_column_name} = $field_value;
	} ## end for (0 .. $#{$self->columns...
	return $hr_returnvalue;
} ## end sub ReadRecord ($$)

# ReadData ($filename) returns ar_data
method ReadData(Str $filename !, HashRef $hr_options ?) {
	my $ar_returnvalue = [];
	$hr_options //= {};
	if (!-e "$filename") {
		Carp::carp("File [$filename] does not exist");
		return;
	}
	# Determine required length of input records
	my $lastindex = $#{$self->columns};
	$self->FlatFile_recordlength(List::Util::max(map { ($self->flatfield_start->[$_] // 0) + ($self->flatfield_length->[$_] // 0); } (0 .. $lastindex)));
	open (my $filehandle, '<', $filename) or Interfaces::Interface::Crash("Cannot open file [$filename]");
	while (<$filehandle>) { ### Reading [===[%]    ]
		chomp;
		push (@{$ar_returnvalue}, Interfaces::FlatFile::ReadRecord($self, $_, $hr_options));
	}
	close ($filehandle);
	return $ar_returnvalue;
} ## end sub ReadData ($$)

# WriteData ($filename, $ar_data, $hr_options)
# Options consist of:	append = 0 | 1 # Append to existing file (default = 0 (overwrite))
method WriteData(Str $filename !, ArrayRef $ar_data !, HashRef $hr_options ?) {
	$hr_options->{append} //= 0; # Default
	my $filemode = '>';
	if ($hr_options->{append}) {
		$filemode .= '>';
	}
	open (my $filehandle, $filemode, $filename) or Interfaces::Interface::Crash("Cannot open file [$filename]");
	foreach my $hr_data (@{$ar_data}) { ### Writing [===[%]    ]
		print $filehandle Interfaces::FlatFile::WriteRecord($self, $hr_data) . $/;
	}
	close ($filehandle);
} ## end sub WriteData($$$)

1;

=head1 NAME

Interfaces::FlatFile - FlatFile format extension to Interfaces::Interface

=head1 VERSION

This document refers to Interfaces::FlatFile version 1.0.0.

=head1 SYNOPSIS

  use Interfaces::Interface;
  my $interface = Interfaces::Interface->new();
  $interface->ReConfigureFromHash($hr_config);
  my $ar_data = $interface->FlatFile_ReadData("foobar.txt");
  $interface->FlatFile_WriteData("foobar.txt", $ar_data);

=head1 DESCRIPTION

This module extends the Interfaces::Interface with the capabilities to read from - and
write to files in a flatfile (a.k.a. fixed-length record) layout.

=head2 Attributes for C<Interfaces::FlatFile>

=over 4

=item * C<mask>
Contains the (sprintf) mask used when converting a datarecord to a flat line of text. If it is not
supplied, it will automatically be constructed using the interface's configuration data upon first
use.

=item * C<flatfield_start>
Contains, per column, the position (0-based) where the data for this column starts.

-item * C<flatfield_length>
Contains, per column, the length (in bytes) of the data for this column.

=back

=head2 Methods for C<Interfaces::FlatFile>

=over 4

=item * C<$interface-E<gt>ReadRecord($line_of_text);>

Parses the supplied line of text as a fixed-length record. Returns an hashref with the data with the 
columnnames as key.

=item * C<$interface-E<gt>WriteRecord($hr_data);>

Converts the supplied hashref datarecord to a line of text. Returns a string of text containing the
fixed-length encoded data.

=item * C<$interface-E<gt>ReadData($fullpath_to_file);>

Reads the given file, decodes it and returns its data as an arrayref with a hashref per datarecord.
The special variable $/ (or $INPUT_RECORD_SEPARATOR) can be changed to a different input record separator
should that be required.

=item * C<$interface-E<gt>WriteData($fullpath_to_file, $ar_data);>

Writes the supplied data in fixed-length format to the given file. If the file already existed, it is
overwritten, otherwise it is created. Each record is appended with $/ when written to file.

=back

=head1 DEPENDENCIES

L<Interfaces::Interface>, L<Moose>, L<Carp> and L<Encode>

=head1 AUTHOR

The original author is Herbert Buurman

=head1 LICENSE

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See L<perlartistic>.

=cut

