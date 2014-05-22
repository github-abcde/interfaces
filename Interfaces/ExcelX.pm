package Interfaces::ExcelX;
# Interfaces with the new excel format (.xlsx)

use v5.10;
use Smart::Comments;
use Moose::Role;    # automatically turns on strict and warnings
use Spreadsheet::XLSX;
use Excel::Writer::XLSX;
use List::Util;
use MooseX::Method::Signatures;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater

BEGIN {
	$Interfaces::ExcelX::VERSION = '1.0.0'; # 03-01-2012
}

has 'ExcelX_ar_useinfile'			=> (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 0,);
has 'ExcelX_ar_fileindex'			=> (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 0,);
has 'ExcelX_hr_reversefileindex'	=> (is => 'rw', isa => 'HashRef[Int]', lazy_build => 0,);

after 'Check' => sub {
	my $self = shift;
	# Check if all fields that are marked with "useinfile" have a displayname
	for (0 .. $#{$self->columns}) {
		if ($self->{ExcelX_ar_useinfile}->[$_] && !($self->displayname->[$_] // "")) {
			Interfaces::Interface::Crash("ExcelX field [" . $self->columns->[$_] . "] is configured to be used, but has no displayname");
		}
	}
};

# ConfigureUseInFile ($ar_headers)
# Matches headers in $ar_headers with @self->displayname and sets useinfile=1 for the matching headers
# Also sets the matching header's fileindex to the columnnumber (0-based) where the header matched in the arrayref.
method ConfigureUseInFile(ArrayRef $ar_headers !) {
	# Zero all useinfiles and fileindex
	for (0 .. $#{$self->columns}) {
		$self->{ExcelX_ar_useinfile}->[$_] = 0;
		$self->{ExcelX_ar_fileindex}->[$_] = undef;
	}
	$self->{ExcelX_hr_reversefileindex} = {};
	my $num_file_index = 0;
	foreach my $header (@{$ar_headers}) {
		my $header_index = -1;
		foreach (@{$self->displayname}) {
			$header_index++;
			last if $header eq $_;
		}
		if ($header_index >= 0) {
			$self->{ExcelX_ar_useinfile}->[$header_index]           = 1;
			$self->{ExcelX_ar_fileindex}->[$header_index]           = $num_file_index;
			$self->{ExcelX_hr_reversefileindex}->{$num_file_index} = $header_index;
		} else {
			$num_file_index++;
			Carp::carp("Header [$header] not found in interface");
			next;
		}
		$num_file_index++;
	} ## end foreach my $header (@{$ar_headers...
} ## end sub ExcelXConfigureUseInFile ($$)

# ReadRecord (Worksheet, Row) returns $hr_data
# Reads a row of data from an opened SpreadSheet::Worksheet-object
method ReadRecord($WorkSheet, $CurrentRow) {
	if (List::Util::sum($self->{ExcelX_ar_fileindex}) == 0) { Interfaces::Interface::Crash("Error: No headers have been identified or ConfigureUseInFile never used."); }
	my ($MinCol, $MaxCol) = $WorkSheet->col_range();
	if ($MaxCol < $MinCol) { Interfaces::Interface::Crash("Error: The worksheet [" . $WorkSheet->get_name() . "] has no data (cols)"); }
	my $hr_data = {};
	for (my $CurrentCol = $MinCol ; $CurrentCol < $MaxCol ; $CurrentCol++) {
		$hr_data->{$self->{columns}->[$self->{ExcelX_hr_reversefileindex}->{$CurrentCol}]} = $WorkSheet->get_cell($CurrentRow, $CurrentCol)->value;
	}
	return $hr_data;
} ## end sub ReadRecord ($$$)

# WriteRecord ($WorkSheet, $CurrentRow, $hr_data)
# Writes data in $hr_data to $CurrentRow in $WorkSheet
method WriteRecord($WorkSheet, $CurrentRow, HashRef $hr_data) {
	for my $column (0 .. $#{$self->{columns}}) {
		if (!$self->{ExcelX_ar_useinfile}->[$column]) { next; }
		if (!defined $hr_data->{$self->{columns}->[$column]}) {
			next;
		}
		given ($self->{datatype}->[$column]) {
			when (/CHAR|VARCHAR|TEXT/i) {
				$WorkSheet->write_string($CurrentRow, $self->{ExcelX_ar_fileindex}->[$column], $hr_data->{$self->{columns}->[$column]});
			}
			when (/FLOAT|DOUBLE|TINYINT|SMALLINT|MEDIUMINT|INT|BIGINT|INTEGER/i) {
				$WorkSheet->write_number($CurrentRow, $self->{ExcelX_ar_fileindex}->[$column], $hr_data->{$self->{columns}->[$column]});
			}
			default {
				$WorkSheet->write($CurrentRow, $self->{ExcelX_ar_fileindex}->[$column], $hr_data->{$self->{columns}->[$column]});
			}
		} ## end given
	} ## end for my $column (0 .. $#...
} ## end sub WriteRecord ($$$$)

# WriteHeaders ($WorkSheet)
# Writes headers (displaynames of columns with useinfile == 1) to row 0 in $WorkSheet
method WriteHeaders($WorkSheet) {
	my $ColumnID = 0;
	foreach my $Header (map { $self->{displayname}->[$_]; } grep { $self->{ExcelX_ar_useinfile}->[$_]; } (0 .. $#{$self->{columns}})) {
		$WorkSheet->write(0, $ColumnID++, $Header);
	}
} ## end sub ExcelXWriteHeaders

# ReadData (Filename, {options}) returns $ar_data
# Reads data from the given file (which should be a BIFF-formatted .xls-file) and the given worksheet (by name or number (0-based)).
# If the supplied worksheetID is a number, a negative number -n will refer to the n-to-last worksheet.
# Options consist of:
# 	worksheet_id		| Name or Number of target worksheet
# 	skip_header		= 0 | 1 # Skip the header in the file (default = 0)
#	no_header		= 0 | 1 # There is no header in the target file/worksheet (default = 0) (implies skip_header=0)
method ReadData(Str $FileName !, HashRef $hr_options ?) {
	if (!-e $FileName) { Carp::confess("File [$FileName] does not exist."); }
	$hr_options->{no_header} = $hr_options->{no_header} // 0;
	$hr_options->{skip_header} = $hr_options->{skip_header} // 0;
	if ($hr_options->{no_header}) {
		$hr_options->{skip_header} = 0;
	}
	
	no warnings;
	my $WorkBook = Spreadsheet::XLSX->new($FileName); # With warnings enabled, this spams a lot
	use warnings;
	if (!defined $WorkBook) { Carp::confess("Error parsing [$FileName]: " . $WorkBook->error()); }
	$hr_options->{worksheet_id} //= 0;    # Default to 0 (the first sheet) if not supplied
	my $WorkSheet;
	if ($hr_options->{worksheet_id} < 0) {
		my @WorkSheets = @{$WorkBook->{Worksheet}};
		$WorkSheet = $WorkSheets[$hr_options->{worksheet_id}];    # Allow for a fetch-n-before-last
	} else {
		$WorkSheet = $WorkBook->worksheet($hr_options->{worksheet_id});    # Allow for a fetch-by-name
	}
	if (!defined $WorkSheet) { Carp::confess("Error: The requested worksheet [$hr_options->{worksheet_id}] does not exist in [$FileName]"); }
	
	my ($MinCol, $MaxCol) = $WorkSheet->col_range();
	my ($MinRow, $MaxRow) = $WorkSheet->row_range();
	if (!$hr_options->{no_header} && !$hr_options->{skip_header}) {
		# Read headers
		if ($MaxCol < $MinCol) { Carp::confess("Error: The worksheet [$hr_options->{worksheet_id}] has no data (cols)"); }
		if ($MaxRow < $MinRow) { Carp::confess("Error: The worksheet [$hr_options->{worksheet_id}] has no data (rows)"); }
		my @ExcelHeaders;
		for (my $CurrentCol = $MinCol ; $CurrentCol <= $MaxCol ; $CurrentCol++) {
			if (!defined $WorkSheet->get_cell($MinRow, $CurrentCol)) {
				Carp::carp('Error: Worksheet [' . $hr_options->{worksheet_id} . '], cell [' . $MinRow . ',' . $CurrentCol . '] has no value, but is a header');
			} else {
				push (@ExcelHeaders, $WorkSheet->get_cell($MinRow, $CurrentCol)->value);
			}
		}
		Interfaces::ExcelX::ConfigureUseInFile($self, \@ExcelHeaders);
		$MinRow++;
	}
	$MinRow += $hr_options->{skip_header};
	
	if (List::Util::sum($self->{ExcelX_ar_fileindex}) == 0) {
		if ($hr_options->{no_header}) {
			Carp::confess("Error: Option no_header was given, but no headers were configured using ConfigureUseInFile");
		} elsif ($hr_options->{skip_header}) {
			Carp::confess("Error: Option skip_header was given, but no headers were configured using ConfigureUseInFile");
		} else {
			Carp::confess("Error: The worksheet [$hr_options->{worksheet_id}] does not contain any identifiable headers");
		}
	}
	# Read data
	my $ar_data = [];
	my $Current_Cell = undef;
	for (my $CurrentRow = $MinRow ; $CurrentRow <= $MaxRow ; $CurrentRow++) { ### Reading [===[%]    ]
		my $hr_data = {};
		for (my $CurrentCol = $MinCol ; $CurrentCol <= $MaxCol ; $CurrentCol++) {
			if (!defined $self->{ExcelX_hr_reversefileindex}->{$CurrentCol}) { next; }
			$Current_Cell = $WorkSheet->get_cell($CurrentRow, $CurrentCol);
			if (defined $Current_Cell) {
#print("Reading data [" . $Current_Cell->value . 
#		"] at [" . $CurrentRow . ',' . $CurrentCol . 
#		"] for column [" . $Interfaces::ExcelX::ExcelX_hr_reversefileindex->{$CurrentCol} . 
#		"], being [" . $self->columns->[$Interfaces::ExcelX::ExcelX_hr_reversefileindex->{$CurrentCol}]. "]\n");
#print("Data [" . $Current_Cell->value . "], Excel Column [$CurrentCol], interface lookup [" . $Interfaces::ExcelX::ExcelX_hr_reversefileindex->{$CurrentCol} . ']');
				my $fieldvalue = $Current_Cell->value;
				# Trim field
				$fieldvalue =~ s/^\s+//;
				$fieldvalue =~ s/\s+$//;
				$hr_data->{$self->columns->[$self->{ExcelX_hr_reversefileindex}->{$CurrentCol}]} = $fieldvalue;
			}
		}
		push (@{$ar_data}, $hr_data);
	} ## end for (my $CurrentRow = $MinRow...
	return $ar_data;
} ## end sub ReadData

# WriteData ($FileName, $ar_data, [$WorkSheetID])
# Writes supplied $ar_data to $FileName in $WorkSheetID
# If $FileName exists but $WorkSheetID does not, it will be appended.
method WriteData(Str $FileName !, ArrayRef $ar_data !, Str $WorkSheetID ?) {
	my $WorkBook = Excel::Writer::XLSX->new($FileName);
	if (!defined $WorkBook) { Carp::confess("Error opening [$FileName]: $!"); }
	my $WorkSheet = (defined $WorkSheetID) ? $WorkBook->add_worksheet($WorkSheetID) : $WorkBook->add_worksheet;
	# Configure & Write headers
	my $targetcolumn = 0;
	map { $self->{ExcelX_ar_fileindex}->[$_] = $targetcolumn++; } grep { $self->{ExcelX_ar_useinfile}->[$_]; } (0 .. $#{$self->columns});
	Interfaces::ExcelX::WriteHeaders($self, $WorkSheet);
	# Write data
	my $CurrentRow = 1;
	foreach my $hr_data (@{$ar_data}) { ### Writing [===[%]    ]
		Interfaces::ExcelX::WriteRecord($self, $WorkSheet, $CurrentRow++, $hr_data);
	}
} ## end sub WriteData

1;

=head1 NAME

Interfaces::ExcelX - Excel 2007 (.xlsx) format extension to Interfaces::Interface

=head1 VERSION

This document refers to Interfaces::ExcelX version 1.0.0.

=head1 SYNOPSIS

  use Interfaces::Interface;
  my $interface = Interfaces::Interface->new();
  $interface->ReConfigureFromHash($hr_config);
  my $ar_data = $interface->ExcelX_ReadData("foobar.xls");
  $interface->ExcelX_WriteData("foobar.xls", $ar_data);

=head1 DESCRIPTION

This module extends the Interfaces::Interface with the capabilities to read from - and
write to files in a binary Excel file (typically with an .xls extension).

=head2 Attributes for C<Interfaces::ExcelX>

=over 4

Interfaces::ExcelX has no additional public attributes.

=back

=head2 Methods for C<Interfaces::ExcelX>

=over 4

=item * C<$interface-E<gt>ConfigureUseInFile($ar_headers);>

Supplied an arrayref of strings, matches those with $self->displayname to determine which columns in
the xls are to be linked with which columns of the interface. Is automatically called from ReadData,
but not from ReadRecord.

=item * C<$interface-E<gt>ReadRecord($worksheet, $row);>

Reads the row (0-based) $row from the given $worksheet. Returns an hashref with the data with the 
columnnames as key. After initializing the interface, a call to C<$interface-E<gt>ConfigureUseInFile> 
is required before calling ReadRecord. When the input-file/worksheet changes (and thus the column-
assignment), C<$interface-E<gt>ConfigureUseInFile> needs to be called again.

=item * C<$interface-E<gt>WriteRecord($worksheet, $row, $hr_data);>

Writes the data in $hr_data to row (0-based) $row in the given $worksheet. As with ReadRecord, be sure
to have called C<$interface-E<gt>ConfigureUseInFile> to be certain that the data is written to the proper
columns.

=item * C<$interface-E<gt>ReadData($fullpath_to_file, [$worksheetID]);>

Reads the given file and returns its data as an arrayref with a hashref per datarecord.
The optional $worksheetID argument can be a name (for named worksheets) or a number (0-based). If a
negative number is supplied, this will be used as the n-to-last worksheet, similar to substr().

=item * C<$interface-E<gt>WriteData($fullpath_to_file, $ar_data, [$worksheetID]);>

Writes the given data to the file specified by $fullpath_to_file and (optional) sheet $worksheetID.
If $worksheetID exists, it is overwritten, otherwise a sheet with name $worksheetID is created.
If $worksheetID is not supplied, a new sheet 'Sheet 1' is created (this is the default behaviour for 
Spreadsheet::WriteExcel).

=back

=head1 DEPENDENCIES

L<Interfaces::Interface>, L<Moose>, L<Carp>, L<Spreadsheet::XLSX> and L<Excel::Writer::XLSX>.

=head1 AUTHOR

The original author is Herbert Buurman

=head1 LICENSE

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See L<perlartistic>.

=cut

