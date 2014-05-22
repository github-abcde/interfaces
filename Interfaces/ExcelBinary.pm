package Interfaces::ExcelBinary;
# Version 0.11	30-08-2011
# Copyright (C) OGD 2011

# Interfaces with the BIFF-excel format (.xls)

use 5.010;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater
use Moose::Role;    # automatically turns on strict and warnings
use MooseX::Method::Signatures;
use Spreadsheet::ParseExcel;
use Spreadsheet::WriteExcel;
use List::Util;

# Private attributes
has 'ExcelBinary_ar_useinfile'			=> (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 0,);
has 'ExcelBinary_ar_fileindex'			=> (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 0,);
has 'ExcelBinary_hr_reversefileindex'	=> (is => 'rw', isa => 'HashRef[Int]', lazy_build => 0,);
has 'ExcelBinary_datatypes'				=> (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 0,);

BEGIN {
	@Interfaces::ExcelBinary::methods = qw(ReadRecord WriteRecord ReadData WriteData ConfigureUseInFile);
}

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

after 'Check' => sub {
	my $self = shift;
	print ("Checking ExcelBinary constraints...");
	# Check if all fields that are marked with "useinfile" have a displayname
	for (0 .. $#{$self->columns}) {
		if ($self->{ExcelBinary_ar_useinfile}->[$_] and !($self->displayname->[$_] // "")) {
			Carp::confess("ExcelBinary field [" . $self->columns->[$_] . "] is configured to be used, but has no displayname");
		}
	}
	# Init datatypes for speed (saves having to do regexes for each ReadRecord call)
	foreach my $index (0 .. $#{$self->columns}) {
		given ($self->datatype->[$index]) {
			when (/^(CHAR|VARCHAR|DATE|TIME|DATETIME)$/) { $self->{ExcelBinary_datatypes}->[$index] = Interfaces::DATATYPE_TEXT; }
			when (/^(TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT|FLOAT|DOUBLE|DECIMAL|NUMERIC)$/) { $self->{ExcelBinary_datatypes}->[$index] = Interfaces::DATATYPE_NUMERIC; }
			default { $self->{ExcelBinary_datatypes}->[$index] = 0; }
		}
	}	
	print("[OK]\n");
};

# ConfigureUseInFile ($ar_headers)
# Matches headers in $ar_headers with @self->displayname and sets useinfile=1 for the matching headers
# Also sets the matching header's fileindex to the columnnumber (0-based) where the header matched in the arrayref.
method ConfigureUseInFile (ArrayRef $ar_headers !) {
	# Zero all useinfiles and fileindex
	for (0 .. $#{$self->columns}) {
		$self->{ExcelBinary_ar_useinfile}->[$_] = 0;
		$self->{ExcelBinary_ar_fileindex}->[$_] = undef;
	}
	$self->{ExcelBinary_hr_reversefileindex} = {};
	my $num_file_index = 0;
	foreach my $header (@{$ar_headers}) {
		my $HeaderIndex = SleLib::IndexOf($header, @{$self->displayname});
		if ($HeaderIndex >= 0) {
			$self->{ExcelBinary_ar_useinfile}->[$HeaderIndex]           = 1;
			$self->{ExcelBinary_ar_fileindex}->[$HeaderIndex]           = $num_file_index;
			$self->{ExcelBinary_hr_reversefileindex}->{$num_file_index} = $HeaderIndex;
		} else {
			Carp::carp("Header [$header] not found\n");
		}
		$num_file_index++;
	} ## end foreach my $header (@{$ar_headers...})
} ## end sub ConfigureUseInFile ($$)

# ReadRecord (Worksheet, Row) returns $hr_data
# Reads a row of data from an opened SpreadSheet::Worksheet-object
method ReadRecord ($WorkSheet !, Int $CurrentRow !) {
	if (List::Util::sum($self->{ExcelBinary_ar_fileindex}) == 0) { Carp::confess("Error: No headers have been identified or ConfigureUseInFile never used."); }
	my ($MinCol, $MaxCol) = $WorkSheet->col_range();
	if ($MaxCol < $MinCol) { Carp::confess("Error: The worksheet [" . $WorkSheet->get_name() . "] has no data (cols)"); }
	my $hr_data = {};
	for (my $CurrentCol = $MinCol ; $CurrentCol < $MaxCol ; $CurrentCol++) {
		$hr_data->{$self->columns->[$self->{ExcelBinary_hr_reversefileindex}->{$CurrentCol}]} = $WorkSheet->get_cell($CurrentRow, $CurrentCol)->value;
	}
	print ("Returning record with size [" . Devel::Size::total_size($hr_data) . "]\n");
	return $hr_data;
} ## end sub ReadRecord ($$$)

# WriteRecord ($WorkSheet, $CurrentRow, $hr_data)
# Writes data in $hr_data to $CurrentRow in $WorkSheet
method WriteRecord ($WorkSheet !, Int $CurrentRow !, HashRef $hr_data !) {
	for my $column (0 .. $#{$self->columns}) {
		#		if (!$self->useinfile->[$column]) { next; }
		if (!$self->{ExcelBinary_ar_useinfile}->[$column]) { next; }
		if (!defined $hr_data->{$self->columns->[$column]}) {
			#$WorkSheet->write_blank($CurrentRow, $self->fileindex->[$column]); # This is stupid, let's not write anything here at all :)
			next;
		}
		given ($self->datatype->[$column]) {
			when (/CHAR|VARCHAR|TEXT/i) {
				#				$WorkSheet->write_string($CurrentRow, $self->fileindex->[$column], $hr_data->{$self->columns->[$column]});
				$WorkSheet->write_string($CurrentRow, $self->{ExcelBinary_ar_fileindex}->[$column], $hr_data->{$self->columns->[$column]});
			}
			when (/FLOAT|DOUBLE|TINYINT|SMALLINT|MEDIUMINT|INT|BIGINT|INTEGER/i) {
				#				$WorkSheet->write_number($CurrentRow, $self->fileindex->[$column], $hr_data->{$self->columns->[$column]});
				$WorkSheet->write_number($CurrentRow, $self->{ExcelBinary_ar_fileindex}->[$column], $hr_data->{$self->columns->[$column]});
			}
			default {
				#				$WorkSheet->write($CurrentRow, $self->fileindex->[$column], $hr_data->{$self->columns->[$column]});
				$WorkSheet->write($CurrentRow, $self->{ExcelBinary_ar_fileindex}->[$column], $hr_data->{$self->columns->[$column]});
			}
		} ## end given
	} ## end for my $column (0 .. $#...)
} ## end sub WriteRecord ($$$$)

# WriteHeaders ($WorkSheet)
# Writes headers (displaynames of columns with useinfile == 1) to row 0 in $WorkSheet
method WriteHeaders ($WorkSheet !) {
	my $ColumnID = 0;
	#	foreach my $Header (map { $self->{displayname}->[$_]; } grep { $self->{useinfile}->[$_]; } (0 .. $#{$self->{columns}})) {
	foreach my $Header (map { $self->{displayname}->[$_]; } grep { $self->{ExcelBinary_ar_useinfile}->[$_]; } (0 .. $#{$self->{columns}})) {
		$WorkSheet->write(0, $ColumnID++, $Header);
	}
} ## end sub WriteHeaders

# ReadData (Filename, { options }) returns $ar_data
# Reads data from the given file (which should be a BIFF-formatted .xls-file) and the given worksheet (by name or number (0-based)).
# If the supplied worksheetID is a number, a negative number -n will refer to the n-to-last worksheet.
# Options consist of:
# 	WorksheetID			| Name or Number of target worksheet
# 	skip_header		= 0 | 1 # Skip the header in the file (default = 0)
#	no_header		= 0 | 1 # There is no header in the target file/worksheet (default = 0) (implies skip_header=0)
method ReadData (Str $FileName !, HashRef $hr_options ?) {
	if (defined $hr_options and ref($hr_options) ne 'HASH') { Carp::confess "Options-argument is not a hashref"; }	
	if (!defined $FileName or !-e $FileName) { Carp::confess("File [$FileName] does not exist."); }
	$hr_options->{no_header} = $hr_options->{no_header} // 0;
	$hr_options->{skip_header} = $hr_options->{skip_header} // 0;
	if ($hr_options->{no_header}) {
		$hr_options->{skip_header} = 0;
	}
#	$Interface::ExcelBinary::myself = $self;
	my $ExcelParser = Spreadsheet::ParseExcel->new(
		#		CellHandler => \&cell_handler,
		#		NotSetCell => 1,
	);
	my $WorkBook = $ExcelParser->parse($FileName);

	if (!defined $WorkBook) { Carp::confess("Error parsing [$FileName]: " . $ExcelParser->error()); }
	$hr_options->{worksheet_id} //= 0;    # Default to 0 (the first sheet) if not supplied
	my $WorkSheet;
	if ($hr_options->{worksheet_id} < 0) {
		my @WorkSheets = $WorkBook->worksheets();
		$WorkSheet = $WorkSheets[$hr_options->{worksheet_id}];    # Allow for a fetch-n-before-last
	} else {
		$WorkSheet = $WorkBook->worksheet($hr_options->{worksheet_id});    # Allow for a fetch-by-name
	}
	if (!defined $WorkSheet) { Carp::confess("Error: The requested worksheet [$hr_options->{worksheet_id}] does not exist in [$FileName]"); }
	
	my ($MinCol, $MaxCol) = $WorkSheet->col_range();
	my ($MinRow, $MaxRow) = $WorkSheet->row_range();
	if (!$hr_options->{no_header} and !$hr_options->{skip_header}) {
		# Read headers
		if ($MaxCol < $MinCol) { Carp::confess("Error: The worksheet [$hr_options->{worksheet_id}] has no data (cols)"); }
		if ($MaxRow < $MinRow) { Carp::confess("Error: The worksheet [$hr_options->{worksheet_id}] has no data (rows)"); }
		my @ExcelHeaders;
		for (my $CurrentCol = $MinCol ; $CurrentCol <= $MaxCol ; $CurrentCol++) {
			push (@ExcelHeaders, $WorkSheet->get_cell($MinRow, $CurrentCol)->value);
		}
		Interfaces::ExcelBinary::ConfigureUseInFile($self, \@ExcelHeaders);
		$MinRow++;
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
	$MinRow++;
	# Read data
	my $ar_data      = [];
	my $Current_Cell = undef;
	my ($CurrentColumnIndex, $CurrentColumnDecimals);
	for (my $CurrentRow = $MinRow ; $CurrentRow <= $MaxRow ; $CurrentRow++) {
		my $hr_data = {};
		for (my $CurrentCol = $MinCol ; $CurrentCol <= $MaxCol ; $CurrentCol++) {
			$Current_Cell = $WorkSheet->get_cell($CurrentRow, $CurrentCol);
			$CurrentColumnIndex = $Interfaces::ExcelBinary::hr_reversefileindex->{$CurrentCol};
			my $CurrentColumn = undef;
			my $CurrentColumnValue;
			if (defined $Current_Cell) {
				$CurrentColumnDecimals = $self->decimals->[$CurrentColumnIndex];
				if ($self->datatype->[$CurrentColumnIndex] =~ /^(?:TINYINT|MEDIUMINT|SMALLINT|INT|INTEGER|BIGINT)$/) {
					$CurrentColumn->{$CurrentColumnIndex} = 0 + $Current_Cell->value;    # create a numeric value.
				} elsif ($self->datatype->[$CurrentColumnIndex] =~ /^(?:FLOAT|DOUBLE)$/ and $CurrentColumnDecimals > 0) {
					$CurrentColumn->{$CurrentColumnIndex} = "" . $Current_Cell->value;
					if ($CurrentColumn->{$CurrentColumnIndex} !~ /\./p) {
						# Add period and trailing zeroes if required (and not present)
						$CurrentColumn->{$CurrentColumnIndex} .= '.' . '0' x $CurrentColumnDecimals;
					} elsif (length ${^POSTMATCH} < $CurrentColumnDecimals) {
						$CurrentColumn->{$CurrentColumnIndex} .= '0' x ($CurrentColumnDecimals - length (${^POSTMATCH}));
					}
				} else {
					$CurrentColumn->{$CurrentColumnIndex} = $Current_Cell->value;
				}
				$hr_data->{$self->columns->[$CurrentColumnIndex]} = $CurrentColumn->{$CurrentColumnIndex};
			} else {
				$hr_data->{$self->columns->[$CurrentColumnIndex]} = undef;
			}
		} ## end for (my $CurrentCol = $MinCol...)
		push (@{$ar_data}, $hr_data);
	} ## end for (my $CurrentRow = $MinRow...)
	return $ar_data;
} ## end sub ReadData

# WriteData ($FileName, $ar_data, [$WorkSheetID])
# Writes supplied $ar_data to $FileName in $WorkSheetID
# If $FileName exists but $WorkSheetID does not, it will be appended.
method WriteData (Str $FileName !, ArrayRef $ar_data !, $WorkSheetID ?) {
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
	map { $self->{ExcelBinary_ar_fileindex}->[$_] = $targetcolumn++; } grep { $self->{ExcelBinary_ar_useinfile}->[$_]; } (0 .. $#{$self->columns});
	__PACKAGE__::WriteHeaders($self, $WorkSheet);
	# Write data
	my $CurrentRow = 1;
	foreach my $hr_data (@{$ar_data}) {
		__PACKAGE__::WriteRecord($self, $WorkSheet, $CurrentRow++, $hr_data);
	}
} ## end sub WriteData

1;

=head1 NAME

Interfaces::ExcelBinary - Excel BIFF format extension to Interfaces::Interface

=head1 VERSION

This document refers to Interfaces::ExcelBinary version 0.10.

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

