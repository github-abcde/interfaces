package Interfaces::XMLFile;

use 5.010;
use Smart::Comments;
use Moose::Role;    # automatically turns on strict and warnings
use XML::Twig;
use Scalar::Util;
use MooseX::Method::Signatures;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater

BEGIN {
	$Interfaces::XMLFile::VERSION = 1.00; # 27-11-2013
}

has 'XMLFile_ar_useinfile'	=> (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 1,);
has 'XMLFile_hr_columns'	=> (is => 'rw', isa => 'HashRef[Int]', lazy_build => 1,);
has 'XMLFile_fieldmask' 	=> (is => 'rw', isa => 'HashRef[Str]', lazy_build => 1,);
has 'XMLFile_root_tag'		=> (is => 'rw', isa => 'Str', lazy_build => 1,);
has 'XMLFile_item_tag'		=> (is => 'rw', isa => 'Str', lazy_build => 1,);
has 'XMLFile_ar_writemask'	=> (is => 'rw', isa => 'Str', lazy_build => 0, clearer => 'clear_XMLFile_ar_writemask');

after 'BUILD' => sub {
	my $self = shift;
	# Initialize our own attributes with default values and set all columns with a displayname to be used
	Interfaces::XMLFile::ConfigureUseInFile($self, $self->displayname());
	# Other defaults
	$self->XMLFile_root_tag($self->name // 'root');
	$self->XMLFile_item_tag('item');
	$self->{XMLFile_ar_writemask} = [];
};

after 'Check' => sub {
	my $self = shift;
#	print ("Checking XMLFile constraints\n");
	# Check if all fields that are marked with "useinfile" have a displayname
	for (0 .. $#{$self->columns}) {
		if ($self->XMLFile_ar_useinfile->[$_] && !($self->displayname->[$_] // "")) {
			Interfaces::Interface::Crash("XMLFile field [" . $self->columns->[$_] . "] is configured to be used, but has no displayname");
		}
	} ## end for (0 .. $#{$self->columns...
	if (!$self->has_XMLFile_root_tag) { Interfaces::Interface::Crash('root tag not defined'); }
	if (!$self->has_XMLFile_item_tag) { Interfaces::Interface::Crash('item tag not defined'); }
};

after 'ReConfigureFromHash' => sub {
	my $self = shift;
	$self->clear_XMLFile_ar_writemask();
	# Init datatypes for speed (saves having to do regexes for each ReadRecord call)
	foreach my $index (0 .. $#{$self->columns}) {
		$self->{XMLFile_hr_columns}->{$self->columns->[$index]} = $index;
		$self->{XMLFile_ar_useinfile}->[$index] = 1;
	}
	# Other defaults
	$self->XMLFile_root_tag($self->name);
	$self->XMLFile_item_tag('item');
};

after 'AddField' => sub {
	my ($self, $hr_config) = @_;
	my $last_index = $#{$self->columns};
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
	my @process_these_columns = grep { $self->{XMLFile_ar_useinfile}->[$_]; } (0 .. $#{$self->{columns}});
	my %columnnames = map { $_ => $self->{columns}->[$_]; } @process_these_columns;
	my $result = "\t<item>\n";
	# Filter kolomindices die geen XMLFile_ar_useinfile hebben
	# Maak printf-masks
	if (scalar grep { !defined $_; } map { $self->{XMLFile_ar_writemask}->[$_]; } @process_these_columns > 0) {
		for my $index (@process_these_columns) {
			if (!defined $self->{XMLFile_ar_writemask}->[$index]) {
				$self->{XMLFile_ar_writemask}->[$index] = "%";
				given ($self->{internal_datatype}->[$index]) {
					when ($Interfaces::Interface::DATATYPE_TEXT) {
						$self->{XMLFile_ar_writemask}->[$index] .= "s";
					}
					when ($Interfaces::Interface::DATATYPE_NUMERIC) {
						$self->{XMLFile_ar_writemask}->[$index] .= $self->{signed}->[$index] == 1 ? "d" : "u";
					}
					when ($_ > $Interfaces::Interface::DATATYPE_NUMERIC) {
						$self->{XMLFile_ar_writemask}->[$index] .= "." . $self->{decimals}->[$index] . "f";
					}
					default {
						$self->{XMLFile_ar_writemask}->[$index] .= "s";
					}
				} ## end given
			}
		}
		if (!defined $self->{XMLFile_ar_writemask}) {
			Interfaces::Interface::Crash("No columns were identified as being used in file (have you forgot to use ConfigureUseInFile?).");
		}
	}
	foreach my $column_index (@process_these_columns) {
		my $current_column_name = $columnnames{$column_index};
		my $field_value = $hr_data->{$current_column_name};
		if (!defined $field_value) {
			if ($self->{allownull}->[$column_index]) {
				next;
			} else {
				# Required field
				if ($self->{write_defaultvalues} and defined $self->{default}->[$column_index]) {
					$field_value = $self->{default}->[$column_index];
				} else {
					Interfaces::Interface::Crash('Field [' . $current_column_name . '] requires a value, but has none (write_defaultvalues [' . $self->{write_defaultvalues} . '], default [' . $self->{default}->[$column_index] . "])\n" . Data::Dump::dump($hr_data));
				}
			}
		}
		my $export_column_name = xml_escape($current_column_name);
		$result .= "\t\t<" . $export_column_name . '>';
		if ($self->{internal_datatype}->[$column_index] >= $Interfaces::Interface::DATATYPE_NUMERIC) {
			$field_value = $self->minmax($column_index, $field_value);
		}
		$result .= xml_escape(sprintf($self->{XMLFile_ar_writemask}->[$column_index], $field_value)) . '</' . $export_column_name . ">" . $/;
	}
	$result .= "\t</item>" . $/;
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
	open ($filehandle, '>:' . $hr_options->{encoding}, $filename) or Interfaces::Interface::Crash("Error opening outputfile [$filename]: $!");
	print $filehandle '<?xml version="1.0" encoding="UTF-8" standalone="no" ?>' . $/;
	print $filehandle '<' . $self->name . ">" . $/;
	foreach my $hr_data (@{$ar_data}) { ### Writing [===[%]    ]
		print $filehandle Interfaces::XMLFile::WriteRecord($self, $hr_data);
	}
	print $filehandle '</' . $self->name . ">" . $/;
	close ($filehandle);
} ## end sub WriteData ($$$)

# ReadRecord ($node) returns $hr_record
method ReadRecord($twig, $element) {
	# Use all columns specified in useinfile
	my $hr_returnvalue = {};
	my $decimalseparator = $self->{decimalseparator};

	foreach my $child_node ($element->children()) {
		my $name = $child_node->gi();
		my $column_index = $self->{XMLFile_hr_columns}->{$name};
		my $field_value = $child_node->text();
		next if not defined $column_index;
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
				# Compensate for decimalseparators other than period, change them to .
				if ($decimalseparator ne '.' && !($field_value =~ s/\Q${decimalseparator}\E/./x) || index($field_value, '.') + 1 == 0) {
					# There were no $decimalseparators present and there is no period present in $field_value
					$field_value .= '.';
				}
				$field_value = "0$field_value" if substr($field_value, 0, 1) eq '.';
				$field_value .= '0' x $CurrentColumnDecimals;
				$field_value =~ s/(\.[0-9]{$CurrentColumnDecimals}).+/$1/x;    # Trim trailing digits to max $CurrentColumnDecimals
			}
			# Check if field is numeric
#print("Field [$name] type [$self->{datatype}->[$column_index]] value [$field_value]\n");
#Devel::Peek::Dump $field_value;
			$hr_returnvalue->{$name} = 0 + $field_value;
		} else {
			if ($field_value eq '') {
				# Store default value or undef (if no default value exists)
				if ($self->read_defaultvalues and defined $self->{default}->[$column_index]) {
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
		Interfaces::Interface::Crash("Error initializing XML parser");
	}
	$xml_twig->parsefile($filename);
	return $ar_returnvalue;
} ## end sub ReadData ($$)

1;

=head1 NAME

Interfaces::XMLFile - XML file format extension to Interfaces::Interface

=head1 VERSION

This document refers to Interfaces::XMLFile version 1.0.0.

=head1 SYNOPSIS

  use Interfaces::Interface;
  my $interface = Interfaces::Interface->new();
  $interface->ReConfigureFromHash($hr_config);
  my $ar_data = $interface->DelimitedFile_ReadData("foobar.xml");
  $interface->DelimitedFile_WriteData("foobar.xml", $ar_data);

=head1 DESCRIPTION

This module extends the Interfaces::Interface with the capabilities to read from - and
write to files in an XML file.

=head2 Attributes for C<Interfaces::XMLFile>

=over 4

=head2 Methods for C<Interfaces::XMLFile>

=over 4

=item * C<$interface-E<gt>ConfigureUseInFile($ar_headers);>

Supplied an arrayref of strings, matches those with $self->displayname to determine which columns in
the file are to be linked with which columns of the interface. Is automatically called from ReadData,
but not from ReadRecord.

=item * C<$interface-E<gt>ReadRecord($twig, $element);>

Parses the supplied element node and it's children. Returns an hashref with the data 
with the columnnames as key. Only reads the columns configured by ConfigureUseInFile.

=item * C<$interface-E<gt>WriteRecord($hr_data);>

Converts the supplied hashref datarecord to a line of text. Returns a string of text containing the
XML data.

=item * C<$interface-E<gt>ReadData($fullpath_to_file);>

Reads the given file and returns its data as an arrayref with a hashref per datarecord.
If ConfigureUseInFile has not been called before, an initial record with headers is assumed
present and is parsed.

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

