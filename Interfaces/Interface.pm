package Interfaces::Interface;
# Version 0.11	30-08-2011
# Copyright (C) OGD 2011

use Moose;    # automatically turns on strict and warnings
use 5.010;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater
use MooseX::Method::Signatures;

use Data::Dump;
use Carp;

# General info
has 'config'            => (is => 'rw', isa => 'HashRef[HashRef[HashRef[Maybe[Value]]]]', lazy_build => 1,);
has 'name'              => (is => 'rw', isa => 'Maybe[Str]',                              lazy_build => 1,);
has 'decimalseperator'  => (is => 'rw', isa => 'Str',                                     lazy_build => 1,);
has 'thousandseperator' => (is => 'rw', isa => 'Str',                                     lazy_build => 1,);
# Fields info
has 'columns'     => (is => 'rw', isa => 'ArrayRef[Str]',          lazy_build => 1,);
has 'displayname' => (is => 'rw', isa => 'ArrayRef[Str]',          lazy_build => 1,);
has 'datatype'    => (is => 'rw', isa => 'ArrayRef[Str]',          lazy_build => 1,);
has 'length'      => (is => 'rw', isa => 'ArrayRef[Maybe[Int]]',   lazy_build => 1,);
has 'decimals'    => (is => 'rw', isa => 'ArrayRef[Maybe[Int]]',   lazy_build => 1,);
has 'signed'      => (is => 'rw', isa => 'ArrayRef[Maybe[Bool]]',  lazy_build => 1,);
has 'allownull'   => (is => 'rw', isa => 'ArrayRef[Bool]',         lazy_build => 1,);
has 'default'     => (is => 'rw', isa => 'ArrayRef[Maybe[Value]]', lazy_build => 1,);
has 'fieldid'     => (is => 'rw', isa => 'ArrayRef[Int]',          lazy_build => 1,);

# TODO: Scan the dir for pm's and dynamically apply those roles (instead of the list of 'with' below)

with
  'Interfaces::FlatFile' => {
	alias => {ReadRecord => 'FlatFile_ReadRecord', WriteRecord => 'FlatFile_WriteRecord', ReadData => 'FlatFile_ReadData', WriteData => 'FlatFile_WriteData',},
	excludes => ['ReadRecord', 'WriteRecord', 'ReadData', 'WriteData',]
							 };
with							 
  'Interfaces::DelimitedFile' => {
								   alias => {
											 ReadRecord         => 'DelimitedFile_ReadRecord',
											 WriteRecord        => 'DelimitedFile_WriteRecord',
											 ReadData           => 'DelimitedFile_ReadData',
											 WriteData          => 'DelimitedFile_WriteData',
											 ConfigureUseInFile => 'DelimitedFile_ConfigureUseInFile',
											},
								   excludes => ['ReadRecord', 'WriteRecord', 'ReadData', 'WriteData', 'ConfigureUseInFile',]
								  };
with
  'Interfaces::ExcelBinary' => {
								 alias => {
										   ReadRecord         => 'ExcelBinary_ReadRecord',
										   WriteRecord        => 'ExcelBinary_WriteRecord',
										   ReadData           => 'ExcelBinary_ReadData',
										   WriteData          => 'ExcelBinary_WriteData',
										   ConfigureUseInFile => 'ExcelBinary_ConfigureUseInFile',
										  },
								 excludes => ['ReadRecord', 'WriteRecord', 'ReadData', 'WriteData', 'ConfigureUseInFile',]
								};
with
  'Interfaces::DataTable';

{
	my $meta = __PACKAGE__->meta;
	no strict;
	foreach my $build_attribute ($meta->get_all_attributes) {
		my $build_attributename = $build_attribute->name;
		#		print ("Creating builder for attribute [" . $build_attributename . "]\n");
		if (!defined *{__PACKAGE__ . '::_build_' . $build_attributename}) {
			*{__PACKAGE__ . '::_build_' . $build_attributename} = sub {
				my $self      = shift;
				my $meta      = $self->meta;
				my $attribute = $meta->find_attribute_by_name($build_attributename);
				if (!defined $attribute) { Carp::confess("Error: can't find attribute [$build_attributename]\n"); }
				my $type_name = $attribute->type_constraint->name;
				if ($attribute->type_constraint->is_a_type_of("ArrayRef")) { return []; }
				elsif ($attribute->type_constraint->is_a_type_of("HashRef")) { return {}; }
				elsif ($attribute->type_constraint->equals("Str"))           { return ""; }
				elsif ($attribute->type_constraint->is_a_type_of("Num"))     { return 0; }
				else                                                         { return undef }
			};
		} ## end if (!defined *{__PACKAGE__...})
	} ## end foreach my $build_attribute...
	use strict;
}

sub BUILD {
	my $self    = shift;
	my $hr_args = shift;
	# Load configuration from given $dbh for interface with $name
	if (exists $hr_args->{dbh} and defined $hr_args->{dbh} and exists $hr_args->{name}) {
		# Multiple interfaces can be set up using a single definition. This is done using aliases.
		my $hr_aliases = $hr_args->{dbh}->selectall_hashref("SELECT * FROM datarepos_alias", "tablename")
		  or Carp::confess("Interface: Error fetching table aliases from repository: " . $hr_args->{dbh}->errstr);
		my $repository_tablename = $hr_aliases->{$hr_args->{name}}->{use_tablename} // $hr_args->{name};
		# Fields
		$self->{config}->{Fields} = $hr_args->{dbh}->selectall_hashref("SELECT * FROM datarepository WHERE tablename=? ORDER BY fieldid", "fieldname", undef, $repository_tablename)
		  or Carp::confess("Interface: Error loading field information from repository: " . $hr_args->{dbh}->errstr);
		# Indices
		$self->{config}->{Indices} = $hr_args->{dbh}->selectall_hashref("SELECT * FROM datareposidx WHERE tablename=?", "keyname", undef, $repository_tablename)
		  or Carp::confess("Interface: Error loading indices information from repository: " . $hr_args->{dbh}->errstr);
		foreach my $fieldname (keys (%{$self->{config}->{Fields}})) {
			$self->{config}->{Fields}->{$fieldname}->{signed}    = $self->{config}->{Fields}->{$fieldname}->{signed}    eq 'Y' ? 1 : 0;
			$self->{config}->{Fields}->{$fieldname}->{allownull} = $self->{config}->{Fields}->{$fieldname}->{allownull} eq 'Y' ? 1 : 0;
		}
		# Apply retrieved configuration
		$self->ReConfigureFromHash($self->config);
	} ## end if (exists $hr_args->{...})
	    # Initialize non-undef default values for attributes
	$self->decimalseperator('.');
} ## end sub BUILD

sub Check {
	my $self = shift;
	# Check if all configuration data is valid (for Interface only)
	if (!$self->has_config) { return undef; }
	print ("Checking...");
	if ($self->has_name) {
		print ($self->name);
	}
	print ("\n");
	my $meta = $self->meta;
	# Check if all arrayref attributes contain the same amount of elements, use columns as leading
	my $num_arrayref_elements = $#{$self->columns};
	print ("Checking if all arrayref attributes contain the same amount of elements...");
	foreach my $attribute ($meta->get_all_attributes) {
		my $attributename = $attribute->name;
		if ($attribute->type_constraint->name =~ /^ArrayRef/) {
			if ($num_arrayref_elements != $#{$self->$attributename}) {
				Carp::confess(  "Attribute ["
							  . $attributename
							  . "] does not have the same amount of elements as there are columns ["
							  . $#{$self->$attributename}
							  . "] vs [$num_arrayref_elements]");
			} ## end if ($num_arrayref_elements...)
		} ## end if ($attribute->type_constraint...)
	} ## end foreach my $attribute ($meta...)
	print ("[OK]\n");
	# Check if all fields are accounted for ($self->fieldid is continuous)
	# $self->fieldid->[0] = 1, $self->fieldid->[n] = $self->fieldid->[n-1] + 1
	print ("Checking if all fields are accounted for...");
	if ($self->fieldid->[0] != 1) {
		Carp::confess("Column [" . $self->columns->[0] . "] has fieldid [" . $self->fieldid->[0] . "], expected [1]. FieldIDs not continous");
	}
	foreach (1 .. $num_arrayref_elements) {
		if ($self->fieldid->[$_] != $self->fieldid->[$_ - 1] + 1) {
			Carp::confess("Column [" . $self->columns->[$_] . "] has fieldid [" . $self->fieldid->[$_] . "], expected [" . $_ + 1 . "]. FieldIDs not continous");
		}
	}
	print ("[OK]\n");
	# Check if all columns have a (valid) datatype
	print ("Checking if all columns have a valid datatype...");
	if (!$self->has_datatype) { Carp::confess("No datatypes configured."); }
	foreach (0 .. $num_arrayref_elements) {
		if ($self->datatype->[$_] !~ /CHAR|VARCHAR|TEXT|TINYINT|SMALLINT|MEDIUMINT|INT|BIGINT|INTEGER|FLOAT|DOUBLE|DATE|TIME|ENUM|NUMERIC|MONEY|BIT/i) {
			Carp::confess("Column [" . $self->columns->[$_] . "] has unknown datatype [" . $self->datatype->[$_] . "]");
		}
	}
	print ("[OK]\n");
	# Check if all columns of type CHAR|VARCHAR|TEXT have a length
	# Check if all columns of type NUMERIC|DECIMAL have defined decimals (0 is allowed)
	# Check if all columns of type TINYINT|SMALLINT|MEDIUMINT|INT|BIGINT|INTEGER have defined signed
	print ("Checking if all text-columns have a length, all float/double columns have decimals and all integer columns have defined the 'signed' attribute...");
	foreach (0 .. $num_arrayref_elements) {
		if ($self->datatype->[$_] =~ /CHAR|VARCHAR|TEXT/i and $self->length->[$_] <= 0) {
			Carp::confess("Column [" . $self->columns->[$_] . "] has datatype [" . $self->datatype->[$_] . "] but length [" . $self->length->[$_] . "]");
		} elsif ($self->datatype->[$_] =~ /NUMERIC|DECIMAL/i and !defined $self->decimals->[$_]) {
			Carp::confess("Column [" . $self->columns->[$_] . "] has datatype [" . $self->datatype->[$_] . "] but decimals has not been defined");
		} elsif ($self->datatype->[$_] =~ /TINYINT|SMALLINT|MEDIUMINT|INT|BIGINT|INTEGER/i and !defined $self->signed->[$_]) {
			Carp::confess("Column [" . $self->columns->[$_] . "] has datatype [" . $self->datatype->[$_] . "] but signed has not been defined");
		}
	} ## end foreach (0 .. $num_arrayref_elements)
	print ("[OK]\n");
	print ("Checking if numeric-typed columns have numeric defaults: ");
	foreach (0 .. $num_arrayref_elements) {
		if ($self->datatype->[$_] =~ /FLOAT|DOUBLE|TINYINT|SMALLINT|MEDIUMINT|INT|BIGINT|INTEGER|NUMERIC/i and ($self->default->[$_] eq '0' or $self->default->[$_] > 0)) {
			Carp::confess("Column [" . $self->columns->[$_] . "] has datatype [" . $self->datatype->[$_] . "] but non-numeric default [" . $self->default->[$_] . "]");
		}
	}
	print ("[Done]\n");
} ## end sub Check

method ReConfigureFromHash($hr_config !) {
#sub ReConfigureFromHash {
#	my ($self, $hr_config) = @_;
	my $meta = $self->meta;
	if (!defined $hr_config) { return undef; }
	# Clear ArrayRef-type attributes (this clears ALL attributes...including those generated by roles)
	foreach ($meta->get_all_attributes) {
		if ($_->type_constraint->name =~ /^ArrayRef/) {
			$_->clear_value($self);
		}
	}
	if (!defined $hr_config and $self->has_config) {
		Carp::confess("Trying to reconfigure Base with empty configdata");
	}
	# Reconfigure
	$self->config($hr_config);
	my @keys = keys (%{$hr_config->{Fields}});
	if (!@keys) { Carp::confess("Empty config supplied"); }
	# Set the columns
	my $ar_Columns;
	foreach my $Column (@keys) {
		$ar_Columns->[$hr_config->{Fields}->{$Column}->{fieldid} - 1] = $Column;    # fieldid starts at 1
	}
	$self->columns($ar_Columns);
	# Set all other attributes
	foreach my $ColumnIndex (0 .. $#{$self->columns}) {
		my $Column = $self->columns->[$ColumnIndex];
		if (!defined $Column) { Carp::confess("Undefined columnname with fieldid [" . ($ColumnIndex + 1) . "]"); }
		foreach ($meta->get_all_attributes) {
			my $attributename = $_->name;
			if ($attributename eq "columns") { next; }                              # Skip columns-attribute. We already did that one.
			if ($_->type_constraint->name =~ /^ArrayRef/) {
				push (@{$self->$attributename}, $hr_config->{Fields}->{$Column}->{$attributename});
			}
		} ## end foreach ($meta->get_all_attributes)
	} ## end foreach my $ColumnIndex (0 ...)
} ## end sub ReConfigureFromHash

sub MakeNewConfig ($) {
	my $self = shift;
	my $meta = $self->meta;
	# Clear current config
	delete $self->{config};
	my @attributes = $meta->get_all_attributes;
	my @attributes_ArrayRef;
	my @attributes_HashRef;
	my @attributes_Scalar;
	foreach my $attribute (@attributes) {
		if ($attribute->name eq "columns") { next; }
		given ($attribute->type_constraint->name) {
			when (/^ArrayRef/) { push (@attributes_ArrayRef, $attribute); }
			when (/^HashRef/)  { push (@attributes_HashRef,  $attribute); }
			push (@attributes_Scalar, $attribute);
		}
	} ## end foreach my $attribute (@attributes)
	foreach (@attributes_ArrayRef) {
		my $attributename = $_->name;
		foreach my $ColumnIndex (0 .. $#{$self->columns}) {
			my $Column = $self->columns->[$ColumnIndex];
			$self->{config}->{Fields}->{$Column}->{$attributename} = $self->$attributename->[$ColumnIndex];
		}
	} ## end foreach (@attributes_ArrayRef)
} ## end sub MakeNewConfig ($)

sub DESTROY {
	my $self = shift;
	#	Carp::carp("Destroying interface for [" . $self->tablename . "]\n");
}

1;

=head1 NAME

Interfaces::Interface - Generic data-interface between file-formats and databases

=head1 VERSION

This document refers to Interfaces::Interface version 0.10.

=head1 SYNOPSIS

  use Interfaces::Interface;
  my $interface = Interfaces::Interface->new();

=head1 C<Interfaces> MODULES

The C<Interfaces> hierarchy of modules is an attempt at creating a general
method for transferring data from various file-formats and (MySQL) databases to 
other file-formats and (MYSQL) databases. Currently implemented are:

=over 4

=item * Interfaces::FlatFile

=item * Interfaces::DelimitedFile

=item * Interfaces::DataTable

=item * Interface::ExcelBinary

=back

=head1 DESCRIPTION

This module is the main module of the Interfaces-hierarchy and is the only
one that needs to be instantiated to use. All other modules add Moose::Roles to this
interface to extend funcionality.
The interface itself cannot do anything, it depends on additional modules to provide
the various read- and write-methods.
The interface can be configured using ReConfigureFromHash with a given hashref filled
with configuration data. The basic data that all interfaces require consists of the
following:

=over 4

=item * a (table)name which defines the name of the interface (and is also the default
tablename used when interfacing with a (MySQL) database using Interfaces::DataTable).

=item * an arrayref with columnnames. These are used when referencing specific columns,
 and also when interfacing with a (MySQL) database.

=item * an arrayref with (MySQL) datatypes describing the type of each column.

=item * an arrayref with lengths describing the amount of characters (or digits for numeric 
types) used for each column.

=item * an arrayref describing the amount of digits used in the fraction of numeric types
(that support fractions) for each column. This is undefined for columns with types that 
don't use fractions.

=item * an arrayref describing whether or not a numeric type is signed. This is undefined
for columns with non-numeric types.

=item * an arrayref describing whether a column may contain NULL (undefined) values.

=item * an arrayref containing the default values that should be given to a column.

=item * an arrayref containing a field-id for each column. This is not used in the 
interface itself, but in the configuration of the interface to indicate the order in which 
columns should be used.

=back

Modules which add roles can introduce other attributes that need to be supplied in the
configuration data. The DelimitedFile-module needs a delimiter and a displayname (for the
header row), and the FlatFile-module requires flatfield_start and flatfield_length-attributes.


=head2 Methods for C<Interfaces::Interface>

=over 4

=item * C<my $interface = Interfaces::Interface-E<gt>new($dbh, $name);>

Calls C<Interfaces::Interface>'s C<new> method. Creates an unconfigured interface object.
Optionally can be supplied with an active database handle and an interface name. The 
interface will automatically be configured using data from tables 'datarepository', 
'datareposidx' and 'datarepos_alias' that should be present in the supplied database.
This method (BUILD) can be augmented (using Moose's "after") for each additional module 
in the Interfaces-hierarchy.

=item * C<$interface-E<gt>ReConfigureFromHash($hr_config);>

Configures the interface object with the supplied configuration. Will Carp::confess if some basic
checks pertaining the integrity of the configuration are not met.

=item * C<$interface-E<gt>Check();>

Starts a more thorough check on the integrity and correctness of the currently configured interface
object. This method can be augmented (using Moose's "after") for each additional module in the
Interfaces-hierarchy.

=back

=head1 DEPENDENCIES

L<Moose>, L<Carp> and L<Perl 5.10>

=head1 AUTHOR

The original author is Herbert Buurman

=head1 LICENSE

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See L<perlartistic>.

=cut
