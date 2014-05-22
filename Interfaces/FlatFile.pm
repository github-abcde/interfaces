package Interfaces2::FlatFile;
# Version 0.2	29-09-2011
# previously Copyright (C) OGD 2011
# previously Copyright (C) THR 2011
# Copyright released by THR in 2013

use Moose::Role;
use MooseX::Method::Signatures;
use Encode;
use 5.010;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater

BEGIN {
	@Interfaces2::FlatFile::methods = qw(ReadRecord WriteRecord ReadData WriteData);
}

has 'flat_mask'				=> (is => 'rw', isa => 'Str',					lazy_build => 1,);
has 'flat_mask_unpack'		=> (is => 'rw', isa => 'Str',					lazy_build => 1,);
has 'flat_columns'			=> (is => 'rw', isa => 'ArrayRef[Int]',		lazy_build => 1,);
has 'flatfield_start'		=> (is => 'rw', isa => 'ArrayRef[Maybe[Int]]',	lazy_build => 1,);
has 'flatfield_length'		=> (is => 'rw', isa => 'ArrayRef[Maybe[Int]]',	lazy_build => 1,);
has 'internal_datatype'	=> (is => 'rw', isa => 'ArrayRef[Int]',		lazy_build => 0,);
has 'FlatFile_recordlength'	=> (is => 'rw', isa => 'Maybe[Int]',			lazy_build => 1,);	

# Scan for roles
BEGIN {
	no strict;
	my ($package_fqpn, $package_this, $package_aspath) = (__PACKAGE__)x3;
	$package_aspath =~ s'::'/'g;
	$package_this =~ s/^.*::([^:]*)$/$1/;
	my (undef, $include_dir, $package_pm) = File::Spec->splitpath($INC{$package_aspath . '.pm'});
	my @subroles;
	if (-d $include_dir . $package_this ) {
		@subroles = File::Find::Rule->file()->maxdepth(1)->name('*.pm')->relative->in($include_dir . $package_this);
		foreach my $subrole (@subroles) {
			require $package_aspath . '/' . $subrole;
			$subrole =~ s/\.pm//; # Remove .pm
			# Store the subrole's exported aliases in a fully qualified hash with the fully qualified subrole as key
			# We can't apply the role here in case the subrole modifies methods (not yet) declared in this role
			${$package_fqpn . '::subroles'}->{$package_fqpn . '::' . $subrole} = ${$package_fqpn . '::' . $subrole . '::aliases'};
		}
	}
	# Export own aliases
	foreach my $alias (@{$package_fqpn . '::methods'}) {
		${$package_fqpn . '::aliases'}->{-alias}->{$alias} = $package_this . '_' . $alias;
		push(@{${$package_fqpn . '::aliases'}->{-excludes}}, $alias);
	}
	use strict;
}

INIT {
	no strict;
	foreach my $subrole_fqpn (keys %{${__PACKAGE__ . '::subroles'}}) {
		# Apply the role, using the exported aliases from the subrole
		with $subrole_fqpn => ${__PACKAGE__ . '::subroles'}->{$subrole_fqpn};
	}
}

use strict;

#requires qw(columns datatype decimals signed allownull default decimalseparator thousandseparator);

after 'BUILD' => sub {
	my $self    = shift;
	my $hr_args = shift;
	# Initialize default values if not better left at undef
};

after 'Check' => sub {
	my $self = shift;
	print ("Checking Flatfile constraints [" . $self->name . "]...");

	my $previousfield;
	# Search first flatfield
	for (0 .. $#{$self->columns}) {
		if (defined $self->flatfield_start->[$_]) { $previousfield = $_; last; }
	}
	if (!defined $previousfield) { return; }    # Interface does not contain flatfields
	for (1 .. $#{$self->columns}) {
		# Skip check for fields we're not going to use due to not being (fully) configured.
		if (!(defined $self->flatfield_start->[$_] and defined $self->flatfield_length->[$_])) {
			next;
		}
		if ($self->flatfield_start->[$_] <= $self->flatfield_start->[$previousfield]) {
			Carp::confess("Flatfield_start is not always increasing: Column [" . $self->columns->[$_] . "] doesn't start after [" . $self->columns->[$previousfield] . "]");
		}
		if ($self->flatfield_start->[$_] < $self->flatfield_start->[$previousfield] + $self->flatfield_length->[$previousfield]) {
			Carp::confess("Flatfields [" . $self->columns->[$previousfield] . "] and [" . $self->columns->[$_] . "] overlap");
		}
		$previousfield = $_;
	} 
	print ("[OK]\n");
};

after 'ReConfigureFromHash' => sub {
	my $self = shift;
	$self->clear_flat_mask;
};

method WriteRecord (HashRef $hr_data !, HashRef $hr_options ?) {
	if (defined $hr_options and defined $hr_options->{encoding_out} and !defined $hr_options->{encoding_in}) {
		Carp::confess "encoding_out supplied without encoding_in."
	}
	my $mask = "";
	my @data;
	my $flatline_counter = 0;
	# Maak printf-mask als deze nog niet bestaat
	if (!$self->has_flat_mask) {
		$self->clear_flat_columns;
		my $ar_flat_columns = [];
		foreach my $index (0 .. $#{$self->columns}) {
			if (!(defined $self->flatfield_start->[$index] and defined $self->flatfield_length->[$index])) {
				# Field is missing interface_start, interface_length or both, skip it.
				next;
			}
			if ($flatline_counter > $self->flatfield_start->[$index]) {
				Carp::confess(  "Error in interface ["
							  . $self->tablename
							  . "]: field ["
							  . $self->columns->[$index]
							  . "] starts at position ["
							  . $self->flatfield_start->[$index]
							  . "] but we have already [$flatline_counter] bytes of data.");
			} ## end if ($flatline_counter ...
			if ($flatline_counter < $self->flatfield_start->[$index]) {
				# Defined fields are non-contiguous, inserting filler
				$mask .= " " x ($self->flatfield_start->[$index] - $flatline_counter);
				$flatline_counter = $self->flatfield_start->[$index];
			}
			$mask .= '%';
			if ($self->{internal_datatype}->[$index]->{type} < Interfaces2::DATATYPE_NUMERIC) { # Datatypes stored as text
				$mask .= "-" . $self->flatfield_length->[$index] . '.' . $self->flatfield_length->[$index] . "s";
			} elsif ($self->signed->[$index] eq 'Y') {
				$mask .= "0" . $self->flatfield_length->[$index] . ($] < 5.012 ? "s" : "d");
			} else {
				$mask .= "0" . $self->flatfield_length->[$index] . ($] < 5.012 ? "s" : "u");
			}
			$flatline_counter += $self->flatfield_length->[$index];
			push(@{$ar_flat_columns}, $index);
		} 
		$self->flat_mask($mask);
		$self->flat_columns($ar_flat_columns);
	} 
	my $evalstring;
	foreach my $index (@{$self->flat_columns}) {
		my $datafield;
		my $columnname = $self->columns->[$index];
		if ($self->{internal_datatype}->[$index]->{type} < Interfaces2::DATATYPE_NUMERIC) { # Datatypes stored as text
			# Text
			$datafield = $hr_data->{$columnname} // $self->default->[$index] // '';
		} else {
			# Numeric
			if (($hr_data->{$columnname} // '')  eq '') {
				$datafield = $self->default->[$index] // 0;
			} else {
				if ($hr_data->{$columnname} =~ /[^-.0-9]/) { # Check if field contains characters not supposed to be present in numeric values
					Data::Dump::dd($hr_data);
					print("Column [$index]\n");
					Carp::confess('Interface [' . $self->name . '] datatype [' . $self->{datatype}->[$index] . '] column [' . $columnname . '] error converting data [' . $hr_data->{$columnname} . ']');
				} else {
					# MinMax boundary check and fix
					$datafield = 0 + $self->minmax($index, $hr_data->{$columnname});
				}
			}
			given ($self->{internal_datatype}->[$index]->{type}) {
				when (Interfaces2::DATATYPE_NUMERIC) {
					$datafield = int($datafield); # Truncaten...getallen achter de komma kunnen weg.
				}
				when ([ Interfaces2::DATATYPE_FLOATINGPOINT, Interfaces2::DATATYPE_FIXEDPOINT ]) {
					if (($self->{decimals}->[$index] // 0) > 0) {
						$datafield *= 10**$self->{decimals}->[$index];
						# Destroy remaining decimals (not needed, because sprintf("%u" or "%d") doesn't write decimals.
						# But only v5.012+ because before that we're using %s to print
						if ($] < 5.012) {
							$datafield = int($datafield);
						}
					}
				}
			}
		}
		# If output-encoding is supplied, encode it
		if (defined $hr_options and defined $hr_options->{encoding_in} and defined $hr_options->{encoding_out}) {
			$datafield = Encode::encode($hr_options->{encoding_out}, Encode::decode($hr_options->{encoding_in}, $datafield));
		}
		# Truncate field to maximum allowed length
		$datafield = substr($datafield, 0, $self->flatfield_length->[$index]);
		push(@data, $datafield);
	} 
	return sprintf ($self->flat_mask, @data);
} ## end sub WriteRecord 

# ReadRecordUnpack ($self, $textinput)
# Parses $textinput using unpack and returns $hr_data
method ReadRecordUnpack (Str $textinput) {
	my $hr_returnvalue = {};
	my ($CurrentColumnName, $CurrentColumnValue, $CurrentColumnDecimals, $unpack_mask);
	if (! $self->has_flat_mask_unpack) {
		# Build unpackmask
		my $flatline_counter = 0;
		for my $index (0 .. $#{$self->columns}) {
			if (!(defined $self->flatfield_start->[$index] and defined $self->flatfield_length->[$index])) {
				# Field is missing interface_start, interface_length or both, skip it.
				next;
			}
			if ($flatline_counter > $self->flatfield_start->[$index]) {
				Carp::confess(  "Error in interface ["
							  . $self->name
							  . "]: field ["
							  . $self->columns->[$index]
							  . "] starts at position ["
							  . $self->flatfield_start->[$index]
							  . "] but we have already [$flatline_counter] bytes of data.");
			} ## end if ($flatline_counter ...)
			if ($flatline_counter < $self->flatfield_start->[$index]) {
				# Defined fields are non-contiguous, inserting filler
				$unpack_mask .= 'x' . ($self->flatfield_start->[$index] - $flatline_counter);
				$flatline_counter = $self->flatfield_start->[$index];
			}
			$unpack_mask .= "A" . $self->flatfield_length->[$index];
			$flatline_counter += $self->flatfield_length->[$index];
		} ## end for (0 .. $#{$self->columns...})
		$self->has_flat_mask_unpack($unpack_mask);
	} ## end if (!defined $Interfaces2::FlatFile::UnpackMask)
	my @datalist = unpack ($self->has_flat_mask_unpack, $textinput);
	for my $index (0 .. $#{$self->columns}) {
		$CurrentColumnName     = $self->{columns}->[$index];
		$CurrentColumnDecimals = $self->{decimals}->[$index];
		undef $CurrentColumnValue;
		if (!(defined $self->{flatfield_start}->[$index] and defined $self->{flatfield_length}->[$index])) {
			# Field is missing interface_start, interface_length or both, skip it.
			#Carp::carp("Field [$CurrentColumnName] is missing flatfield_start, flatfield_length or both, skip it.");
			next;
		}
		my $field_value;
		if ($self->{internal_datatype}->[$index]->{type} >= Interfaces2::DATATYPE_NUMERIC) {
			if ($CurrentColumnDecimals == 0) {
				if ($datalist[0] eq '') {
					shift(@datalist);
					$field_value = 0;
				} else {
					$field_value = 0 + shift(@datalist);
					# MinMax boundary check and fix
					$field_value = $self->minmax($index, $field_value);
				}
			} else {
				# Remove leading zeroes
				$field_value =~ s/^0*//;
				# Insert period
				if (length ($field_value) <= $CurrentColumnDecimals) {
					$field_value = '0.' . '0' x ($CurrentColumnDecimals - length ($field_value)) . $field_value;
				} else {
					$field_value =~ s/([0-9]{$CurrentColumnDecimals})$/\.$1/;
				}
			}
		} else {
			$field_value = shift(@datalist);
			s/^(\s*)(.*?)(\s*)$/$2/ for $field_value; # Trim whitespace 
			# Fill empty fields with that field's default value, if such a value is defined
			if ($field_value eq '') {
				$field_value = $self->{default}->[$index];
			} 
		} 
		$hr_returnvalue->{$CurrentColumnName} = $field_value;
	} 
	return $hr_returnvalue;
} ## end sub ReadRecordUnpack

method ReadRecord (Str $textinput) {
	if (ref($textinput) ne '') {
		Carp::confess "1st Argument passed is a reference (expected text)";
	}
	my $hr_returnvalue = {};
	my ($current_column_name, $current_field_start, $current_field_length, $current_field_decimals, $current_field_default);
	my $decimalseparator;
	if ($self->has_decimalseparator) {
		$decimalseparator = $self->decimalseparator;
	} else {
		$decimalseparator = '.';
	}
	# Check if textinput is long enough
	if (defined $self->{FlatFile_recordlength} and length($textinput) < $self->{FlatFile_recordlength}) {
		Data::Dump::dd($textinput);
		Carp::confess("field [" . $self->columns->[$_] . "] [" . $self->flatfield_start->[$_] . "," . $self->flatfield_length->[$_] . "] is outside the text inputstring (length [" . length($textinput) . "])");
	}
	foreach my $index (0 .. $#{$self->columns}) {
		my $field_value;
		$current_column_name = $self->columns->[$index];
		$current_field_start = $self->flatfield_start->[$index];
		$current_field_length = $self->flatfield_length->[$index];
		$current_field_decimals = $self->decimals->[$index];
		if (!(defined $current_field_start and defined $current_field_length)) {
			# Field is missing interface_start, interface_length or both, skip it.
			#			Carp::carp("Field [$current_column_name] is missing flatfield_start, flatfield_length or both, skip it.");
			next;
		}
		$field_value = substr ($textinput, $current_field_start, $current_field_length);
		# The two regexes below took respectively 1us/call and 478ns/call
		$field_value =~ s/^\s+//;
		$field_value =~ s/\s+$//;
		# Controleren of datatypes[] gevuld is.
		if (!defined $self->{internal_datatype}->[$index]) {
			Carp::confess("Datatypes not defined huh?");
		}
		# Lege velden weggooien.
		if ($field_value eq '') { $field_value = undef; }
		$current_field_default = $self->{default}->[$index];
		given ($self->{internal_datatype}->[$index]->{type}) {
			when (Interfaces2::DATATYPE_TEXT) {
				$field_value //= "" . $current_field_default;
			}
			when (Interfaces2::DATATYPE_NUMERIC) {
				$field_value = defined $field_value ? 0 + $field_value : 0 + $current_field_default;
				$field_value = $self->minmax($index, $field_value);
			}
			when ([Interfaces2::DATATYPE_FLOATINGPOINT, Interfaces2::DATATYPE_FIXEDPOINT]) {
#print("Pre-minmax [$field_value] ");
				if (!defined $field_value) {
					$field_value = $self->minmax($index, 0 + $current_field_default);
				} else {
					$field_value =~ s/[$decimalseparator]/\./g;                      # Change the decimal-sign to .
					$field_value /= 10**$current_field_decimals;
#print("Post decimalfix [$field_value]\n");
					$field_value = $self->minmax($index, 0 + $field_value);
#print("Post [$field_value]\n");
				}
			}
		}
		$hr_returnvalue->{$current_column_name} = $field_value;
	} ## end for (0 .. $#{$self->columns...
	return $hr_returnvalue;
} ## end sub ReadRecord 

# ReadData ($filename) returns ar_data
method ReadData (Str $filename !) {
	my $ar_returnvalue = [];
	open (FLATFILE, '<', $filename) or (Carp::confess("Cannot open file [$filename]: $!") and return);
	while (<FLATFILE>) {
		chomp;
		push (@{$ar_returnvalue}, __PACKAGE__::ReadRecordUnpack($self, $_));
	}
	close (FLATFILE);
	return $ar_returnvalue;
} ## end sub ReadData 

# WriteData ($filename, $ar_data)
method WriteData (Str $filename !, ArrayRef $ar_data !) {
	open (FLATFILE, '>', $filename) or (Carp::confess("Cannot open file [$filename]: $!") and return);
	foreach my $hr_data (@{$ar_data}) {
		print FLATFILE __PACKAGE__::WriteRecord($self, $hr_data) . "\r\n";
	}
	close (FLATFILE);
} ## end sub WriteData

1;

=head1 NAME

Interfaces::FlatFile - FlatFile format extension to Interfaces::Interface

=head1 VERSION

This document refers to Interfaces::FlatFile version 0.10.

=head1 SYNOPSIS

  use Interfaces::Interface;
  my $interface = Interfaces::Interface->new();
  $interface->ReConfigureFromHash($hr_config);
  my $ar_data = $interface->ReadData("foobar.txt");
  $interface->WriteData("foobar.txt", $ar_data);

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

Parses the supplied line of text as a fixed-length record using substr. Returns a hashref with the data with the 
columnnames as key.

=item * C<$interface-E<gt>ReadRecordUnpack($line_of_text);>

Parses the supplied line of text as a fixed-length record using unpack. Returns a hashref with the data
with the columnnames as key.

=item * C<$interface-E<gt>WriteRecord($hr_data);>

Converts the supplied hashref datarecord to a line of text. Returns a string of text containing the
fixed-length encoded data.

=item * C<$interface-E<gt>ReadData($fullpath_to_file);>

Reads the given file, decodes it and returns its data as an arrayref with a hashref per datarecord.
It is assumed that a LF or a CRLF seperates records.

=item * C<$interface-E<gt>WriteData($fullpath_to_file, $ar_data);>

Writes the supplied data in fixed-length format to the given file. If the file already existed, it is
overwritten, otherwise it is created.

=back

=head1 DEPENDENCIES

L<Interfaces::Interface>, L<Moose> and L<Carp>

=head1 AUTHOR

The original author is Herbert Buurman

=head1 LICENSE

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See L<perlartistic>.

=cut

