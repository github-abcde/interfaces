package Interfaces::JSON;

use 5.010;
use Smart::Comments;
use Moose::Role;    # automatically turns on strict and warnings
use JSON;
use Scalar::Util;
use MooseX::Method::Signatures;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater

BEGIN {
	$Interfaces::JSON::VERSION = 1.00; # 11-02-2014
}

has 'JSON_ar_useinfile' => (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 1,);
has 'JSON_hr_columns' => (is => 'rw', isa => 'HashRef[Int]', lazy_build => 1,);
has 'JSON_fieldmask' => (is => 'rw', isa => 'HashRef[Str]', lazy_build => 1,);

after 'BUILD' => sub {
	my $self = shift;
	# Initialize our own attributes with default values and set all columns with a displayname to be used
	Interfaces::JSON::ConfigureUseInFile($self, $self->displayname());
};

after 'Check' => sub {
	my $self = shift;
#	print ("Checking JSON constraints\n");
	# Check if all fields that are marked with "useinfile" have a displayname
	for (0 .. $#{$self->columns}) {
		if ($self->JSON_ar_useinfile->[$_] && !($self->displayname->[$_] // "")) {
			Interfaces::Interface::Crash("JSON field [" . $self->columns->[$_] . "] is configured to be used, but has no displayname");
		}
	} ## end for (0 .. $#{$self->columns...
};

after 'ReConfigureFromHash' => sub {
	my $self = shift;
	# Init datatypes for speed (saves having to do regexes for each ReadRecord call)
	foreach my $index (0 .. $#{$self->columns}) {
		$self->{JSON_hr_columns}->{$self->columns->[$index]} = $index;
		$self->{JSON_ar_useinfile}->[$index] = 1;
	}
};

after 'AddField' => sub {
	my ($self, $hr_config) = @_;
	my $last_index = $#{$self->columns};
	$self->{JSON_hr_columns}->{$hr_config->{fieldname}} = $last_index;
	$self->{JSON_ar_useinfile}->[$last_index] = 1;
};

# WriteRecord ($hr_data) returns string
method WriteRecord(HashRef $hr_data !, HashRef $hr_options ?) {
	my @skip_these_columns = grep { !$self->{JSON_ar_useinfile}->[$_]; } (0 .. $#{$self->{columns}});
	my %columnnames = map { $_ => $self->{columns}->[$_]; } @skip_these_columns;
	delete $hr_data->{$_} for values(%columnnames);
	return JSON::to_json($hr_data, { pretty => $hr_options->{pretty} });
} ## end sub WriteRecord

# WriteData ($filename, $ar_data, $hr_options)
# Options consist of:	header = 0 | 1 # Write a header to the file (default = 1)
#						append = 0 | 1 # Append to file (default = 0)
#						encoding = <value> # ascii, iso-8859-1, utf8 or any other encoding supported by Encode (default = utf8)
method WriteData(Str $filename !, ArrayRef $ar_data !, HashRef $hr_options ?) {
	$hr_options->{append} //= 0;
	$hr_options->{encoding} //= 'utf8';
	my $num_records = 0;
	open (my $filehandle, '>:' . $hr_options->{encoding}, $filename) or Interfaces::Interface::Crash("Error opening outputfile [$filename]: $!");
	print $filehandle '{ "' . $self->name . '": [' . "\r\n";
	foreach my $hr_data (@{$ar_data}) {
		if ($num_records++ > 0) {
			print $filehandle ',' . "\r\n";
		}	
		print $filehandle Interfaces::JSON::WriteRecord($self, $hr_data, $hr_options);
	}
	print $filehandle "\r\n" . ']}' . "\r\n";
	close ($filehandle);
} ## end sub WriteData ($$$)

# ReadRecord ($node) returns $hr_record
method ReadRecord(Str $inputstring !) {
	# Use all columns specified in useinfile
	my $hr_returnvalue = {};
	my $decimalseparator = $self->{decimalseperator};
	my $hr_inputdata = JSON::decode_json($inputstring);
	foreach my $column_index (0 .. $#{$self->{columns}}) {
		my $name = $self->{columns}->[$column_index];
		my $field_value = $hr_inputdata->{$name};
		my $CurrentColumnDecimals = $self->{decimals}->[$column_index];
		my $CurrentColumnDatatype = $self->{internal_datatype}->[$column_index];
		if ($CurrentColumnDatatype >= $Interfaces::Interface::DATATYPE_NUMERIC) {
			Interfaces::Interface::Crash("Field [$name] does not contain numeric data: [$field_value]\n") if !Scalar::Util::looks_like_number($field_value); #if ($field_value !~ /^[0-9\Q${decimalseparator}\E]*$/x); # Prof: 5239806	29.5s	10479612	11.9s
			# Check if there are trailing negators, and fix it to be a heading negator
			if (substr($field_value,-1) eq '-') {
				#$field_value =~ s/^(.*)-$/-$1/; # 11.2s, 2.67s
				$field_value = '-' . substr($field_value, 0, -1);
			} elsif ($field_value eq '') {
				$field_value = '0';
			}
			if ($CurrentColumnDatatype > $Interfaces::Interface::DATATYPE_NUMERIC && $CurrentColumnDecimals) { # Field is a type that has decimals (FLOAT, NUMERIC etc)
				# Compensate for decimalseperators other than period, change them to .
				if ($decimalseparator ne '.' && !($field_value =~ s/\Q${decimalseparator}\E/./x) || index($field_value, '.') + 1 == 0) {
					# There were no $decimalseperators present and there is no period present in $field_value
					$field_value .= '.';
				}
				$field_value = "0$field_value" if substr($field_value, 0, 1) eq '.';
				$field_value .= '0' x $CurrentColumnDecimals;
				$field_value =~ s/(\.[0-9]{$CurrentColumnDecimals}).+/$1/x;    # Trim trailing digits to max $CurrentColumnDecimals
			}
			# Check if field is numeric
			$hr_returnvalue->{$name} = 0 + $field_value;
		} elsif (defined $field_value) {
			if ($field_value eq '') {
				# Store default value or undef (if no default value exists)
				if (defined $self->{default}->[$column_index]) {
					$hr_returnvalue->{$name} = $self->{default}->[$column_index];
				}
				# else don't store the value at all..saves a key-value pair
			} else {
				$hr_returnvalue->{$name} = $field_value;
			}
		}
	}
	return $hr_returnvalue;
} ## end sub ReadRecord 

# ConfigureUseInFile ($ar_headers)
# Matches headers in $ar_headers with @self->displayname and sets useinfile=1 for the matching headers
# Also sets the matching header's fileindex to the columnnumber (0-based) where the header matched in the arrayref.
method ConfigureUseInFile (ArrayRef $ar_headers !) {
	# Zero all useinfiles and fileindex
	for (0 .. $#{$self->columns}) {
		$self->{JSON_ar_useinfile}->[$_] = 0;
	}
	my $num_file_index = 0;
	foreach my $header (@{$ar_headers}) {
		my $HeaderIndex = SleLib::IndexOf($header, @{$self->{displayname}});
		if ($HeaderIndex >= 0) {
			$self->{JSON_ar_useinfile}->[$HeaderIndex] = 1;
		} else {
			Carp::carp("Header [$header] not found\n");
		}
		$num_file_index++;
	} ## end foreach my $header (@{$ar_headers...})
} ## end sub ConfigureUseInFile ($$)

# Configure use-in-file manually, with a supplied { file_column_name => interface_column_nr }
method ConfigureUseInFile_Manual(HashRef $hr_headerindex !) {
	# Zero all useinfiles and fileindex
	for (0 .. $#{$self->columns}) {
		$self->{JSON_ar_useinfile}->[$_] = 0;
	}
	foreach my $file_column (keys %{$hr_headerindex}) {
		$self->{JSON_ar_useinfile}->[$hr_headerindex->{$file_column}] = 1;
	}
}

# ReadFile ($filename, [$hr_options]) returns \@data with \%records
method ReadData(Str $filename !, HashRef $hr_options ?) {
	my $ar_returnvalue = [];
	local $/ = $self->record_delimiter;
	open (my $filehandle, '<', $filename) or Interfaces::Interface::Crash("Cannot open file [$filename]: $!");
	# Read interface tag
	my $name = readline($filehandle); # { "name" : [
	while (<$filehandle>) {
		chomp;
		s/,$//;
		Data::Dump::dd("Read from file [$_]");
		if ($_ eq ']}') { last; } # Skip closing tag to $name
		push (@{$ar_returnvalue}, Interfaces::JSON::ReadRecord($self, $_));
	} ## end while (<DELIMFILE>)
	close ($filehandle);
	return $ar_returnvalue;
} ## end sub ReadData ($$)

1;

=head1 NAME

Interfaces::JSON - JSON format extension to Interfaces::Interface

=head1 VERSION

This document refers to Interfaces::JSON version 1.0.0.

=head1 SYNOPSIS

  use Interfaces::Interface;
  my $interface = Interfaces::Interface->new();
  $interface->ReConfigureFromHash($hr_config);
  my $ar_data = $interface->JSON_ReadData("foobar.json");
  $interface->JSON_WriteData("foobar.json", $ar_data);

=head1 DESCRIPTION

This module extends the Interfaces::Interface with the capabilities to read from - and
write to files in a JSON file.

=head2 Attributes for C<Interfaces::JSON>

=over 4

=head2 Methods for C<Interfaces::JSON>

=over 4

=item * C<$interface-E<gt>ConfigureUseInFile($ar_headers);>

Supplied an arrayref of strings, matches those with $self->displayname to determine which columns in
the file are to be linked with which columns of the interface. Is automatically called from ReadData,
but not from ReadRecord.

=item * C<$interface-E<gt>ReadRecord($inputstring);>

Parses the supplied string. Returns an hashref with the data with the columnnames as key. Only reads the columns configured by ConfigureUseInFile.

=item * C<$interface-E<gt>WriteRecord($hr_data);>

Converts the supplied hashref datarecord to a line of text. Returns a string of text containing the
JSON data.

=item * C<$interface-E<gt>ReadData($fullpath_to_file);>

Reads the given file and returns its data as an arrayref with a hashref per datarecord.

=item * C<$interface-E<gt>WriteData($fullpath_to_file, $ar_data, $hr_options);>

Writes the given data to the file specified by $fullpath_to_file.

=back

=head1 DEPENDENCIES

L<Interfaces::Interface>, L<Moose> and L<Carp>.

=head1 AUTHOR

The original author is Herbert Buurman

=head1 LICENSE

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See L<perlartistic>.

=cut

