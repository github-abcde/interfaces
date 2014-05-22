package Interfaces2::DataTable;
# Version 0.2	28-09-2011
# Copyright (C) OGD 2011

#use Devel::Size;
use Moose::Role;
use v5.10;
use Devel::Peek;

BEGIN {
	@Interfaces2::DataTable::methods = qw();
}

has 'indices'       => (is => 'rw', isa => 'Maybe[HashRef[ArrayRef[Str]]]', lazy_build => 1,);
has 'useintable'    => (is => 'rw', isa => 'ArrayRef[Bool]',                lazy_build => 1,);
#has 'autoincrement' => (is => 'rw', isa => 'ArrayRef[Bool]',                lazy_build => 1,);

# Scan for roles
BEGIN {
	no strict;
	my ($package_fqpn, $package_this, $package_aspath) = (__PACKAGE__)x3;
	$package_aspath =~ s'::'/'g;
	$package_this =~ s/^.*::([^:]*)$/$1/;
	my (undef, $include_dir, $package_pm) = File::Spec->splitpath($INC{$package_aspath . '.pm'});
	my @subroles;
	if (-d $include_dir . $package_this ) {
		@subroles = (); #File::Find::Rule->file()->maxdepth(1)->name('*.pm')->relative->in($include_dir . $package_this);
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

after 'Check' => sub {
	my $self = shift;
	print ("Checking DataTable constraints...");
	# Check tablename
	if (!$self->has_name) {
		Carp::confess "Interface does not have a (table)name defined";
	}
	# Check if all the fields referenced in the indices (if any) actually exist
	my $hr_failures;
	if ($self->has_indices and defined $self->indices) {
		for my $keyname (keys (%{$self->indices})) {
			foreach my $keycolumn (@{$self->indices->{$keyname}}) {
				if (!grep { $_ eq $keycolumn } @{$self->columns}) {
					push (@{$hr_failures->{$keyname}}, $keycolumn);
				}
			}
		} ## end for my $keyname (keys (...))
		if (scalar keys (%{$hr_failures})) {
			Data::Dump::dd($hr_failures);
			Carp::confess("Interface [" . $self->name . "] has indices defined on columns (shown above) that don't exist");
		}
	} ## end if ($self->has_indices...)
	print ("[OK]\n");
};

after 'ReConfigureFromHash' => sub {
	my ($self, $hr_config) = @_;
	my @keys = keys (%{$hr_config->{Fields}});
	# Set tablename
	$self->name($hr_config->{Fields}->{$keys[0]}->{tablename});
	# Set indices
	my $hr_indices;
	foreach my $keyname (keys (%{$hr_config->{Indices}})) {
		$hr_indices->{$keyname} = [split (',', $hr_config->{Indices}->{$keyname}->{keyfields})];
	}
	if (defined $hr_indices) { $self->indices($hr_indices); }
};

1;    # so the require or use succeeds
