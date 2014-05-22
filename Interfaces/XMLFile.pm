package Interfaces2::XMLFile;

use 5.010;
use Moose::Role;    # automatically turns on strict and warnings
use XML::Twig;
use MooseX::Method::Signatures;

BEGIN {
	$Interfaces::XMLFile::VERSION = 1.00; # 27-11-2013
}

has 'XMLFile_ar_useinfile' => (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 1,);
has 'XMLFile_hr_columns' => (is => 'rw', isa => 'HashRef[Int]', lazy_build => 1,);
has 'XMLFile_datatypes' => (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 1,);
has 'XMLFile_fieldmask' => (is => 'rw', isa => 'HashRef[Str]', lazy_build => 1,);
has 'data' => (is => 'rw', isa => 'Any', lazy_build => 1,);

# Scan for subroles
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

after 'BUILD' => sub {
	my $self = shift;
	# Initialize our own attributes with default values and set all columns with a displayname to be used
	Interfaces::XMLFile::ConfigureUseInFile($self, $self->displayname());
};

after 'Check' => sub {
	my $self = shift;
#	print ("Checking XMLFile constraints\n");
	# Check if all fields that are marked with "useinfile" have a displayname
	for (0 .. $#{$self->columns}) {
		if ($self->XMLFile_ar_useinfile->[$_] && !($self->displayname->[$_] // "")) {
			Crash("XMLFile field [" . $self->columns->[$_] . "] is configured to be used, but has no displayname");
		}
	} ## end for (0 .. $#{$self->columns...
};

after 'ReConfigureFromHash' => sub {
	my $self = shift;
	# Init datatypes for speed (saves having to do regexes for each ReadRecord call)
	foreach my $index (0 .. $#{$self->columns}) {
		given ($self->datatype->[$index]) {
			when (/^(?:CHAR|VARCHAR|DATE|TIME|DATETIME|ENUM)$/x) { $self->{XMLFile_datatypes}->[$index] = $Interfaces::Interface::DATATYPE_TEXT; }
			when (/^(?:TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT)$/x) { $self->{XMLFile_datatypes}->[$index] = $Interfaces::Interface::DATATYPE_NUMERIC; }
			when (/^(?:FLOAT|SINGLE|DOUBLE)$/x) { $self->{XMLFile_datatypes}->[$index] = $Interfaces::Interface::DATATYPE_FLOATINGPOINT; }
			when (/^(?:DECIMAL|NUMERIC)$/x) { $self->{XMLFile_datatypes}->[$index] = $Interfaces::Interface::DATATYPE_FIXEDPOINT; }
			default { Crash("Datatype [$_] unknown"); }
		}
		$self->{XMLFile_hr_columns}->{$self->columns->[$index]} = $index;
		$self->{XMLFile_ar_useinfile}->[$index] = 1;
	}
};

after 'AddField' => sub {
	my ($self, $hr_config) = @_;
	my $last_index = $#{$self->columns};
	given ($hr_config->{datatype}) {
		when (/^(?:CHAR|VARCHAR|DATE|TIME|DATETIME)$/x) { $self->{XMLFile_datatypes}->[$last_index] = $Interfaces::Interface::DATATYPE_TEXT; }
		when (/^(?:TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT)$/x) { $self->{XMLFile_datatypes}->[$last_index] = $Interfaces::Interface::DATATYPE_NUMERIC; }
		when (/^(?:FLOAT|SINGLE|DOUBLE)$/x) { $self->{XMLFile_datatypes}->[$last_index] = $Interfaces::Interface::DATATYPE_FLOATINGPOINT; }
		when (/^(?:DECIMAL|NUMERIC)$/x) { $self->{XMLFile_datatypes}->[$last_index] = $Interfaces::Interface::DATATYPE_FIXEDPOINT; }
		default { Crash("Datatype [$_] unknown"); }
	}
	$self->{XMLFile_hr_columns}->{$hr_config->{fieldname}} = $last_index;
	$self->{XMLFile_ar_useinfile}->[$last_index] = 1;
};

sub xml_escape {
	my ($text) = @_;
	return if !defined $text;
	$text =~ s/[^\x{0009}\x{000A}\x{000D}\x{0020}-\x{D7FF}\x{E000}-\x{FFFD}]/ /xg;
	$text =~ s/&nbsp;/&#160;/xg;
	$text =~ s/["]/&#34;/xg;
	$text =~ s/[&]([^#])/&#38;$1/xg;
	$text =~ s/[']/&#39;/xg;
	$text =~ s/[<]/&#60;/xg;
	$text =~ s/[>]/&#62;/xg;
	return $text;
}

# WriteRecord ($hr_data) returns string
method WriteRecord(HashRef $hr_data !) {
	# Filter kolomindices die geen xml_columns hebben
#print('ar_useinfile: [' . Data::Dump::dump($self->{XMLFile_ar_useinfile}) . "]\r\n");
	my @process_these_columns = grep { $self->{XMLFile_ar_useinfile}->[$_]; } (0 .. $#{$self->{columns}});
	my %columnnames = map { $_ => $self->{columns}->[$_]; } @process_these_columns;
	my $result = "\t<item>\r\n";
#print("Processing these columns: [" . Data::Dump::dump(@process_these_columns) . "]\n");
#print("Processing these columnnames: [" . Data::Dump::dump(%columnnames) . "]\n");
	foreach my $column_index (@process_these_columns) {
		my $CurrentColumnName = $columnnames{$column_index};
		next if !defined $hr_data->{$CurrentColumnName};
		my $ExportColumnName = xml_escape($CurrentColumnName);
		$result .= "\t\t<" . $ExportColumnName . '>' . xml_escape($hr_data->{$CurrentColumnName}) . '</' . $ExportColumnName . ">\r\n";
	}
	$result .= "\t</item>\r\n";
	return $result;
} ## end sub WriteRecord

# WriteData ($filename, $ar_data, $hr_options)
# Options consist of:	header = 0 | 1 # Write a header to the file (default = 1)
#						append = 0 | 1 # Append to file (default = 0)
#						encoding = <value> # ascii, iso-8859-1, utf8 or any other encoding supported by Encode (default = utf8)
method WriteData(Str $filename !, ArrayRef $ar_data !, HashRef $hr_options ?) {
	$hr_options->{header} //= 1;
	$hr_options->{append} //= 0;
	$hr_options->{encoding} //= 'utf8';
	my $filehandle;
	open ($filehandle, '>:' . $hr_options->{encoding}, $filename) or Crash("Error opening outputfile [$filename]: $!");
	print $filehandle '<?xml version="1.0" encoding="UTF-8" standalone="no" ?>' . "\r\n";
	print $filehandle '<' . $self->name . ">\r\n";
	foreach my $hr_data (@{$ar_data}) {
		print $filehandle Interfaces::XMLFile::WriteRecord($self, $hr_data);
	}
	print $filehandle '</' . $self->name . ">\r\n";
	close ($filehandle);
} ## end sub WriteData ($$$)

# ReadRecord ($node) returns $hr_record
method ReadRecord($twig, $element) {
	# Use all columns specified in useinfile
	my $hr_returnvalue = {};
	my $decimalseparator = $self->{decimalseperator};

	foreach my $child_node ($element->children()) {
		my $name = $child_node->gi();
		my $column_index = $self->{XMLFile_hr_columns}->{$name};
		my $field_value = $child_node->text();
		next if not defined $column_index;
		my $CurrentColumnDecimals = $self->{decimals}->[$column_index];
		my $CurrentColumnDatatype = $self->{XMLFile_datatypes}->[$column_index];
		if ($CurrentColumnDatatype >= $Interfaces::Interface::DATATYPE_NUMERIC) {
			# Check if field ends with '-', if so, move '-' to start
			$field_value =~ s/([^ ]*)-$/-$1/x;
			if ($field_value eq '') {
				$field_value = '0';
			}
			if ($CurrentColumnDatatype > $Interfaces::Interface::DATATYPE_NUMERIC && $CurrentColumnDecimals) { # Field is a type that has decimals (FLOAT, NUMERIC etc)
				# Compensate for decimalseperators other than period, change them to .
				if ($decimalseparator ne '.' && $field_value !~ s/\Q${decimalseparator}\E/\./x || index($field_value, '.') + 1 > 0) {
					# There were no $decimalseperators present and there is no period present in $field_value
					$field_value .= '.';
				}
				$field_value = "0$field_value" if substr($field_value, 0, 1) eq '.';
				$field_value .= '0' x $CurrentColumnDecimals;
				$field_value =~ s/(\.[0-9]{$CurrentColumnDecimals}).+/$1/x;    # Trim trailing digits to max $CurrentColumnDecimals
			}
			$hr_returnvalue->{$name} = 0 + $field_value;
		} else {
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
	$twig->purge();
	return $hr_returnvalue;
} ## end sub ReadRecord 

# ConfigureUseInFile ($ar_headers)
# Matches headers in $ar_headers with @self->displayname and sets useinfile=1 for the matching headers
# Also sets the matching header's fileindex to the columnnumber (0-based) where the header matched in the arrayref.
method ConfigureUseInFile (ArrayRef $ar_headers !) {
	# Zero all useinfiles and fileindex
	for (0 .. $#{$self->columns}) {
		$self->{XMLFile_ar_useinfile}->[$_] = 0;
	}
	my $num_file_index = 0;
	foreach my $header (@{$ar_headers}) {
		my $HeaderIndex = SleLib::IndexOf($header, @{$self->{displayname}});
		if ($HeaderIndex >= 0) {
			$self->{XMLFile_ar_useinfile}->[$HeaderIndex] = 1;
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
		$self->{XMLFile_ar_useinfile}->[$_] = 0;
	}
	foreach my $file_column (keys %{$hr_headerindex}) {
		$self->{XMLFile_ar_useinfile}->[$hr_headerindex->{$file_column}] = 1;
	}
}

# ReadFile ($filename, [$hr_options]) returns \@data with \%records
method ReadData(Str $filename !, HashRef $hr_options ?) {
	my $ar_returnvalue = [];
	my $xml_twig = XML::Twig->new(
		twig_roots => {
			item => sub {
				push(@{$ar_returnvalue}, Interfaces::XMLFile::ReadRecord($self, @_));
			}
		},
	);
	if (!defined $xml_twig) {
		Crash("Error initializing XML parser");
	}
	$xml_twig->parsefile($filename);
	return $ar_returnvalue;
} ## end sub ReadData ($$)

1;

=head1 NAME

Interfaces::DelimitedFile - Delimited file format extension to Interfaces::Interface

=head1 VERSION

This document refers to Interfaces::DelimitedFile version 1.0.0.

=head1 SYNOPSIS

  use Interfaces::Interface;
  my $interface = Interfaces::Interface->new();
  $interface->ReConfigureFromHash($hr_config);
  $interface->delimiter(',');
  my $ar_data = $interface->DelimitedFile_ReadData("foobar.csv");
  $interface->DelimitedFile_WriteData("foobar.csv", $ar_data);

=head1 DESCRIPTION

This module extends the Interfaces::Interface with the capabilities to read from - and
write to files in a character or string-delimited file.

=head2 Attributes for C<Interfaces::DelimitedFile>

=over 4

=item * C<delimiter>
Contains the field-delimiter character (or string).

=item * C<usedinexcel>
When importing csv-files into Excel, values can get mangled. In order to prevent this, a workaround
was implemented to assign "=value" to a field instead of just the value. This works for textfields only.

=back

=head2 Methods for C<Interfaces::DelimitedFile>

=over 4

=item * C<$interface-E<gt>ConfigureUseInFile($ar_headers);>

Supplied an arrayref of strings, matches those with $self->displayname to determine which columns in
the file are to be linked with which columns of the interface. Is automatically called from ReadData,
but not from ReadRecord.

=item * C<$interface-E<gt>ParseHeaders($headerstring);>

Performs an identical function to ConfigureUseInFile, except this takes a string from which it extracts
the headers.

=item * C<$interface-E<gt>ReadRecord($string);>

Parses the supplied line of text as a character/string-delimited record. Returns an hashref with the data 
with the columnnames as key. Only reads the columns configured by ConfigureUseInFile or ParseHeaders.

=item * C<$interface-E<gt>WriteRecord($hr_data);>

Converts the supplied hashref datarecord to a line of text. Returns a string of text containing the
character/string-delimeted data.

=item * C<$interface-E<gt>ReadData($fullpath_to_file);>

Reads the given file and returns its data as an arrayref with a hashref per datarecord.
If ConfigureUseInFile or ParseHeaders has not been called before, an initial record with headers is assumed
present and is parsed. The special variable $/ (or $INPUT_RECORD_SEPARATOR) can be changed to a different 
input record separator should that be required.

=item * C<$interface-E<gt>WriteData($fullpath_to_file, $ar_data, $hr_options);>

Writes the given data to the file specified by $fullpath_to_file.
Options consist of: header = 0 | 1 (Write a header to the file (default = 1)).
Each record is appended with $/ when written to file.

=back

=head1 DEPENDENCIES

L<Interfaces::Interface>, L<Moose> and L<Carp>.

=head1 AUTHOR

The original author is Herbert Buurman

=head1 LICENSE

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See L<perlartistic>.

=cut

