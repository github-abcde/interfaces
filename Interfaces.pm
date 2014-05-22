package Interfaces;
# Version 0.11	30-08-2011
# previously Copyright (C) THR 2011
# Copyright released by THR in 2013

use Moose;    # automatically turns on strict and warnings
use 5.010;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater
use MooseX::Method::Signatures;
use File::Spec;
use File::Find::Rule;
use Data::Dump;
use Devel::Peek;
use List::Util;
use Carp;
use POSIX;
use constant DATATYPE_UNKNOWN => 0; # default
use constant DATATYPE_TEXT => 1;
use constant DATATYPE_DATETIME => 2;
use constant DATATYPE_NUMERIC => 16;
use constant DATATYPE_FLOATINGPOINT => 17;
use constant DATATYPE_FIXEDPOINT => 18;

use constant DATATYPES => {
	CHAR => { type => DATATYPE_TEXT },
	VARCHAR => { type => DATATYPE_TEXT },
	TEXT => { type => DATATYPE_TEXT },
	DATE => { type => DATATYPE_TEXT },
	TIME => { type => DATATYPE_TEXT },
	DATETIME => { type => DATATYPE_TEXT },
	TIMESTAMP => { type => DATATYPE_TEXT },
	TINYINT => { type => DATATYPE_NUMERIC, min => - (2**7), max => 2**8 - 1, },
	SMALLINT => { type => DATATYPE_NUMERIC, min => - (2**15), max => 2**16 - 1, },
	MEDIUMINT => { type => DATATYPE_NUMERIC, min => - (2**23), max => 2**24 - 1, },
	INT => { type => DATATYPE_NUMERIC, min => - (2**31), max => 2**32 - 1, },
	INTEGER => { type => DATATYPE_NUMERIC, min => - (2**31), max => 2**32 - 1, },
	BIGINT => { type => DATATYPE_NUMERIC, min => - (2**63), max => 2**64 - 1, },
	FLOAT => { type => DATATYPE_FLOATINGPOINT },
	DOUBLE => { type => DATATYPE_FLOATINGPOINT },
	NUMERIC => { type => DATATYPE_FIXEDPOINT },
	DECIMAL => { type => DATATYPE_FIXEDPOINT },
};

BEGIN {
	@Interfaces::methods = ();
	$Interfaces::DEBUGMODE = 1;
}

# General info
has 'config'            => (is => 'rw', isa => 'HashRef[HashRef[HashRef[Maybe[Value]]]]',	lazy_build => 1,);
has 'name'              => (is => 'rw', isa => 'Maybe[Str]',								lazy_build => 1,);
has 'decimalseparator'  => (is => 'rw', isa => 'Str',										lazy_build => 1,);
has 'thousandseparator' => (is => 'rw', isa => 'Str',										lazy_build => 1,);
has 'overflow_method'	=> (is => 'rw', isa => 'Int',										lazy_build => 1,);
# Fields info
has 'columns'     		=> (is => 'rw', isa => 'ArrayRef[Str]',								lazy_build => 1,);
has 'displayname' 		=> (is => 'rw', isa => 'ArrayRef[Str]',								lazy_build => 1,);
has 'datatype'    		=> (is => 'rw', isa => 'ArrayRef[Str]',								lazy_build => 1,);
has 'internal_datatype' => (is => 'rw', isa => 'ArrayRef[HashRef[Value]]',					lazy_build => 0,);
has 'length'      		=> (is => 'rw', isa => 'ArrayRef[Maybe[Int]]',						lazy_build => 1,);
has 'decimals'    		=> (is => 'rw', isa => 'ArrayRef[Maybe[Int]]',						lazy_build => 1,);
has 'signed'      		=> (is => 'rw', isa => 'ArrayRef[Maybe[Bool]]',						lazy_build => 1,);
has 'allownull'   		=> (is => 'rw', isa => 'ArrayRef[Bool]',							lazy_build => 1,);
has 'default'     		=> (is => 'rw', isa => 'ArrayRef[Maybe[Value]]',					lazy_build => 1,);
has 'fieldid'     		=> (is => 'rw', isa => 'ArrayRef[Int]',								lazy_build => 1,);

sub BUILD {
	my $self    = shift;
	my $hr_args = shift;
	# Load configuration from given $dbh for interface with $name
	if (exists $hr_args->{dbh} and defined $hr_args->{dbh} and exists $hr_args->{name}) {
		# Multiple interfaces can be set up using a single definition. This is done using aliases.
		my $hr_aliases = $hr_args->{dbh}->selectall_hashref("SELECT * FROM datarepos_alias", "tablename")
		  or Crash("Interface: Error fetching table aliases from repository: " . $hr_args->{dbh}->errstr);
		my $repository_tablename = $hr_aliases->{$hr_args->{name}}->{use_tablename} // $hr_args->{name};
		# Fields
		$self->{config}->{Fields} = $hr_args->{dbh}->selectall_hashref("SELECT * FROM datarepository WHERE tablename=? ORDER BY fieldid", "fieldname", undef, $repository_tablename)
		  or Crash("Interface: Error loading field information from repository: " . $hr_args->{dbh}->errstr);
		# Indices
		$self->{config}->{Indices} = $hr_args->{dbh}->selectall_hashref("SELECT * FROM datareposidx WHERE tablename=?", "keyname", undef, $repository_tablename)
		  or Crash("Interface: Error loading indices information from repository: " . $hr_args->{dbh}->errstr);
		foreach my $fieldname (keys (%{$self->{config}->{Fields}})) {
			$self->{config}->{Fields}->{$fieldname}->{signed}    = $self->{config}->{Fields}->{$fieldname}->{signed}    eq 'Y' ? 1 : 0;
			$self->{config}->{Fields}->{$fieldname}->{allownull} = $self->{config}->{Fields}->{$fieldname}->{allownull} eq 'Y' ? 1 : 0;
		}
		# Apply retrieved configuration
		$self->ReConfigureFromHash($self->config);
	} ## end if (exists $hr_args->{...})
	    # Initialize non-undef default values for attributes
	$self->decimalseparator('.');
	$self->overflow_method(OVERFLOW_METHOD_ERROR);
} ## end sub BUILD

method Check() {
	# Check if all configuration data is valid (for Interface only)
	if (!$self->has_config) { return undef; }
	if (defined $Interfaces::DEBUGMODE) {
		print ("Checking...");
		if ($self->has_name) {
			print ($self->name);
		}
		print ("\n");
	}
	my $meta = $self->meta;
	# Check if all arrayref attributes contain the same amount of elements, use columns as leading
	my $num_arrayref_elements = $#{$self->columns};
	print ("Checking if all arrayref attributes contain the same amount of elements...") if defined $Interfaces::DEBUGMODE;
	foreach my $attribute ($meta->get_all_attributes) {
		my $attributename = $attribute->name;
		if ($attribute->{lazy_build} == 0) { next; } # Skip attributes die zonder lazy_build zijn gedefinieerd.
		if ($attribute->type_constraint->name =~ /^ArrayRef/) {
			if ($num_arrayref_elements != $#{$self->$attributename}) {
				Crash(  "Attribute ["
							  . $attributename
							  . "] does not have the same amount of elements as there are columns ["
							  . $#{$self->$attributename}
							  . "] vs [$num_arrayref_elements]"
				);
			} ## end if ($num_arrayref_elements...)
		} ## end if ($attribute->type_constraint...)
	} ## end foreach my $attribute ($meta...)
	print ("[OK]\n") if defined $Interfaces::Interface::DEBUGMODE;
	# Check if all fields are accounted for ($self->fieldid is continuous)
	# $self->fieldid->[0] = 1, $self->fieldid->[n] = $self->fieldid->[n-1] + 1
	print ("Checking if all fields are accounted for...") if defined $Interfaces::DEBUGMODE;
	if ($self->fieldid->[0] != 1) {
		Crash("Column [" . $self->columns->[0] . "] has fieldid [" . $self->fieldid->[0] . "], expected [1]. FieldIDs not continous");
	}
	foreach (1 .. $num_arrayref_elements) {
		if ($self->fieldid->[$_] != $self->fieldid->[$_ - 1] + 1) {
			Crash("Column [" . $self->columns->[$_] . "] has fieldid [" . $self->fieldid->[$_] . "], expected [" . $_ + 1 . "]. FieldIDs not continous");
		}
	}
	print ("[OK]\n") if defined $Interfaces::DEBUGMODE;
	# Check if all columns have a (valid) datatype
	print ("Checking if all columns have a valid datatype...") if defined $Interfaces::DEBUGMODE;
	if (!$self->has_datatype) { Crash("No datatypes configured."); }
	foreach (0 .. $num_arrayref_elements) {
		if (!defined DATATYPES->{$self->datatype->[$_]}) {
			Crash("Column [" . $self->columns->[$_] . "] has unknown datatype [" . $self->datatype->[$_] . "]");
		}
	}
	print ("[OK]\n") if defined $Interfaces::DEBUGMODE;
	# Check if all columns of type DATATYPE_TEXT have a length
	# Check if all columns of type DATATYPE_FLOATINGPOINT and DATATYPE_FIXEDPOINT have defined decimals (0 is allowed, but $decimals == $length is not, at least 1 non-decimal digit has to be present)
	# Check if all columns of type DATATYPE_NUMERIC have defined signed
	print ("Checking if all text-columns have a length, all float/double columns have decimals and all integer columns have defined the 'signed' attribute...") if defined $Interfaces::DEBUGMODE;
	foreach (0 .. $num_arrayref_elements) {
		if ($self->internal_datatype->[$_]->{type} == DATATYPE_TEXT and $self->length->[$_] <= 0) {
			Crash("Column [" . $self->columns->[$_] . "] has datatype [" . $self->datatype->[$_] . "] but length [" . $self->length->[$_] . "]");
		} elsif ($self->internal_datatype->[$_]->{type} > DATATYPE_NUMERIC and (!defined $self->decimals->[$_] or (($self->length->[$_] // 0) <= 0))) {
			Crash("Column [" . $self->columns->[$_] . "] has datatype [" . $self->datatype->[$_] . "] but decimals,length has not been defined properly [" . $self->decimals->[$_] .',' . $self->length->[$_] . ']');
		} elsif ($self->internal_datatype->[$_]->{type} > DATATYPE_NUMERIC and ($self->decimals->[$_] == $self->length->[$_])) {
			Crash("Column [" . $self->columns->[$_] . "] has datatype [" . $self->datatype->[$_] . "] with only decimals (at least 1 non-decimal is required) [" . $self->decimals->[$_] .',' . $self->length->[$_] . ']');
		} elsif ($self->internal_datatype->[$_]->{type} == DATATYPE_NUMERIC and ($self->decimals->[$_] // 0) > 0) {
			Crash("Column [" . $self->columns->[$_] . "] has datatype [" . $self->datatype->[$_] . "] but has decimals");
		}
		if ($self->internal_datatype->[$_]->{type} >= DATATYPE_NUMERIC and !defined $self->signed->[$_]) {
			Crash("Column [" . $self->columns->[$_] . "] has datatype [" . $self->datatype->[$_] . "] but signed has not been defined");
		}
	} ## end foreach (0 .. $num_arrayref_elements)
	print ("[OK]\n") if defined $Interfaces::DEBUGMODE;
	# Check if numeric-typed columns have numeric defaults
	print("Checking if numeric-typed columns have numeric defaults: ") if defined $Interfaces::DEBUGMODE;
	foreach (0 .. $num_arrayref_elements) {
		# But only if allownull = false
		if (defined $self->default->[$_] and $self->internal_datatype->[$_]->{type} >= DATATYPE_NUMERIC and !($self->default->[$_] eq '0' or $self->default->[$_] > 0)) {
			Crash("Column [" . $self->columns->[$_] . "] has datatype [" . $self->datatype->[$_] . "] but non-numeric default [" . $self->default->[$_] . "]");
		}
	} ## end foreach (0 .. $num_arrayref_elements)
	print("[Done]\n") if defined $Interfaces::DEBUGMODE;
	1;
} ## end sub Check

method ClearConfig () {
	my $meta = $self->meta;
	# Clear ArrayRef-type attributes (this clears ALL attribute values...including those generated by roles)
	foreach ($meta->get_all_attributes) {
		if ($_->type_constraint->name =~ /^ArrayRef/) {
			$_->clear_value($self);
		}
	}
}

method ReConfigureFromHash($hr_config !) {
	my $meta = $self->meta;
	$self->ClearConfig();
	if (!defined $hr_config and $self->has_config) {
		Crash("Trying to reconfigure Base with empty configdata");
	}
	# Reconfigure
	$self->config($hr_config);
	my @keys = keys (%{$hr_config->{Fields}});
	if (!@keys) { Crash("Empty config supplied"); }
	# Set the columns
	my $ar_Columns;
	foreach my $Column (@keys) {
		$ar_Columns->[$hr_config->{Fields}->{$Column}->{fieldid} - 1] = $Column;    # fieldid starts at 1
	}
	$self->columns($ar_Columns);
	# Set all other attributes
	foreach my $ColumnIndex (0 .. $#{$self->columns}) {
		my $Column = $self->columns->[$ColumnIndex];
		my $hr_attributes;
		foreach my $attribute ($meta->get_all_attributes) {
			if ($attribute->{lazy_build} == 0) { next; }	# Skip attributes die zonder lazy_build zijn gedefinieerd.
			my $attributename = $attribute->name;
			if ($attributename eq "columns") { next; }		# Skip columns-attribute. We already did that one.
			if (!defined $Column) { Crash("Undefined columnname with fieldid [" . ($ColumnIndex + 1) . "]"); }
			if ($attribute->type_constraint->name =~ /^ArrayRef/) {
				push (@{$self->$attributename}, $hr_config->{Fields}->{$Column}->{$attributename});
			}
		} ## end foreach ($meta->get_all_attributes)
	} ## end foreach my $ColumnIndex (0 ...)
	# Init internal_datatype for speed (saves having to do regexes for each ReadRecord call)
	foreach my $index (0 .. $#{$self->columns}) {
		$self->{internal_datatype}->[$index] = DATATYPES->{$self->{datatype}->[$index]} // DATATYPE_UNKNOWN;
	}
	1;
} ## end sub ReConfigureFromHash

method MakeNewConfig() {
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

method AddField($hr_config !) {
	if (ref($hr_config) ne 'HASH') {
		Crash("1st Argument passed is not a hashref");
	}
	# Pre-add check
	# 1 - Check if datatype is valid
	if (!defined DATATYPES->{$hr_config->{datatype}}) {
		Crash("Supplied datatype [$hr_config->{datatype}] is not valid");
	}
	# 2 - Check if column of type CHAR|VARCHAR|TEXT have a length
	# 2 - Check if column of type NUMERIC|DECIMAL have defined decimals (0 is allowed), default signed to 'Y'
	# 2 - Check if column of type TINYINT|SMALLINT|MEDIUMINT|INT|BIGINT|INTEGER have defined signed
	my $internal_datatype = DATATYPES->{$hr_config->{datatype}}->{type};
	given ($internal_datatype) {
		when (DATATYPE_TEXT) {
			if (($hr_config->{length} // 0) <= 0) {
				Crash("Column [" . $hr_config->{fieldname} . "] has datatype [" . $hr_config->{datatype} . "] but length [" . $hr_config->{length} . "]");
			}
		}
		when ([DATATYPE_FLOATINGPOINT, DATATYPE_FIXEDPOINT]) {
			if (!defined $hr_config->{decimals} or (($hr_config->{length} // 0) <= 0)) {
				Crash("Column [" . $hr_config->{fieldname} . "] has datatype [" . $hr_config->{datatype} . "] but decimals,length has not been defined properly [" . $hr_config->{decimals} .',' . $hr_config->{length} . ']');
			}
			$hr_config->{signed} = 'Y';
		}
		when (DATATYPE_NUMERIC) {
			if (!defined $hr_config->{signed}) {
				Crash("Column [" . $hr_config->{fieldname} . "] has datatype [" . $hr_config->{datatype} . "] but signed has not been defined");
			}
			$hr_config->{length} //= length("" . DATATYPES->{$hr_config->{datatype}}->{max});
		}
	}
	# 3 - Check if datatype is numeric but the default exists and is not numeric
	if (defined $hr_config->{default} and $internal_datatype > DATATYPE_NUMERIC and !($hr_config->{default} eq '0' or $hr_config->{default} > 0)) {
		Crash("Column [" . $hr_config->{fieldname} . "] has datatype [" . $hr_config->{datatype} . "] but non-numeric default [" . $hr_config->{default} . "]");
	}
	# All ok, proceed with adding the field to the interface
	# Generate field_id based on last used fieldid
	$hr_config->{fieldid} = ($self->fieldid->[-1] // 0) + 1;
	push(@{$self->columns}, $hr_config->{fieldname});
	my $meta = $self->meta;
	foreach ($meta->get_all_attributes) {
		my $attributename = $_->name;
		if ($_->{lazy_build} == 0) { next; } # Skip attributes die zonder lazy_build zijn gedefinieerd.
		if ($attributename eq "columns") { next; }                              # Skip columns-attribute. We already did that one.
		if ($_->type_constraint->name =~ /^ArrayRef/) {
			push (@{$self->$attributename}, $hr_config->{$attributename});
		}
	}
	# Custom initialization for lazy-built attributes
	push(@{$self->{internal_datatype}}, DATATYPES->{$hr_config->{datatype}});
}

# Reduces length of $value until it fits $length,decimals, truncates from left to right (so only gets the LSB)
method fix_runlength(Int $fieldid !, $value !) {
	my ($internal_datatype, $target_signed, $length, $decimals) = ($self->{internal_datatype}->[$fieldid], $self->{signed}->[$fieldid], $self->{length}->[$fieldid], $self->{decimals}->[$fieldid]);
	# Translate signed = 'Y'/'N' to 1/0
	my $source_signed = $value < 0 ? 1 : 0;
	$target_signed = $target_signed eq 'Y' ? 1 : 0;
	# Split the value in an integer and fractional part
	my $current_num_decimals = 0;
	if (index($value, $self->decimalseparator) >= 0) {
		$current_num_decimals = length($value) - index($value, $self->decimalseparator) - $source_signed;
	}
	my ($fraction, $integer) = POSIX::modf($value);
	$fraction = sprintf("%.0${current_num_decimals}f", $fraction); # Fix floating point errors from POSIX::modf
#print("fix_runlength [$integer, $fraction], signed, decimals,current_num_decimals [$source_signed, $decimals, $current_num_decimals] [" . List::Util::min($length - $decimals, length($integer) - $source_signed) . "]\n");
	# Truncate
	$integer = reverse(substr(reverse($integer), 0, List::Util::min($length - $decimals, length($integer) - $source_signed))) if $integer;
	$fraction = substr($fraction, $source_signed + 2, List::Util::min($decimals, $current_num_decimals)) if length($fraction) > 2;
#print("fix_runlength2 [$integer, $fraction], [" . List::Util::min($length - $decimals, length($integer) - $source_signed) . "]\n");
	$value = ($source_signed ? -1 : 1) * ($integer + "0.$fraction");
#print("fix_runlength3 [$value]\n");
	# Add trailing significant decimals
	if ($decimals > 0) {
		$value =~ s/\.([0-9]*)/'.' . substr($1, 0, $decimals)/e;
	}
	return $value;
}

method fix_typesize(Int $fieldid !, $value !) {
	my ($internal_datatype, $signed, $length, $decimals) = ($self->{internal_datatype}->[$fieldid], $self->{signed}->[$fieldid], $self->{length}->[$fieldid], $self->{decimals}->[$fieldid] // 0);
	my ($minvalue, $maxvalue);
	my ($minvalue_round, $maxvalue_round) = (- (10**($length - $decimals)) + (10**(-$decimals)), (10**($length - $decimals)) - (10**(-$decimals)));
	# Translate signed = 'Y'/'N' to 1/0
	$signed = $signed eq 'Y' ? 1 : 0;
	if ($internal_datatype->{type} == DATATYPE_NUMERIC) {
		if ($signed) {
			$minvalue = $internal_datatype->{min};
			$maxvalue = - $minvalue - 1;
		} else {
			$minvalue = 0;
			$maxvalue = $internal_datatype->{max};
		}
		# If the minimum or maximum value doesn't fit in $length, get the largest number that does fit in $length
		if ($minvalue < $minvalue_round) { $minvalue = $minvalue_round; }
		if ($maxvalue > $maxvalue_round) { $maxvalue = $maxvalue_round; }
	} elsif ($internal_datatype->{type} > DATATYPE_NUMERIC) {
		if ($signed) {
			$minvalue = - (10**($length - $decimals)) + (10**(-$decimals));
			$maxvalue = (10**($length - $decimals)) - (10**(-$decimals));
		} else {
			$minvalue = 0;
			$maxvalue = (10**($length - $decimals)) - (10**(-$decimals));
		}
	}
#print("Min [$minvalue] max [$maxvalue]\n");
	if ($value < $minvalue) { $value = $minvalue; }
	elsif ($value > $maxvalue) { $value = $maxvalue; }
	return $value;
}

method minmax(Int $fieldid !, $value !) {
	# For OVERFLOW_METHOD_ROUND, read the value as-is, then round to within respectively $datatype_size and $length,decimals
	# For OVERFLOW_METHOD_TRUNC, read the value as-is, then truncate the value within respectively $length,decimals and $datatype_size
	my ($internal_datatype, $signed, $length, $decimals) = ($self->{internal_datatype}->[$fieldid], $self->{signed}->[$fieldid], $self->{length}->[$fieldid], $self->{decimals}->[$fieldid] // 0);
	# Translate signed = 'Y'/'N' to 1/0
if (!defined $signed) { Crash("Not signed?!"); }
	$signed = $signed eq 'Y' ? 1 : 0;
	if ($self->{overflow_method} == OVERFLOW_METHOD_ERROR) {
		if ($signed and $value < 0) { Crash('Value [' . $value . '] below minimum [0]'); }
		my $copy_of_value = $value;
		$copy_of_value =~ s/$self->{decimalseparator}//;
		if (length($copy_of_value) > $length) { Crash('value [' . $value . '] too large to fit in [' . $length . '] figures'); }
	} elsif ($self->{overflow_method} == OVERFLOW_METHOD_TRUNC) {
		if (!$decimals) {
			# Truncate to no decimals
			$value = int($value);
		} elsif ($decimals == $length) {
			# Special case, truncate to only decimals
			$value = POSIX::fmod($value, 1);
		}
		$value = $self->fix_runlength($fieldid, $value);
		$value = $self->fix_typesize($fieldid, $value);
	} elsif ($self->{overflow_method} == OVERFLOW_METHOD_ROUND) {
		# First round to proper amount of decimals
		$value = sprintf("%.${decimals}f", $value);
		$value = $self->fix_typesize($fieldid, $value);
	} else {
		Crash("Unknown overflow method selected [" . $self->{overflow_method});
	}
	return $value;
}

sub Crash {
	defined $Interfaces::DEBUGMODE ? Carp::confess(@_) : die(@_);
}

sub DESTROY {
	my $self = shift;
	#	Carp::carp("Destroying interface for [" . $self->tablename . "]\n");
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
	# Export own methods as aliases
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

INIT {
# Automatically create accessors, _build_-functions for all attributes (including ones from roles, which are applied at this point)
	my $meta = __PACKAGE__->meta;
	no strict;
	foreach my $build_attribute ($meta->get_all_attributes) {
		my $build_attributename = $build_attribute->name;
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
