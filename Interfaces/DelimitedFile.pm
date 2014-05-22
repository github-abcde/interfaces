package Interfaces::DelimitedFile;
# Version 0.2	29-09-2011
# previously Copyright (C) OGD 2011
# previously Copyright (C) THR 2011
# Copyright released by THR in 2013

# RFC 4180-compliant.
use 5.010;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater
#use Devel::Size;
use Moose::Role;    # automatically turns on strict and warnings
use MooseX::Method::Signatures;

BEGIN {
	@Interfaces::DelimitedFile::methods = qw(ReadRecord WriteRecord ReadData WriteData ConfigureUseInFile);
}

has 'field_delimiter'  => (is => 'rw', isa => 'Str',  lazy_build => 1,);
has 'record_delimiter' => (is => 'rw', isa => 'Str',  lazy_build => 1,);
has 'DelimitedFile_ar_useinfile'			=> (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 0,);
has 'DelimitedFile_hr_fileindex'			=> (is => 'rw', isa => 'HashRef[Int]', lazy_build => 0,);
has 'DelimitedFile_ar_writemask'			=> (is => 'rw', isa => 'Str', lazy_build => 0,);
	
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

#requires qw(columns displayname datatype decimals signed allownull default decimalseparator thousandseparator);

# TODO:
# Implement allownull when reading (!allownull -> requires default)

after 'BUILD' => sub {
	my $self = shift;
	# Initialize our own attributes with default values and set all columns with a displayname to be used
	$self->field_delimiter(',');
	$self->record_delimiter("\r\n");
	$self->DelimitedFile_ConfigureUseInFile($self->displayname());
};

after 'Check' => sub {
	my $self = shift;
	print ("Checking DelimitedFile constraints...");
	# Check if all fields that are marked with "useinfile" have a displayname
	for (0 .. $#{$self->columns}) {
		if ($self->{ar_useinfile}->[$_] and !($self->displayname->[$_] // "")) {
			Carp::confess("DelimitedFile field [" . $self->columns->[$_] . "] is configured to be used, but has no displayname");
		}
	}
	# Check if the delimiter is set
	if (!$self->has_field_delimiter or $self->field_delimiter eq '') {
		Carp::confess("Field delimiter not set");
	}
	if (!$self->has_record_delimiter or $self->record_delimiter eq '') {
		Carp::confess("Record delimiter not set");
	}
	print("[OK]\n");
};

after 'ReConfigureFromHash' => sub {
	my $self = shift;
	$self->{DelimitedFile_ar_writemask} = undef;
};

method DelimitedHeader {
	if (!$self->has_field_delimiter) {
		Carp::confess("Field delimiter is not set");
	}
	# Returned alleen die displaynames waarvan useinfile op 1 staat.
	return join ($self->{field_delimiter}, map { $self->{displayname}->[$_]; } grep { $self->{ar_useinfile}->[$_]; } (0 .. $#{$self->{columns}}));
} ## end sub DelimitedHeader ($)

# WriteRecord ($hr_data) returns string
method WriteRecord (HashRef $hr_data !) {
	my $mask    = "";
	my @data;
	if (!$self->has_field_delimiter or !$self->has_record_delimiter) {
		Carp::confess("Field- or Record-delimiter is not set");
	}
	my $field_delimiter = $self->field_delimiter;
	# Filter kolomindices die geen DelimitedFile_ar_useinfile hebben
	my @process_these_columns = grep { $self->{DelimitedFile_ar_useinfile}->[$_]; } (0 .. $#{$self->{columns}});
	my %columnnames = map { $_ => $self->{columns}->[$_]; } @process_these_columns;
	# Maak printf-masks
	for my $index (@process_these_columns) {
		if (!defined $self->{DelimitedFile_ar_writemask}->[$index]) {
			$self->{DelimitedFile_ar_writemask}->[$index] = "%";
			given ($self->{internal_datatype}->[$index]->{type}) {
				when (Interfaces::DATATYPE_TEXT) {
					$self->{DelimitedFile_ar_writemask}->[$index] .= "s";
				}
				when (Interfaces::DATATYPE_NUMERIC) {
					$self->{DelimitedFile_ar_writemask}->[$index] .= $self->{signed}->[$index] eq 'Y' ? "d" : "u";
				}
				when ([ Interfaces::DATATYPE_FLOATINGPOINT, Interfaces::DATATYPE_FIXEDPOINT ]) {
					$self->{DelimitedFile_ar_writemask}->[$index] .= "." . $self->{decimals}->[$index] . "f";
				}
				when (Interfaces::DATATYPE_DATETIME) {
					$self->{DelimitedFile_ar_writemask}->[$index] .= "s";
				}
				default {
					$self->{DelimitedFile_ar_writemask}->[$index] .= "s";
				}
			} ## end given
		} ## end if (!defined $Interfaces::DelimitedFile::hr_writemask...)
	} ## end for my $index (0 .. $#{...})
	if (!defined $self->{DelimitedFile_ar_writemask}) {
		Carp::confess("No columns were identified as being used in file (have you forgot to use ConfigureUseInFile?).");
	}
	my $evalstring;
	foreach my $index (@process_these_columns) { 
		if (!defined $self->{DelimitedFile_ar_writemask}->[$index]) {
			$data[$index] = 'ERROR_NO_WRITE_MASK';
			next;
		} else {
			Carp::carp("Delmitedfile_ar_writemask [" . $self->{DelimitedFile_ar_writemask}->[$index] . "]") if ($Interfaces::DEBUGMODE);
		}
		my $columnname = $columnnames{$index};
		my $field_value = (defined $hr_data->{$columnname}) ? $hr_data->{$columnname} : $self->{default}->[$index];

		if (defined $field_value) {
			if ($self->{internal_datatype}->[$index]->{type} >= Interfaces::DATATYPE_NUMERIC) { # Numeric with or without decimals
				# MinMax boundary check and fix
#print("Pre-minmax [$field_value]\n");
				$field_value = $self->minmax($index, $field_value);
#print("Post-minmax [$field_value]\n");
			}
			# Escape "'s in character-data with another " RFC 4180 2.7
			if (index($field_value, '"') + 1) { # 7772520	6.33s
				$field_value =~ s/"/""/g;
				$field_value = "\"$field_value\"";
			} elsif (index($field_value, $field_delimiter) + 1 or index($field_value, $self->{record_delimiter}) + 1) {
				$field_value = "\"$field_value\"";
			}
		} else {
			$field_value = '';
		}
		$data[$index] = $field_value;
	} ## end foreach (0 .. $#{$self->columns...})
	return join ($field_delimiter, map { sprintf ($self->{DelimitedFile_ar_writemask}->[$_], $data[$_]); } @process_these_columns);
} ## end sub WriteRecord

# WriteData ($filename, $ar_data, $hr_options)
# Options consist of:	header = 0 | 1 # Write a header to the file (default = 1)
#						append = 0 | 1 # Append to file (default = 0)
method WriteData (Str $filename !, ArrayRef $ar_data !, HashRef $hr_options ?){
	if (!$self->has_field_delimiter or !$self->has_record_delimiter) {
		Carp::confess("Field- or Record-delimiter is not set");
	}
	$hr_options->{header} //= 1;
	$hr_options->{append} //= 0;
	$hr_options->{encoding} //= 'utf8';
	if ($hr_options->{append}) {
		open (DELIMFILE, '>>:' . $hr_options->{encoding}, $filename) or (Carp::confess("Error opening outputfile [$filename]: $!") and return);
	} else {
		open (DELIMFILE, '>:' . $hr_options->{encoding}, $filename) or (Carp::confess("Error opening outputfile [$filename]: $!") and return);
	}
	if ($hr_options->{header}) {
		print DELIMFILE __PACKAGE__::DelimitedHeader($self) . $self->record_delimiter;
	}
	foreach my $hr_data (@{$ar_data}) {
		print DELIMFILE __PACKAGE__::WriteRecord($self, $hr_data) . $self->record_delimiter;
	}
	close (DELIMFILE);
} ## end sub WriteData ($$$)

# ReadRecord ($data) returns $hr_record
method ReadRecord (Str $inputstring !) {
	if (!$self->has_field_delimiter) {
		Carp::confess("Field-delimiter is not set");
	}
	# Use all columns specified in useinfile
	my $hr_returnvalue = {};
	my $input_column_index  = 0;
	my $output_column_index = -1;
	my $field_value;
	my $delimiter         = $self->field_delimiter;
	my $thousandseparator = $self->thousandseparator;
	my $decimalseparator  = $self->decimalseparator;
	my ($CurrentColumnDecimals, $CurrentColumnDatatype);
	while ($inputstring) {
		undef $field_value;
		$output_column_index = $self->{DelimitedFile_hr_fileindex}->{$input_column_index};
		if (!defined $output_column_index) {
			Carp::carp("Line read: [$inputstring]");
			Carp::confess("Column index [$input_column_index] not found in DelimitedFile_hr_fileindex. Have you used ConfigureUseInFile or ParseHeaders? (Or are there more fields in the file than you defined)");
		}
		$CurrentColumnDecimals = $self->{decimals}->[$output_column_index];
		$CurrentColumnDatatype = $self->{datatype}->[$output_column_index];
		if (substr($inputstring,0,1) eq '"') { # 7707749	6.07s	
			$field_value = $inputstring;
			if ($inputstring =~ /^"(([^"]|"")+)"(?:[$delimiter]|$)/p) {
				($field_value, $inputstring) = ($1, ${^POSTMATCH});
				# Unescape escaped quotes
				$field_value =~ s/""/"/g;
			} else {
				Carp::confess("Parsing error with data [$inputstring], current index [$input_column_index]");
			}
		} else {
			$field_value = $inputstring;
			if ($inputstring =~ /^([^$delimiter"]*)(?:[$delimiter]|$)/p) {
				($field_value, $inputstring) = ($1, ${^POSTMATCH});
			}
		} ## end else [ if ($inputstring =~ /^"/)]
		if ($output_column_index >= 0) {
			if ($self->{internal_datatype}->[$output_column_index]->{type} >= Interfaces::DATATYPE_NUMERIC) {
				if ($field_value eq '') {
					$field_value = '0';
				} elsif ($thousandseparator) {
					# Remove thousandseparator, if present
					while (my $ts_loc = index($field_value, $thousandseparator) + 1) {
						substr($field_value, $ts_loc - 1, 1) = '';
					}
				}
				# MinMax boundary check and fix
				$field_value = $self->minmax($output_column_index, $field_value);
				if ($CurrentColumnDecimals and $self->{internal_datatype}->[$output_column_index]->{type} > Interfaces::DATATYPE_NUMERIC) { # Field is a type that has decimals (FLOAT, NUMERIC etc)
					# Compensate for decimalseparators other than period, change them to .
					if (not $field_value =~ s/\Q${decimalseparator}\E/\./ and not index($field_value, '.') + 1) {
						# There were no $decimalseparators present and there is no period present in $field_value
						$field_value .= '.';
					}
					$field_value = "0$field_value" if substr($field_value, 0, 1) eq '.'; # 971565	1.45s
					$field_value .= '0' x $CurrentColumnDecimals; # 971565	725ms
					$field_value =~ s/(\.[0-9]{$CurrentColumnDecimals}).+/$1/;    # Trim trailing digits to max $CurrentColumnDecimals # 971565	9.83s	3886260	3.86s
				}
				$hr_returnvalue->{$self->{columns}->[$output_column_index]} = 0 + $field_value;
			} else {
				if ($field_value eq '') {
					# Store default value or undef (if no default value exists)
					if (defined $self->{default}->[$output_column_index]) {
						$hr_returnvalue->{$self->{columns}->[$output_column_index]} = $self->{default}->[$output_column_index];
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
method ParseHeaders (Str $inputstring !) {
	if (!$self->has_field_delimiter or !$self->has_record_delimiter) {
		Carp::confess("Field- or Record-delimiter is not set");
	}
	# Zero all useinfiles and fileindex
	for (0 .. $#{$self->columns}) {
		$self->{DelimitedFile_ar_useinfile}->[$_] = 0;
		$self->{DelimitedFile_ar_fileindex}->[$_] = undef;
	}
	my $num_file_index = 0;
	my $delimiter      = $self->field_delimiter;
	while ($inputstring) {
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

# ConfigureUseInFile ($ar_headers)
# Matches headers in $ar_headers with @self->displayname and sets useinfile=1 for the matching headers
# Also sets the matching header's fileindex to the columnnumber (0-based) where the header matched in the arrayref.
method ConfigureUseInFile (ArrayRef $ar_headers !) {
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
method ReadData (Str $filename !, HashRef $hr_options ?) {
	if (ref($filename) ne '') {
		Carp::confess "1st Argument passed is a reference (expected text)";
	}
	if (!$self->has_field_delimiter or !$self->has_record_delimiter) {
		Carp::confess("Field- or Record-delimiter is not set");
	}
	no strict qw(refs);
	$hr_options->{no_header} = $hr_options->{no_header} // 0;
	$hr_options->{skip_header} = $hr_options->{skip_header} // 0;
	if ($hr_options->{no_header}) {
		$hr_options->{skip_header} = 0;
	}
	my $ar_returnvalue = [];
	my $old_INPUT_RECORD_SEPARATOR = $/;
	$/ = $self->record_delimiter;
	open (DELIMFILE, '<', $filename) or Carp::confess("Cannot open file [$filename]: $!");
	if (!$hr_options->{no_header}) {
		# There is a header
		my $Headers = <DELIMFILE>;
		chomp($Headers);
		if ($hr_options->{skip_header}) {
			if (scalar keys (%{$self->{DelimitedFile_hr_fileindex}}) == 0) {
				Carp::confess("ReadData called but no fields have been configured to use and the option to skip the header was given (which means no fields will be autoconfigured for use either).");
			}
		} else {
			&{__PACKAGE__ . '::ParseHeaders'}($self, $Headers);
		}
	}

	my $record;
	while (<DELIMFILE>) {
		chomp;
		$record = $_;
		# If a line contains an odd amount of doublequotes ("), then we'll need to continue reading until we find another line that contains an odd amount of doublequotes.
		# This is in order to catch fields that contain recordseparators (but are encased in ""'s).
		if (grep ($_ eq '"', split ('', $_)) % 2 == 1) { # 64771	8.75s
			# Keep reading data and appending to $record until we find another line with an odd number of doublequotes.
			while (<DELIMFILE>) {
				$record .= $_;
				if (grep ($_ eq '"', split ('', $_)) % 2 == 1) { last; }
			}
		} ## end if (grep ($_ eq '"', split...))
		push (@{$ar_returnvalue}, &{__PACKAGE__ . '::ReadRecord'}($self, $record));
	} ## end while (<DELIMFILE>)
	close (DELIMFILE);
	$/ = $old_INPUT_RECORD_SEPARATOR;
	use strict qw(refs);
	return $ar_returnvalue;
} ## end sub ReadData ($$)

1;

=head1 NAME

Interfaces::DelimitedFile - DelimitedFile format extension to Interfaces::Interface

=head1 VERSION

This document refers to Interfaces::Interface version 0.10.

=head1 SYNOPSIS

  use Interfaces::Interface;
  my $interface = Interfaces::Interface->new();
  $interface->ReConfigureFromHash($hr_config);
  $interface->Delimiter(',');
  my $ar_data = $interface->ReadData("foobar.csv");
  $interface->WriteData("foobar.csv", $ar_data);

=head1 DESCRIPTION

This module extends the Interfaces::Interface with the capabilities to read from - and
write to files in a character-delimited layout.

=head2 Attributes for C<Interfaces::DelimitedFile>

=over 4

=item * C<delimiter>
Contains delimiter character used to seperate fields in a record.

=item * C<usedinexcel>
Contains a boolean value to indicate whether the values need to be read in Microsoft Excel. This saves values as ="value" instead of just the value.

=item * C<decimalseparator>
Contains the character used as separator for numeric values between the whole part and the fractional part.

=item * C<thousandseparator>
Contains the character used as a separator of thousands, e.g.: 1,000,000.

=back

=head2 Methods for C<Interfaces::DelimitedFile>

=over 4

=item * C<$interface-E<gt>ReadRecord($line_of_text);>

Parses the supplied line of text as a character-delimited record. Returns a hashref with the data with the columnnames as key.

=item * C<$interface-E<gt>WriteRecord($hr_data);>

Converts the supplied hashref datarecord to a line of text. Returns a string of text containing the character-delimited data.

=item * C<$interface-E<gt>ReadData($fullpath_to_file);>

Reads the given file, decodes it and returns its data as an arrayref with a hashref per datarecord.
As per RFC 4180, records are terminated by a CRLF. Fields can contain CRLF as data, but need to be escaped using "".

=item * C<$interface-E<gt>WriteData($fullpath_to_file, $ar_data);>

Writes the supplied data in character-delimited format to the given file. If the file already existed, it is overwritten, otherwise it is created.

=item * C<$interface-E<gt>ConfigureUseInFile($ar_headers);>

Matches headers in $ar_headers with @self->displayname and sets useinfile=1 for the matching headers.
Also sets the matching header's fileindex to the columnnumber (0-based) where the header matched in the arrayref.
Used to match the index of the various columns in the data with the index of the matching columns in the interface

=back

=head1 DEPENDENCIES

L<Interfaces::Interface>, L<SleLib>, L<Moose> and L<Carp>

=head1 AUTHOR

The original author is Herbert Buurman

=head1 LICENSE

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See L<perlartistic>.

=cut

