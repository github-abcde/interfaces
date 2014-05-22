package Interfaces::Interface;
# Version 2.0.0	03-01-2012
# Copyright (C) OGD 2011-2012

use Moose;    # automatically turns on strict and warnings
use 5.010;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater

#$Interfaces::Interface::DEBUGMODE = 1;
use Smart::Comments;
use Data::Dump;
use Carp;
use Devel::Peek;
use MooseX::Method::Signatures;
use Readonly;

$Interfaces::Interface::DATATYPE_UNKNOWN       = 0;    # default
$Interfaces::Interface::DATATYPE_TEXT          = 1;
$Interfaces::Interface::DATATYPE_DATETIME      = 2;
$Interfaces::Interface::DATATYPE_NUMERIC       = 16;
$Interfaces::Interface::DATATYPE_FLOATINGPOINT = 17;
$Interfaces::Interface::DATATYPE_FIXEDPOINT    = 18;
$Interfaces::Interface::OVERFLOW_METHOD_ERROR  = 0;
$Interfaces::Interface::OVERFLOW_METHOD_TRUNC  = 1;
$Interfaces::Interface::OVERFLOW_METHOD_ROUND  = 2;

$Interfaces::Interface::DATATYPES = {
						   CHAR      => {type => $Interfaces::Interface::DATATYPE_TEXT, constraints => { length => { min => 0, }, }, },
						   VARCHAR   => {type => $Interfaces::Interface::DATATYPE_TEXT, constraints => { length => { min => 0, }, }, },
						   TEXT      => {type => $Interfaces::Interface::DATATYPE_TEXT},
						   DATE      => {type => $Interfaces::Interface::DATATYPE_TEXT},
						   TIME      => {type => $Interfaces::Interface::DATATYPE_TEXT},
						   DATETIME  => {type => $Interfaces::Interface::DATATYPE_TEXT},
						   TIMESTAMP => {type => $Interfaces::Interface::DATATYPE_TEXT},
						   BOOLEAN   => {type => $Interfaces::Interface::DATATYPE_NUMERIC,
							minmax => { min => { 1 => 0, 0 => 0 }, max => { 0 => 1, 1 => 1 }},
							},
						   TINYINT   => {
							type => $Interfaces::Interface::DATATYPE_NUMERIC, 
							minmax => { min => { 1 => -(2**7),  0 => 0 }, max => { 0 => 2**8 - 1,  1 => 2**7 - 1 }}, 
							constraints => { signed => { min => 0, max => 1, }, }, 
							},
						   SMALLINT  => {
							type => $Interfaces::Interface::DATATYPE_NUMERIC, 
							minmax => { min => {1 => -(2**15), 0 => 0}, max => {0 => 2**16 - 1, 1 => 2**15 - 1 }},
							constraints => { signed => { min => 0, max => 1, }, }, 
							},
						   MEDIUMINT => {
							type => $Interfaces::Interface::DATATYPE_NUMERIC, 
							minmax => {min => {1 => -(2**23), 0 => 0}, max => {0 => 2**24 - 1, 1 => 2**23 - 1}},
							constraints => { signed => { min => 0, max => 1, }, }, 
							},
						   INT       => {
							type => $Interfaces::Interface::DATATYPE_NUMERIC, 
							minmax => {min => {1 => -(2**31), 0 => 0}, max => {0 => 2**32 - 1, 1 => 2**31 - 1}},
							constraints => { signed => { min => 0, max => 1, }, }, 
							},
						   INTEGER   => {type => 
							$Interfaces::Interface::DATATYPE_NUMERIC, 
							minmax => {min => {1 => -(2**31), 0 => 0}, max => {0 => 2**32 - 1, 1 => 2**31 - 1}},
							constraints => { signed => { min => 0, max => 1, }, }, 
							},
						   BIGINT    => {type => 
							$Interfaces::Interface::DATATYPE_NUMERIC, 
							minmax => {min => {1 => -(2**63), 0 => 0}, max => {0 => 2**64 - 1, 1 => 2**63 - 1}},
							constraints => { signed => { min => 0, max => 1, }, }, 
							},
						   FLOAT     => {
							type => $Interfaces::Interface::DATATYPE_FLOATINGPOINT,
							minmax => {min => {1 => undef,    0 => 0}, max => {0 => undef,     1 => undef}},
							},
						   DOUBLE    => {
							type => $Interfaces::Interface::DATATYPE_FLOATINGPOINT,
							minmax => {min => {1 => undef,    0 => 0}, max => {0 => undef,     1 => undef}},
							},
						   NUMERIC   => {
							type => $Interfaces::Interface::DATATYPE_FIXEDPOINT, constraints => { length => { min => 1, max => 65, }, decimals => { min => 0, }, }, 
							},
						   DECIMAL   => {
							type => $Interfaces::Interface::DATATYPE_FIXEDPOINT, constraints => { length => { min => 1, max => 65, }, decimals => { min => 0, }, }, 
							}, 
						  };

# General info
has 'config'            => (is => 'rw', isa => 'HashRef[HashRef[HashRef[Maybe[Value]]]]', lazy_build => 1,);
has 'name'              => (is => 'rw', isa => 'Maybe[Str]',                              lazy_build => 1,);
has 'decimalseparator'  => (is => 'rw', isa => 'Str',                                     lazy_build => 1,);
has 'thousandseparator' => (is => 'rw', isa => 'Str',                                     lazy_build => 1,);
has 'speedy'			=> (is => 'rw', isa => 'Bool',										lazy_build => 1,); # Whether or not to do safety checks. This is the "I know what I'm doing, just make it go fast"-option.
# Fields info
has 'columns'      => (is => 'rw', isa => 'ArrayRef[Str]',                  lazy_build => 1,);
has 'displayname'  => (is => 'rw', isa => 'ArrayRef[Str]',                  lazy_build => 1,);
has 'datatype'     => (is => 'rw', isa => 'ArrayRef[Str]',                  lazy_build => 1,);
has 'length'       => (is => 'rw', isa => 'ArrayRef[Maybe[Int]]',           lazy_build => 1,);
has 'decimals'     => (is => 'rw', isa => 'ArrayRef[Maybe[Int]]',           lazy_build => 1,);
has 'signed'       => (is => 'rw', isa => 'ArrayRef[Maybe[Bool]]',          lazy_build => 1,);
has 'allownull'    => (is => 'rw', isa => 'ArrayRef[Bool]',                 lazy_build => 1,);
has 'default'      => (is => 'rw', isa => 'ArrayRef[Maybe[Value]]',         lazy_build => 1, trigger => \&_default_set);
has 'fieldid'      => (is => 'rw', isa => 'ArrayRef[Int]',                  lazy_build => 1,);
has 'min_value'    => (is => 'rw', isa => 'Int',                            lazy_build => 1,);
has 'max_value'    => (is => 'rw', isa => 'Int',                            lazy_build => 1,);
has 'internal_datatype' => (is => 'rw', isa => 'ArrayRef[Int]', lazy_build => 1,);
has 'overflow_method'	=> (is => 'rw', isa => 'Int', lazy_build => 1,);
has 'read_defaultvalues'	=> (is => 'rw', isa => 'Bool', lazy_build => 1,);
has 'write_defaultvalues'	=> (is => 'rw', isa => 'Bool', lazy_build => 1,);

sub BUILD {
	my $self    = shift;
	my $hr_args = shift;
	# Load configuration from given $dbh for interface with $name
	if (exists $hr_args->{dbh} and defined $hr_args->{dbh} and exists $hr_args->{name}) {
		# Multiple interfaces can be set up using a single definition. This is done using aliases.
		my $hr_aliases = $hr_args->{dbh}->selectall_hashref("SELECT * FROM datarepos_alias", "tablename")
		  or Crash('Interface: Error fetching table aliases from repository: ' . $hr_args->{dbh}->errstr);
		my $repository_tablename = $hr_aliases->{$hr_args->{name}}->{use_tablename} // $hr_args->{name};
		# Fields
		$self->{config}->{Fields} = $hr_args->{dbh}->selectall_hashref('SELECT * FROM datarepository WHERE tablename=? ORDER BY fieldid', 'fieldname', undef, $repository_tablename)
		  or Crash('Interface: Error loading field information from repository: ' . $hr_args->{dbh}->errstr);
		# Indices
		$self->{config}->{Indices} = $hr_args->{dbh}->selectall_hashref('SELECT * FROM datareposidx WHERE tablename=?', 'keyname', undef, $repository_tablename)
		  or Crash('Interface: Error loading indices information from repository: ' . $hr_args->{dbh}->errstr);
		foreach my $fieldname (keys (%{$self->{config}->{Fields}})) {
			$self->{config}->{Fields}->{$fieldname}->{signed}    = $self->{config}->{Fields}->{$fieldname}->{signed}    eq 'Y' ? 1 : 0;
			$self->{config}->{Fields}->{$fieldname}->{allownull} = $self->{config}->{Fields}->{$fieldname}->{allownull} eq 'Y' ? 1 : 0;
		}
		    # Apply retrieved configuration
		$self->ReConfigureFromHash($self->config);
	} ## end if (exists $hr_args->{...})
	# Initialize non-undef default values for attributes
	$self->decimalseparator('.');
	$self->read_defaultvalues(0);
	$self->write_defaultvalues(1);
	$self->overflow_method($Interfaces::Interface::OVERFLOW_METHOD_ROUND);
} ## end sub BUILD

method Check() {
	# Check if all configuration data is valid (for Interface only)
	if (!$self->has_config) { return; }
	if (defined $Interfaces::Interface::DEBUGMODE) {
		print ("Checking...");
		if ($self->has_name) {
			print ($self->name);
		}
		print ("\n");
	} ## end if (defined $Interfaces::Interface::DEBUGMODE)
	my $meta = $self->meta;
	  # Check if all arrayref attributes contain the same amount of elements, use columns as leading
	  my $num_arrayref_elements = $#{$self->columns};
	  print ("Checking if all arrayref attributes contain the same amount of elements...") if defined $Interfaces::Interface::DEBUGMODE;
	foreach my $attribute ($meta->get_all_attributes) {
		my $attributename = $attribute->name;
		if ($attribute->{lazy_build} == 0) { next; }    # Skip attributes die zonder lazy_build zijn gedefinieerd.
		if ($attribute->type_constraint->name =~ /^ArrayRef/) {
			if ($num_arrayref_elements != $#{$self->$attributename}) {
				Crash(  "Attribute ["
					  . $attributename
					  . "] does not have the same amount of elements as there are columns ["
					  . $#{$self->$attributename}
					  . "] vs [$num_arrayref_elements]");
			} ## end if ($num_arrayref_elements...)
		} ## end if ($attribute->type_constraint...)
	} ## end foreach my $attribute ($meta...)
	print ("[OK]\n") if defined $Interfaces::Interface::DEBUGMODE;
	# Check if all fields are accounted for ($self->fieldid is continuous)
	# $self->fieldid->[0] = 1, $self->fieldid->[n] = $self->fieldid->[n-1] + 1
	print ("Checking if all fields are accounted for...") if defined $Interfaces::Interface::DEBUGMODE;
	if ($self->fieldid->[0] != 1) {
		Crash("Column [" . $self->columns->[0] . "] has fieldid [" . $self->fieldid->[0] . "], expected [1]. FieldIDs not continous");
	}
	foreach (1 .. $num_arrayref_elements) {
		if ($self->fieldid->[$_] != $self->fieldid->[$_ - 1] + 1) {
			Crash("Column [" . $self->columns->[$_] . "] has fieldid [" . $self->fieldid->[$_] . "], expected [" . $_ + 1 . "]. FieldIDs not continous");
		}
	}
	print ("[OK]\n") if defined $Interfaces::Interface::DEBUGMODE;
	# Check if all columns of type CHAR|VARCHAR|TEXT have a length
	# Check if all columns of type NUMERIC|DECIMAL have defined decimals (0 is allowed)
	# Check if all columns of type TINYINT|SMALLINT|MEDIUMINT|INT|BIGINT|INTEGER have defined signed
	print ("Checking if all columns have their required attributes") if defined $Interfaces::Interface::DEBUGMODE;
	foreach my $index (0 .. $num_arrayref_elements) {
		my $datatype = $self->datatype->[$index];
		foreach my $constraint ( keys %{$Interfaces::Interface::DATATYPES->{$datatype}->{constraints}}) {
			if (!defined $self->{$constraint}->[$index]) {
				Crash('Constraint violation: Column [' . $self->columns->[$index] . "] has datatype [$datatype] but $constraint is not defined");
			}
			my ($min, $max) = ($Interfaces::Interface::DATATYPES->{$datatype}->{constraints}->{$constraint}->{min}, $Interfaces::Interface::DATATYPES->{$datatype}->{constraints}->{$constraint}->{max});
			if (defined $min && $self->{$constraint}->[$index] < $min) {
				Crash('Constraint violation: Column [' . $self->columns->[$index] . "] has datatype [$datatype] but $constraint is below the minimum value [$min]");
			}
			if (defined $max && $self->{$constraint}->[$index] > $max) {
				Crash('Constraint violation: Column [' . $self->columns->[$index] . "] has datatype [$datatype] but $constraint is above the maximum value [$max]");
			}
		}
	}
	print ("[OK]\n")                                                    if defined $Interfaces::Interface::DEBUGMODE;
	print ("Checking if numeric-typed columns have numeric defaults: ") if defined $Interfaces::Interface::DEBUGMODE;
	foreach (0 .. $num_arrayref_elements) {
		# But only if allownull = false
		if (   defined $self->default->[$_]
			&& $self->{internal_datatype}->[$_] >= $Interfaces::Interface::DATATYPE_NUMERIC
			&& !($self->default->[$_] eq '0' || $self->default->[$_] > 0))
		{
			Crash("Column [" . $self->columns->[$_] . "] has datatype [" . $self->datatype->[$_] . "] but non-numeric default [" . $self->default->[$_] . "]");
		} ## end if (defined $self->default...)
	} ## end foreach (0 .. $num_arrayref_elements)
	print ("[Done]\n") if defined $Interfaces::Interface::DEBUGMODE;
	1;
}    ## end sub Check

method ClearConfig() {
	my $meta = $self->meta;
	  # Clear ArrayRef-type attributes (this clears ALL attributes...including those generated by roles)
	  foreach ($meta->get_all_attributes) {
		if ($_->type_constraint->name =~ /^ArrayRef/) {
			$_->clear_value($self);
		}
	}
}

method ReConfigureFromHash(HashRef $hr_config !) {
	my $meta = $self->meta;
	# Clear ArrayRef-type attributes (this clears ALL attributes...including those generated by roles)
	$self->ClearConfig();
	if (!defined $hr_config && $self->has_config) {
		Crash("Trying to reconfigure Base with empty configdata");
	}
	# Reconfigure
	$self->config($hr_config);
	  my @keys = keys (%{$hr_config->{Fields}});
	  if (!@keys) {
		Crash("Empty config supplied");
	}
	# Set the columns
	my $ar_Columns;
	  foreach my $Column (@keys) {
		$ar_Columns->[$hr_config->{Fields}->{$Column}->{fieldid} - 1] = $Column;    # fieldid starts at 1
	}
	$self->columns($ar_Columns);
	  # Set all other attributes
	  foreach my $ColumnIndex (0 .. $#{$self->columns}) {
		my $Column = $self->columns->[$ColumnIndex];
		if (!defined $Column) {
			Crash("Undefined columnname with fieldid [" . ($ColumnIndex + 1) . "]");
		}
		foreach ($meta->get_all_attributes) {
			my $attributename = $_->name;
			if ($_->{lazy_build} == 0) { next; }                                    # Skip attributes die zonder lazy_build zijn gedefinieerd.
			if ($attributename eq "columns") { next; }                              # Skip columns-attribute. We already did that one.
			if ($_->type_constraint->name =~ /^ArrayRef/) {
				push (@{$self->$attributename}, $hr_config->{Fields}->{$Column}->{$attributename});
			}
		} ## end foreach ($meta->get_all_attributes)
		# Init datatypes for speed (saves having to do regexes for each Read call)
		my $hr_datatype = $Interfaces::Interface::DATATYPES->{$self->datatype->[$ColumnIndex]};
		$self->{internal_datatype}->[$ColumnIndex] = $Interfaces::Interface::DATATYPES->{$self->datatype->[$ColumnIndex]}->{type} or Interfaces::Interface::Crash("Datatype [$self->datatype->[$ColumnIndex]] unknown");
		# Add minmax
		if ($self->{internal_datatype}->[$ColumnIndex] >= $Interfaces::Interface::DATATYPE_NUMERIC) {
			if ($self->{internal_datatype}->[$ColumnIndex] == $Interfaces::Interface::DATATYPE_FIXEDPOINT) {
				my ($length,$decimals) = ($self->{length}->[$ColumnIndex] // 10, $self->{decimals}->[$ColumnIndex] // 0);
				$self->{max_value}->[$ColumnIndex] = (10**($length + 1) - 1) / 10**$decimals;
				$self->{min_value}->[$ColumnIndex] = -$self->{max_value}->[$ColumnIndex];
			} else {
				$self->{min_value}->[$ColumnIndex] = $hr_datatype->{min_value}->{$self->{signed}->[$ColumnIndex]};
				$self->{max_value}->[$ColumnIndex] = $hr_datatype->{max_value}->{$self->{signed}->[$ColumnIndex]};
			}
		} 
	} ## end foreach my $ColumnIndex (0 ...)
	1;
}    ## end sub ReConfigureFromHash

method AddField(HashRef $hr_config !) {
	Data::Dump::dd($hr_config) if $Interfaces::Interface::DEBUGMODE;
	# Pre-add check
	$hr_config->{fieldid} = ($self->fieldid->[-1] // 0) + 1;
	my $hr_datatype = $Interfaces::Interface::DATATYPES->{$hr_config->{datatype}};
	Interfaces::Interface::Crash("Datatype [$hr_config->{datatype}] unknown") if !defined $hr_datatype->{type};
	$hr_config->{internal_datatype} = $hr_datatype->{type};
	# Check if column of type CHAR|VARCHAR|TEXT have a length
	# Check if column of type NUMERIC|DECIMAL have defined decimals (0 is allowed)
	# Check if column of type TINYINT|SMALLINT|MEDIUMINT|INT|BIGINT|INTEGER have defined signed
	given ($hr_datatype->{type}) {
		when ($Interfaces::Interface::DATATYPE_TEXT) {
			if (($hr_config->{length} // 0) <= 0) {
				Crash("Column [" . $hr_config->{fieldname} . "] has datatype [" . $hr_config->{datatype} . "] but length [" . $hr_config->{length} . "]");
			}
		}
		when ($_ > $Interfaces::Interface::DATATYPE_NUMERIC) {
			if (!defined $hr_config->{decimals} || (($hr_config->{length} // 0) <= 0)) {
				Crash(  "Column ["
					  . $hr_config->{fieldname}
					  . "] has datatype ["
					  . $hr_config->{datatype}
					  . "] but decimals,length has not been defined properly ["
					  . $hr_config->{decimals} . ','
					  . $hr_config->{length}
					  . ']');
			} ## end if (!defined $hr_config...)
		} ## end when (/^(DECIMAL|FLOAT|DOUBLE)$/)
		when ($Interfaces::Interface::DATATYPE_NUMERIC) {
			if (!defined $hr_config->{signed}) {
				Crash("Column [" . $hr_config->{fieldname} . "] has datatype [" . $hr_config->{datatype} . "] but signed has not been defined");
			}
		}
	} ## end given
	# Check if datatype is numeric but the default exists and is not numeric
	if (defined $hr_config->{default} && $hr_config->{internal_datatype} >= $Interfaces::Interface::DATATYPE_NUMERIC) {
		if (!($hr_config->{default} eq '0' || $hr_config->{default} > 0)) {
			Crash("Column [" . $hr_config->{fieldname} . "] has datatype [" . $hr_config->{datatype} . "] but non-numeric default [" . $hr_config->{default} . "]");
		} else {
			# Check if numerical defaults fall within minmax range
			if ($hr_config->{default} != $self->minmax_manual($hr_datatype, $self->{overflow_method} // $Interfaces::Interface::OVERFLOW_METHOD_ERROR, $hr_config->{default}, $hr_config->{signed}, $hr_config->{length}, $hr_config->{decimals}, $self->{decimalseparator} // '.')) {
				Crash('Column [' . $hr_config->{fieldname} . '] has default [' . $hr_config->{default} . '] but default lies outside constrained values.');
			}
		}
	}
	
	# All ok, proceed with adding the field to the interface
	# Generate field_id based on last used fieldid
	$hr_config->{fieldid} = ($self->fieldid->[-1] // 0) + 1;
	  push (@{$self->columns}, $hr_config->{fieldname});
	  my $meta = $self->meta;
	  foreach ($meta->get_all_attributes) {
		my $attributename = $_->name;
		if ($_->{lazy_build} == 0) { next; }    # Skip attributes die zonder lazy_build zijn gedefinieerd.
		if ($attributename eq "columns") { next; }    # Skip columns-attribute. We already did that one.
		if ($_->type_constraint->name =~ /^ArrayRef/) {
			push (@{$self->$attributename}, $hr_config->{$attributename});
		}
	} ## end foreach ($meta->get_all_attributes)
	$self->{config} //= {Fields => {}};
	#Data::Dump::dd($hr_config);
	#$self->{config}->{Fields}->{$attributename} = $hr_config;
}

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
}    ## end sub MakeNewConfig ($)

# Reduces length of $value until it fits $length,decimals, truncates from left to right (so only gets the LSB)
method fix_runlength(Int $fieldid !, $value !) {
	my ($internal_datatype, $signed, $length, $decimals) = ($self->{internal_datatype}->[$fieldid], $self->{signed}->[$fieldid], $self->{length}->[$fieldid], $self->{decimals}->[$fieldid]);
	my $source_signed = $value < 0 ? 1 : 0;
	# Split the value in an integer and fractional part
	my $current_num_decimals = 0;
	if (index ($value, $self->decimalseparator) >= 0) {
		$current_num_decimals = length ($value) - index ($value, $self->decimalseparator) - $source_signed;
	}
	my ($fraction, $integer) = POSIX::modf($value);
	$fraction = sprintf ("%.0${current_num_decimals}f", $fraction);    # Fix floating point errors from POSIX::modf
	# Truncate
	$integer = reverse (substr (reverse ($integer), 0, List::Util::min($length - $decimals, length ($integer) - $source_signed))) if $integer;
	$fraction = substr ($fraction, $source_signed + 2, List::Util::min($decimals, $current_num_decimals)) if length ($fraction) > 2;
	$value = ($source_signed ? -1 : 1) * ($integer + "0.$fraction");
	# Add trailing significant decimals
	if ($decimals > 0) {
		$value =~ s/\.([0-9]*)/'.' . substr($1, 0, $decimals)/e;
	}
	return $value;
}

method fix_runlength_manual(HashRef $hr_internal_datatype !, Int $overflow_method !, Num $value, Bool $signed ?, Int $length ?, Int $decimals ?, Str $decimalseparator ?) {
	my $source_signed = $value < 0 ? 1 : 0;
	# Split the value in an integer and fractional part
	my $current_num_decimals = 0;
	if (index ($value, $decimalseparator) >= 0) {
		$current_num_decimals = length ($value) - index ($value, $decimalseparator) - $source_signed;
	}
	my ($fraction, $integer) = POSIX::modf($value);
	$fraction = sprintf ("%.0${current_num_decimals}f", $fraction);    # Fix floating point errors from POSIX::modf
	# Truncate
	$integer = reverse (substr (reverse ($integer), 0, List::Util::min($length - $decimals, length ($integer) - $source_signed))) if $integer;
	$fraction = substr ($fraction, $source_signed + 2, List::Util::min($decimals, $current_num_decimals)) if length ($fraction) > 2;
	$value = ($source_signed ? -1 : 1) * ($integer + "0.$fraction");
	# Add trailing significant decimals
	if ($decimals > 0) {
		$value =~ s/\.([0-9]*)/'.' . substr($1, 0, $decimals)/e;
	}
	return $value;
}

method fix_typesize(Int $fieldid !, $value !) {
	my ($internal_datatype, $signed, $length, $decimals) = ($Interfaces::Interface::DATATYPES->{$self->{datatype}->[$fieldid]}, $self->{signed}->[$fieldid], $self->{length}->[$fieldid], $self->{decimals}->[$fieldid] // 0);
	my ($minvalue, $maxvalue);
	my ($minvalue_round, $maxvalue_round);
	if (defined $length and defined $decimals) {
		($minvalue_round, $maxvalue_round) = (-(10**($length - $decimals)) + (10**(-$decimals)), (10**($length - $decimals)) - (10**(-$decimals)));
	}
	# Translate signed = 'Y'/'N' to 1/0
	$signed = $signed eq 'Y' ? 1 : 0 if $signed ~~ ['Y','N'];
	if ($internal_datatype->{type} == $Interfaces::Interface::DATATYPE_NUMERIC) {
		if ($signed) {
			$minvalue = $internal_datatype->{minmax}->{min}->{$signed};
			$maxvalue = -$minvalue - 1;
		} else {
			$minvalue = 0;
			$maxvalue = $internal_datatype->{minmax}->{max}->{$signed};
		}
		if (defined $minvalue_round and defined $maxvalue_round) {
			# If the minimum or maximum value doesn't fit in $length, get the largest number that does fit in $length
			if ($minvalue < $minvalue_round) { $minvalue = $minvalue_round; }
			if ($maxvalue > $maxvalue_round) { $maxvalue = $maxvalue_round; }
		}
	} elsif ($internal_datatype->{type} > $Interfaces::Interface::DATATYPE_NUMERIC) {
		$maxvalue = $maxvalue_round;
		if ($signed) {
			$minvalue = $minvalue_round;
		} else {
			$minvalue = 0;
		}
	} ## end elsif ($internal_datatype...)
	#print("Min [$minvalue] max [$maxvalue]\n");
	if    (defined $minvalue and $value < $minvalue) { $value = $minvalue; }
	elsif (defined $maxvalue and $value > $maxvalue) { $value = $maxvalue; }
	return $value;
}

method fix_typesize_manual(HashRef $hr_internal_datatype !, Int $overflow_method !, Num $value, Bool $signed ?, Int $length ?, Int $decimals ?, Str $decimalseparator ?) {
	my ($minvalue, $maxvalue);
	my ($minvalue_round, $maxvalue_round);
	if (defined $length and defined $decimals) {
		($minvalue_round, $maxvalue_round) = (-(10**($length - $decimals)) + (10**(-$decimals)), (10**($length - $decimals)) - (10**(-$decimals)));
	}
	# Translate signed = 'Y'/'N' to 1/0
	$signed = $signed eq 'Y' ? 1 : 0 if $signed ~~ ['Y','N'];
	if ($hr_internal_datatype->{type} == $Interfaces::Interface::DATATYPE_NUMERIC) {
		if ($signed) {
			$minvalue = $hr_internal_datatype->{minmax}->{min}->{$signed};
			$maxvalue = -$minvalue - 1;
		} else {
			$minvalue = 0;
			$maxvalue = $hr_internal_datatype->{minmax}->{max}->{$signed};
		}
		if (defined $minvalue_round and defined $maxvalue_round) {
			# If the minimum or maximum value doesn't fit in $length, get the largest number that does fit in $length
			if ($minvalue < $minvalue_round) { $minvalue = $minvalue_round; }
			if ($maxvalue > $maxvalue_round) { $maxvalue = $maxvalue_round; }
		}
	} elsif ($hr_internal_datatype->{type} > $Interfaces::Interface::DATATYPE_NUMERIC) {
		$maxvalue = $maxvalue_round;
		if ($signed) {
			$minvalue = $minvalue_round;
		} else {
			$minvalue = 0;
		}
	} ## end elsif ($internal_datatype...)
	#print("Min [$minvalue] max [$maxvalue]\n");
	if    ($value < $minvalue) { $value = $minvalue; }
	elsif ($value > $maxvalue) { $value = $maxvalue; }
	return $value;
}

method minmax(Int $fieldid !, $value !) {
	# For OVERFLOW_METHOD_ROUND, read the value as-is, then round to within respectively $datatype_size and $length,decimals
	# For OVERFLOW_METHOD_TRUNC, read the value as-is, then truncate the value within respectively $length,decimals and $datatype_size
	my ($internal_datatype, $signed, $length, $decimals) = ($self->{internal_datatype}->[$fieldid], $self->{signed}->[$fieldid], $self->{length}->[$fieldid], $self->{decimals}->[$fieldid] // 0);
	if ($internal_datatype < $Interfaces::Interface::DATATYPE_NUMERIC) { return $value; }
	if ($internal_datatype == $Interfaces::Interface::DATATYPE_NUMERIC) {
		# Translate signed = 'Y'/'N' to 1/0
		if (!defined $signed) { Crash("Not signed?!"); }
		$signed = $signed eq 'Y' ? 1 : 0;
	}
	if ($self->{overflow_method} == $Interfaces::Interface::OVERFLOW_METHOD_ERROR) {
		if ($signed and $value < 0) { Crash('Value [' . $value . '] below minimum [0]'); }
		my $copy_of_value = $value;
		$copy_of_value =~ s/$self->{decimalseparator}//;
		if (length ($copy_of_value) > $length) { Crash('value [' . $value . '] too large to fit in [' . $length . '] figures'); }
	} elsif ($self->{overflow_method} == $Interfaces::Interface::OVERFLOW_METHOD_TRUNC) {
		if (!$decimals) {
			# Truncate to no decimals
			$value = int ($value);
		} elsif ($decimals == $length) {
			# Special case, truncate to only decimals
			$value = POSIX::fmod($value, 1);
		}
		$value = $self->fix_runlength($fieldid, $value);
		$value = $self->fix_typesize($fieldid, $value);
	} elsif ($self->{overflow_method} == $Interfaces::Interface::OVERFLOW_METHOD_ROUND) {
		# First round to proper amount of decimals
		$value = sprintf ("%.${decimals}f", $value);
		$value = $self->fix_typesize($fieldid, $value);
	} else {
		Crash("Unknown overflow method selected [" . $self->{overflow_method});
	}
	return $value;
}

method minmax_manual(HashRef $hr_internal_datatype !, Int $overflow_method !, Num $value, Bool $signed ?, Int $length ?, Int $decimals ?, Str $decimalseparator ?) {
	# Version that doesn't rely on a configured interface (called from $self->AddField for runtime checks)
	# For OVERFLOW_METHOD_ROUND, read the value as-is, then round to within respectively $datatype_size and $length,decimals
	# For OVERFLOW_METHOD_TRUNC, read the value as-is, then truncate the value within respectively $length,decimals and $datatype_size
	if ($hr_internal_datatype->{type} == $Interfaces::Interface::DATATYPE_NUMERIC) {
		if (!defined $signed) { Crash("Not signed?!"); }
	}
	if ($overflow_method == $Interfaces::Interface::OVERFLOW_METHOD_ERROR) {
		if ($signed and $value < 0) { Crash('Value [' . $value . '] below minimum [0]'); }
		my $copy_of_value = $value;
		$copy_of_value =~ s/\Q$decimalseparator\E//;
		if (length ($copy_of_value) > $length) { Crash('value [' . $value . '] too large to fit in [' . $length . '] figures'); }
	} elsif ($overflow_method == $Interfaces::Interface::OVERFLOW_METHOD_TRUNC) {
		if (!$decimals) {
			# Truncate to no decimals
			$value = int ($value);
		} elsif ($decimals == $length) {
			# Special case, truncate to only decimals
			$value = POSIX::fmod($value, 1);
		}
		$value = $self->fix_runlength_manual($hr_internal_datatype, $value, $signed, $length, $decimals, $decimalseparator);
		$value = $self->fix_typesize_manual($hr_internal_datatype, $value, $signed, $length, $decimals, $decimalseparator);
	} elsif ($overflow_method == $Interfaces::Interface::OVERFLOW_METHOD_ROUND) {
		# First round to proper amount of decimals
		$value = sprintf ("%.${decimals}f", $value);
		$value = $self->fix_typesize($hr_internal_datatype, $value, $signed, $length, $decimals, $decimalseparator);
	} else {
		Crash("Unknown overflow method selected [" . $overflow_method);
	}
	return $value;
}

method tablename(Str $newvalue) {
	$newvalue ? $self->name($newvalue) : $self->name();
}

method Crash() {
	defined $Interfaces::Interface::DEBUGMODE ? Carp::confess(@_) : die (@_);
}

sub DESTROY {
	my $self = shift;
	#	Carp::carp("Destroying interface for [" . $self->tablename . "]\n");
}

with
  'Interfaces::FlatFile' => {
	alias => {ReadRecord => 'FlatFile_ReadRecord', WriteRecord => 'FlatFile_WriteRecord', ReadData => 'FlatFile_ReadData', WriteData => 'FlatFile_WriteData',},
	excludes => ['ReadRecord', 'WriteRecord', 'ReadData', 'WriteData',],
							},
  'Interfaces::DelimitedFile' => {
								  alias => {
											ReadRecord         => 'DelimitedFile_ReadRecord',
											WriteRecord        => 'DelimitedFile_WriteRecord',
											ReadData           => 'DelimitedFile_ReadData',
											WriteData          => 'DelimitedFile_WriteData',
											ConfigureUseInFile => 'DelimitedFile_ConfigureUseInFile',
										   },
								  excludes => ['ReadRecord', 'WriteRecord', 'ReadData', 'WriteData', 'ConfigureUseInFile',],
								 },
  'Interfaces::DataTable'   => {alias => {ReadData => 'DataTable_ReadData', WriteData => 'DataTable_WriteData',}, excludes => ['ReadData', 'WriteData',],},
  'Interfaces::ExcelBinary' => {
								alias => {
										  ReadRecord         => 'ExcelBinary_ReadRecord',
										  WriteRecord        => 'ExcelBinary_WriteRecord',
										  ReadData           => 'ExcelBinary_ReadData',
										  WriteData          => 'ExcelBinary_WriteData',
										  ConfigureUseInFile => 'ExcelBinary_ConfigureUseInFile',
										  WriteHeaders       => 'ExcelBinary_WriteHeaders',
										 },
								excludes => ['ReadRecord', 'WriteRecord', 'ReadData', 'WriteData', 'ConfigureUseInFile', 'WriteHeaders',],
							   },
  'Interfaces::ExcelX' => {
						   alias => {
									 ReadRecord         => 'ExcelX_ReadRecord',
									 WriteRecord        => 'ExcelX_WriteRecord',
									 ReadData           => 'ExcelX_ReadData',
									 WriteData          => 'ExcelX_WriteData',
									 ConfigureUseInFile => 'ExcelX_ConfigureUseInFile',
									 WriteHeaders       => 'ExcelX_WriteHeaders',
									},
						   excludes => ['ReadRecord', 'WriteRecord', 'ReadData', 'WriteData', 'ConfigureUseInFile', 'WriteHeaders',],
						  },
  'Interfaces::XMLFile' => {
							alias => {
									  ReadRecord                => 'XMLFile_ReadRecord',
									  WriteRecord               => 'XMLFile_WriteRecord',
									  ReadData                  => 'XMLFile_ReadData',
									  WriteData                 => 'XMLFile_WriteData',
									  ConfigureUseInFile        => 'XMLFile_ConfigureUseInFile',
									  ConfigureUseInFile_Manual => 'XMLFile_ConfigureUseInFile_Manual',
									 },
							excludes => ['ReadRecord', 'WriteRecord', 'ReadData', 'WriteData', 'ConfigureUseInFile', 'ConfigureUseInFile_Manual',],
						   },
  'Interfaces::JSON' => {
							alias => {
									  ReadRecord                => 'JSON_ReadRecord',
									  WriteRecord               => 'JSON_WriteRecord',
									  ReadData                  => 'JSON_ReadData',
									  WriteData                 => 'JSON_WriteData',
									  ConfigureUseInFile        => 'JSON_ConfigureUseInFile',
									 },
							excludes => ['ReadRecord', 'WriteRecord', 'ReadData', 'WriteData', ],
						   };
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
				else                                                         { return; }
			};
		} ## end if (!defined *{__PACKAGE__...})
	} ## end foreach my $build_attribute...
	use strict;
}

1;

=head1 NAME

Interfaces::Interface - Generic data-interface between file-formats and databases

=head1 VERSION

This document refers to Interfaces::Interface version 2.0.0

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

=item * Interfaces::ExcelBinary

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
checks pertaining the integrity of the configuration are not met. The supplied $hr_config will be
saved in $self->config. $hr_config has the following structure:
	{ Fields => {
		$fieldname => { 
			displayname => $displayname,
			datatype => $datatype,
			length => $length,
			decimals => $decimals,
			signed => $signed,
			allownull => $allownull,
			default => $defaultvalue,
			fieldid => $fieldid,
			... (other attributes introduced by additional roles)
		} 
	}, Indices => {
		keyname1 => 'keyfield1,keyfield2, keyfield3 , keyfield4',
		keyname2 => 'keyfield2',
		...
	}
The Indices-part is only required for interfacing with databases (or other future interfaces which
would want to use indices this way). The keyfields are input as a commaseparated string. When this
string is parsed, each fieldname is trimmed to remove leading and trailing whitespace.

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
