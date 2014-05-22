package Interfaces::ExcelBinary;
# Version 0.11	30-08-2012
# Copyright (C) OGD 2011-2012

# Interfaces with the BIFF-excel format (.xls)

use v5.10;
use Smart::Comments;
use Moose::Role;    # automatically turns on strict and warnings
use Spreadsheet::ParseExcel::Stream;
use Spreadsheet::WriteExcel;
use List::Util;
use MooseX::Method::Signatures;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater

# Private attributes
has 'ExcelBinary_ar_useinfile'			=> (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 0,);
has 'ExcelBinary_ar_fileindex'			=> (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 0,);
has 'ExcelBinary_hr_reversefileindex'	=> (is => 'rw', isa => 'HashRef[Int]', lazy_build => 0,);

after 'Check' => sub {
	my $self = shift;
	# Check if all fields that are marked with "useinfile" have a displayname
	for (0 .. $#{$self->columns}) {
		if ($self->{ExcelBinary_ar_useinfile}->[$_] && !($self->displayname->[$_] // "")) {
			Interfaces::Interface::Crash("ExcelBinary field [" . $self->columns->[$_] . "] is configured to be used, but has no displayname");
		}
	}
};

# ConfigureUseInFile ($ar_headers)
# Matches headers in $ar_headers with @self->displayname and sets useinfile=1 for the matching headers
# Also sets the matching header's fileindex to the columnnumber (0-based) where the header matched in the arrayref.
method ConfigureUseInFile(ArrayRef $ar_headers !) {
	# Zero all useinfiles and fileindex
	for (0 .. $#{$self->columns}) {
		$self->{ExcelBinary_ar_useinfile}->[$_] = 0;
		$self->{ExcelBinary_ar_fileindex}->[$_] = undef;
	}
	$self->{ExcelBinary_hr_reversefileindex} = {};
	my $num_file_index = 0;
	foreach my $header (@{$ar_headers}) {
		my $header_index = -1;
		foreach (@{$self->displayname}) {
			$header_index++;
			last if $header eq $_ && !defined $self->{ExcelBinary_ar_fileindex}->[$header_index];
		}
		if ($header_index >= 0) {
			$self->{ExcelBinary_ar_useinfile}->[$header_index]           = 1;
			$self->{ExcelBinary_ar_fileindex}->[$header_index]           = $num_file_index;
			$self->{ExcelBinary_hr_reversefileindex}->{$num_file_index} = $header_index;
		} else {
			Carp::carp("Header [$header] not found\n");
		}
		$num_file_index++;
	} ## end foreach my $header (@{$ar_headers...})
} ## end sub ConfigureUseInFile ($$)

# ReadRecord (Worksheet, Row) returns $hr_data
# Reads a row of data from an opened SpreadSheet::Worksheet-object
method ReadRecord($WorkSheet, $CurrentRow) {
	if (List::Util::sum($self->{ExcelBinary_ar_fileindex}) == 0) { Interfaces::Interface::Crash("Error: No headers have been identified or ConfigureUseInFile never used."); }
	my ($MinCol, $MaxCol) = $WorkSheet->col_range();
	if ($MaxCol < $MinCol) { Interfaces::Interface::Crash("Error: The worksheet [" . $WorkSheet->get_name() . "] has no data (cols)"); }
	my $hr_data = {};
	for (my $CurrentCol = $MinCol ; $CurrentCol < $MaxCol ; $CurrentCol++) {
#print("Reading from [$CurrentRow, CurrentCol]: " . $WorkSheet->get_cell($CurrentRow, $CurrentCol)->value . "\n");
		$hr_data->{$self->columns->[$self->{ExcelBinary_hr_reversefileindex}->{$CurrentCol}]} = $WorkSheet->get_cell($CurrentRow, $CurrentCol)->value;
	}
	#print ("Returning record with size [" . Devel::Size::total_size($hr_data) . "]\n");
	return $hr_data;
} ## end sub ReadRecord ($$$)

# WriteRecord ($WorkSheet, $CurrentRow, $hr_data)
# Writes data in $hr_data to $CurrentRow in $WorkSheet
method WriteRecord($WorkSheet, $CurrentRow, HashRef $hr_data !) {
	for my $column (0 .. $#{$self->columns}) {
		if (!$self->{ExcelBinary_ar_useinfile}->[$column]) { next; }
		if (!defined $hr_data->{$self->{columns}->[$column]}) {
			#$WorkSheet->write_blank($CurrentRow, $self->fileindex->[$column]); # This is stupid, let's not write anything here at all :)
			next;
		}
		given ($self->{internal_datatype}->[$column]) {
			when ($Interfaces::Interface::DATATYPE_TEXT) {
				$WorkSheet->write_string($CurrentRow, $self->{ExcelBinary_ar_fileindex}->[$column], $hr_data->{$self->{columns}->[$column]});
			}
			when ($_ >= $Interfaces::Interface::DATATYPE_NUMERIC) {
				$WorkSheet->write_number($CurrentRow, $self->{ExcelBinary_ar_fileindex}->[$column], $hr_data->{$self->{columns}->[$column]});
			}
			default {
				$WorkSheet->write($CurrentRow, $self->{ExcelBinary_ar_fileindex}->[$column], $hr_data->{$self->{columns}->[$column]});
			}
		} ## end given
	} ## end for my $column (0 .. $#...)
} ## end sub WriteRecord ($$$$)

# WriteHeaders ($WorkSheet)
# Writes headers (displaynames of columns with useinfile == 1) to row 0 in $WorkSheet
method WriteHeaders ($WorkSheet !) {
	my $ColumnID = 0;
	foreach my $Header (map { $self->{displayname}->[$_]; } grep { $self->{ExcelBinary_ar_useinfile}->[$_]; } (0 .. $#{$self->{columns}})) {
		$WorkSheet->write(0, $ColumnID++, $Header);
	}
} ## end sub WriteHeaders

# ReadData (Filename, { options }) returns $ar_data
# Reads data from the given file (which should be a BIFF-formatted .xls-file) and the given worksheet (by number (0-based)).
# Options consist of:
# 	WorksheetID			| Number of target worksheet (base 0)
# 	skip_header		= 0 | 1 # Skip the header in the file (default = 0)
#	no_header		= 0 | 1 # There is no header in the target file/worksheet (default = 0) (implies skip_header=0)
method ReadData (Str $FileName !, HashRef $hr_options ?) {
	if (!-e $FileName) { Carp::confess("File [$FileName] does not exist."); }
	$hr_options->{no_header} //= 0;
	$hr_options->{skip_header} //= 0;
	$hr_options->{trim} //= 1;
	if ($hr_options->{no_header}) {
		$hr_options->{skip_header} = 0;
	}

	my $ExcelParser = Spreadsheet::ParseExcel::Stream->new($FileName);
	$hr_options->{worksheet_id} //= 0;    # Default to 0 (the first sheet) if not supplied
	my $WorkSheet = $ExcelParser->sheet();
	while ($hr_options->{worksheet_id}--) {
		$WorkSheet = $ExcelParser->sheet();
	}
	if (!defined $WorkSheet) { Carp::confess("Error: The requested worksheet [$hr_options->{worksheet_id}] does not exist in [$FileName]"); }
	
	if (!$hr_options->{no_header} && !$hr_options->{skip_header}) {
		# Read headers
		Interfaces::ExcelBinary::ConfigureUseInFile($self, $WorkSheet->unformatted());
	}
	
	if (List::Util::sum($self->{ExcelBinary_ar_fileindex}) == 0) {
		if ($hr_options->{no_header}) {
			Carp::confess("Error: Option no_header was given, but no headers were configured using ConfigureUseInFile");
		} elsif ($hr_options->{skip_header}) {
			Carp::confess("Error: Option skip_header was given, but no headers were configured using ConfigureUseInFile");
		} else {
			Carp::confess("Error: The worksheet [$hr_options->{worksheet_id}] does not contain any identifiable headers");
		}
	}
	# Read data
	my $ar_data      = [];
	my $Current_Cell = undef;
	my $row_nr = 0;
	my ($CurrentColumnIndex, $CurrentColumnDecimals, $current_field_default, $field_value);
	while (my $row = $WorkSheet->unformatted()) { ### Reading [===[%]    ]
		$row_nr++;
#Data::Dump::dd($row);
		my $hr_data = {};
		foreach my $CurrentColumnIndex (0 .. $#{$row}) {
			$Current_Cell = $row->[$CurrentColumnIndex];
			$CurrentColumnIndex = $self->{ExcelBinary_hr_reversefileindex}->{$CurrentColumnIndex};
			if (!defined $CurrentColumnIndex) { next; }
			$current_field_default = $self->{default}->[$CurrentColumnIndex];
			$field_value = undef;
			if ($self->{internal_datatype}->[$CurrentColumnIndex] >= $Interfaces::Interface::DATATYPE_NUMERIC) {
				$CurrentColumnDecimals = $self->{decimals}->[$CurrentColumnIndex];
				if (!defined $Current_Cell) {
					print ('Row [' . $row_nr . '], field [' . $self->{columns}->[$CurrentColumnIndex] . '] has no value' . "\n");
					if (!$self->allownull->[$CurrentColumnIndex]) {
						if (defined $current_field_default) {
							if ($self->{read_defaultvalues}) {
								$field_value = $current_field_default;
							}
						} else {
							Interfaces::Interface::Crash('Field [' . $self->{columns}->[$CurrentColumnIndex] . '] requires a value, but has none, and no default value either');
						}
					} else {
						next;
					}
				} else {
					$field_value = 0 + $Current_Cell;    # create a numeric value.
					if ($self->{speedy} && $field_value == ($current_field_default // 0) && $self->{allownull}->[$CurrentColumnIndex] && !$self->{read_defaultvalues}) { next; } # Skip numeric fields that equal (default value // 0)
					if (!$self->{speedy}) {
						$field_value = $self->minmax($CurrentColumnIndex, $field_value);
					}
				}
			} else {
				if (defined $Current_Cell) {
					if ($hr_options->{trim}) {
						$Current_Cell =~ s/^\s+//; # 6592014	18.8s	6592014	6.05s
						$Current_Cell =~ s/\s+$//; # 6592014	12.8s	6592014	2.71s
						if ($Current_Cell eq '') {
							next;
						} else {
							$field_value = $Current_Cell;
						}
					}
				} else {
					if (!$self->allownull->[$CurrentColumnIndex]) {
						if (defined $current_field_default) {
							# If NULL values are not allowed, store default value or undef (if no default value exists)
							if ($self->{read_defaultvalues}) {
								$field_value = $current_field_default
							}
						} else {
							Interfaces::Interface::Crash('Field [' . $self->{columns}->[$CurrentColumnIndex] . '] requires a value, but has none, and no default value either');
						}
					} else {
						next;
					}
					# else don't store the value at all..saves a key-value pair
				}
			}
			$hr_data->{$self->{columns}->[$CurrentColumnIndex]} = $field_value;
		}
		push (@{$ar_data}, $hr_data);
	} ## end for (my $CurrentRow = $MinRow...)
	return $ar_data;
} ## end sub ReadData

# WriteData ($FileName, $ar_data, [$WorkSheetID])
# Writes supplied $ar_data to $FileName in $WorkSheetID
# If $FileName exists but $WorkSheetID does not, it will be appended.
method WriteData (Str $FileName !, ArrayRef $ar_data !, Str $WorkSheetID ?) {
	my $WorkBook = Spreadsheet::WriteExcel->new($FileName);
	if (!defined $WorkBook) { Carp::confess("Error opening [$FileName]: $!"); }
	my @WorkSheets     = $WorkBook->sheets();
	my @SheetNames     = map { $_->get_name(); } @WorkSheets;
	my $WorkSheetIndex = undef;
	my $WorkSheet;
	if (@WorkSheets and defined $WorkSheetID) {
		for (0 .. $#SheetNames) {
			if ($SheetNames[$_] eq $WorkSheetID) { $WorkSheetIndex = $_; last; }
		}    # Search WorkSheetIndex for $WorkSheetID (by name)
		if ($WorkSheetID * 1 >= 0) {    # If $WorkSheetID is numeric and > 0, use it as index
			$WorkSheetIndex = $WorkSheetID;
			$WorkSheet      = $WorkSheets[$WorkSheetID];
		} else {
			$WorkSheet = $WorkBook->add_worksheet($WorkSheetID);    # File has sheets, but name not found. Add worksheet by name
		}
	} else {
		$WorkSheet = $WorkBook->add_worksheet($WorkSheetID);        # Add worksheet by name
	}
	# Configure & Write headers
	my $targetcolumn = 0;
	map { $self->{ExcelBinary_ar_fileindex}->[$_] = $targetcolumn++; } grep { $self->{ExcelBinary_ar_useinfile}->[$_]; } (0 .. $#{$self->{columns}});
	Interfaces::ExcelBinary::WriteHeaders($self, $WorkSheet);
	# Write data
	my $CurrentRow = 1;
	foreach my $hr_data (@{$ar_data}) { ### Writing [===[%]    ]
		Interfaces::ExcelBinary::WriteRecord($self, $WorkSheet, $CurrentRow++, $hr_data);
	}
} ## end sub WriteData

1;

=head1 NAME

Interfaces::ExcelBinary - Excel BIFF format extension to Interfaces::Interface

=head1 VERSION

This document refers to Interfaces::ExcelBinary version 2.0.0

=head1 SYNOPSIS

  use Interfaces::Interface;
  my $interface = Interfaces::Interface->new();
  $interface->ReConfigureFromHash($hr_config);
  my $ar_data = $interface->ReadData("foobar.xls");
  $interface->WriteData("foobar.xls", $ar_data);

=head1 DESCRIPTION

This module extends the Interfaces::Interface with the capabilities to read from - and
write to Microsoft Excel .xls files (Office '97 - 2003).

=head2 Attributes for C<Interfaces::ExcelBinary>

=over 4

  None

=back

=head2 Methods for C<Interfaces::DelimitedFile>

=over 4

=item * C<$interface-E<gt>ReadRecord($Worksheet, $Row);>

Reads a row of data from the given row of an opened SpreadSheet::Worksheet-object and returns it as a hashref.

=item * C<$interface-E<gt>WriteRecord($Worksheet, $Row, $hr_data);>

Writes data in $hr_data to the given $Row in the given SpreadSheet::Worksheet-object.

=item * C<$interface-E<gt>ReadData($fullpath_to_file);>

Reads the given file and returns its data as an arrayref with a hashref per datarecord.
Note: Spreadsheet::ParseExcel suffers from extensive memory-usage on large xls-files. A 45MB file results in a memory-footprint of 300MB.

=item * C<$interface-E<gt>WriteData($fullpath_to_file, $ar_data, [$Worksheet]);>

Writes the supplied data to the given worksheet of the given file. If no worksheet is given, a new sheet is added. If the file already exists, it is overwritten, otherwise it is created.

=item * C<$interface-E<gt>ConfigureUseInFile($ar_headers);>

Matches headers in $ar_headers with @self->displayname and sets useinfile=1 for the matching headers.
Also sets the matching header's fileindex to the columnnumber (0-based) where the header matched in the arrayref.
Used to match the index of the various columns in the data with the index of the matching columns in the interface

=back

=head1 DEPENDENCIES

L<Interfaces::Interface>, L<Spreadsheet::ParseExcel>, L<Spreadsheet::WriteExcel>, L<List::Util>, L<Moose> and L<Carp>

=head1 AUTHOR

The original author is Herbert Buurman

=head1 LICENSE

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See L<perlartistic>.

=cut

