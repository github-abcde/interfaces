package Interfaces::DataTable::SQLServer;
# Version 0.2	28-09-2011
# Copyright (C) OGD 2011

#use Devel::Size;
use Moose::Role;
use 5.010;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater
use Devel::Peek;
use MooseX::Method::Signatures;

BEGIN {
	@Interfaces::DataTable::SQLServer::methods = qw(ReadData WriteData ReConfigureFromDatabase CreateInsertQuery CreateSelectQuery CreateUpdateQuery CreateTable);
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

use strict;

#requires qw(columns displayname datatype length decimals signed allownull default fieldid indices useintable autoincrement);

# ReConfigureFromDatabase configures self using a specified table in a specified databasehandle.
# Configures self for datatable-interfacing only, all values pertaining to other interfaces are left undefined
method ReConfigureFromDatabase ($dbh !, Str $tablename !) {
	if (!defined $dbh) {
		Carp::confess "Supplied databasehandle is undefined";
	}
	my $meta = $self->meta;
	# Clear attributes
	foreach ($meta->get_attribute_list) { eval "$self->clear_" . "$_"; }
	# Get columns-list from database
	my $ar_ColumnInfo = $dbh->selectall_arrayref("
		SELECT 
			*, 
			columnproperty(object_id(TABLE_NAME), column_name,'IsIdentity') AS [Identity] 
		FROM INFORMATION_SCHEMA.COLUMNS 
		WHERE TABLE_NAME = ?", {Slice => {}}, $tablename)
	  or Carp::confess("Error getting column-info for [$tablename]: " . $dbh->errstr);
	if (!@{$ar_ColumnInfo}) { return; }    # No query results -> nothing to do
	my $ar_IndexInfo = $dbh->selectall_arrayref("
		SELECT CONSTRAINT_TYPE, COLUMN_NAME, ORDINAL_POSITION
		FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
		JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ccu ON 
			tc.TABLE_CATALOG = ccu.TABLE_CATALOG AND 
			tc.TABLE_SCHEMA = ccu.TABLE_SCHEMA AND
			tc.CONSTRAINT_NAME = ccu.CONSTRAINT_NAME
		WHERE tc.TABLE_NAME = ?
		ORDER BY ORDINAL_POSITION
	", {Slice => {}}, $tablename)
	  or Carp::confess("Error getting index-info for [$tablename]: " . $dbh->errstr);
	# Start setting attributes
	# Interface.pm supplies these column-attributes:
	# columns, datatype, length, decimals, signed, allownull, default, fieldid
	#		if ($_->type_constraint->name =~ /^ArrayRef/) {
	#			push (@{$self->$attributename}, $hr_config->{$Column}->{$attributename});
	my $hr_indices;
	foreach my $fieldid (0 .. $#$ar_ColumnInfo) {
		my $column = $ar_ColumnInfo->[$fieldid];
		my $dbtype = uc $column->{DATA_TYPE};
		push (@{$self->{columns}},     $column->{COLUMN_NAME});
		push (@{$self->{displayname}}, $column->{COLUMN_NAME});
		push (@{$self->{datatype}},    $column->{DATA_TYPE});
		if ($dbtype =~ /REAL|FLOAT|DOUBLE|DECIMAL|NUMERIC|MONEY/) {
			push (@{$self->{decimals}}, $column->{NUMERIC_SCALE});
		} else {
			push (@{$self->{decimals}}, undef);
		}
		if ($dbtype =~ /(TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT|FLOAT|DOUBLE|REAL|DECIMAL|NUMERIC|NUMERIC)/) {
			push (@{$self->{length}}, $column->{NUMERIC_PRECISION});
			push (@{$self->{signed}}, "1");                            # SQL Server Integer types are always signed
		} elsif ($dbtype =~ /CHAR|VARCHAR|TEXT/) {
			push (@{$self->{length}}, $column->{CHARACTER_MAXIMUM_LENGTH});
			push (@{$self->{signed}}, undef);
		} else {
			push (@{$self->{signed}}, undef);
			push (@{$self->{length}}, undef);
		}
		push (@{$self->{allownull}}, ($column->{IS_NULLABLE} eq "YES") ? "1" : "0");
		push (@{$self->{default}}, map { s/[()]//g; $_; } $column->{COLUMN_DEFAULT}) if (defined $column->{COLUMN_DEFAULT});
		push (@{$self->{default}}, undef) if (!defined $column->{COLUMN_DEFAULT});
		push (@{$self->{fieldid}},       $fieldid + 1);                # FieldID is 1-based
		push (@{$self->{useintable}},    "Y");                         # Fields from a table are automatically used in a table :)
		push (@{$self->{autoincrement}}, $column->{Identity});
	} ## end foreach my $fieldid (0 .. $#$ar_ColumnInfo)
	foreach (@{$ar_IndexInfo}) {
		if ($_->{CONSTRAINT_TYPE} eq 'PRIMARY KEY') { $_->{CONSTRAINT_TYPE} = 'PRIMARY'; }
		push (@{$hr_indices->{$_->{CONSTRAINT_TYPE}}}, $_->{COLUMN_NAME});
	}
	foreach (keys (%{$hr_indices})) {
		$self->{indices}->{$_} = [@{$hr_indices->{$_}}];
	}
	$self->MakeNewConfig();
	$self->ReConfigureFromHash($self->config);
	$self->name($tablename);
} ## end sub ReConfigureFromDatabase ($$$)

# CreateInsertQuery Returns an SQL statement inserting fields @ with value ? into $self->{name}
# Arguments: self, $ar_fieldnames
method CreateInsertQuery (ArrayRef $ar_columns !) {
	if (!$self->has_name) {
		Carp::confess "Cannot create INSERT query for object without (table)name";
	}
	return "INSERT INTO " . $self->name . "(" . join (",", @{$ar_columns}) . ") VALUES (" . join (",", map ("?", @{$ar_columns})) . ") ";
} ## end sub CreateInsertQuery ($$)

# CreateUpdateQuery Returns an SQL statement updating table $self->{name} setting fields @ to ?
# Arguments: self, $ar_fieldnames
method CreateUpdateQuery (ArrayRef $ar_columns !) {
	return "UPDATE " . $self->{name} . " SET " . join (",", map ($_ . "=?", @{$ar_columns})) . " ";
}

# CreateSelectQuery Returns an SQL statement selecting fields @ from table $
# Arguments: TableName, @fieldnames, %modifications
# %modifications consists of key-value pairs as follows: "FieldName" => "FunctionName"
# This will change "FieldName" into "FunctionName(FieldName) AS FieldName"
method CreateSelectQuery (ArrayRef $ar_columns !, HashRef $hr_modifications !) {
	my @Columns          = map { $hr_modifications->{$_} ? "$hr_modifications->{$_} AS $_" : $_; } @{$ar_columns};
	return "SELECT " . join (",", @Columns) . " FROM " . $self->{name};
} ## end sub CreateSelectQuery ($$$)

# CreateTable ($language)
# Returns a string containing the CREATE TABLE statement for the given language
method CreateTable {
	my $returnstring = "CREATE TABLE ";
	my @columnnames;
	$returnstring .= "[" . $self->name . "] (\n";
	@columnnames = map { "[$_]"; } @{$self->columns};
	foreach (0 .. $#{$self->columns}) {
		$returnstring .= "  $columnnames[$_] " . $self->datatype->[$_];
		if ($self->datatype->[$_] =~ /^(NUMERIC|CHAR|VARCHAR|NVARCHAR)$/i) {
			$returnstring .= sprintf ("(%s", $self->length->[$_]);
			if (($self->decimals->[$_] // 0) > 0) {
				$returnstring .= sprintf (",%s", $self->{decimals}[$_]);
			}
			$returnstring .= ")";
		} 
		if ($self->allownull->[$_] != 0) {
			$returnstring .= " NULL";
		}
		if (defined $self->default->[$_]) {
			if ($self->datatype->[$_] =~ /(VARCHAR|CHAR|DATE|TIME|DATETIME)/i) {
				$returnstring .= sprintf (" DEFAULT '%s'", $self->default->[$_]);
			} else {
				$returnstring .= sprintf (" DEFAULT %s", $self->default->[$_]);
			}
		} ## end if (defined $self->default...)
		if ($self->autoincrement->[$_]) {
			$returnstring .= " IDENTITY(1,1)";
		}
		if ($_ < $#{$self->columns}) {
			$returnstring .= ",\n";
		}
	} ## end foreach (0 .. $#{$self->columns...})
	    # Index opbouwen
	if ($self->has_indices) {
		foreach (keys (%{$self->indices})) {
			if (/PRIMARY/) {
				$returnstring .= sprintf (",\n  $_ KEY CLUSTERED (%s) ", join (',', map { "[$_]"; } @{$self->indices->{$_}}));
			} else {
				$returnstring .= sprintf (",\n  KEY $_ (%s) ", $self->indices->{$_});
			}
		} ## end foreach (keys (%{$self->indices...}))
	} ## end if ($self->has_indices)
	$returnstring .= "\n)";
	return $returnstring;
} ## end sub CreateTable

# WriteData ($dbhandle, $ar_data, $hr_options)
# Options consist of:	Columns = [columns..]	# Insert only these columns
# Naturally, columns must have the useintable-attribute set to 'Y'
method WriteData ($dbh !, ArrayRef $ar_data !, HashRef $hr_options ?) {
	if (!defined $dbh) {
		Carp::carp("Database-handle is undefined");
		return undef;
	}
	if (!defined $ar_data) { return undef; }
	my $returnvalue = 0;
	my $ar_Insert_Columns =
	  (exists $hr_options->{Columns}) ? $hr_options->{Columns} : [ $self->columns ]
	  ;    #Make a shallow copy, otherwise splicing ignored columns tampers with the object's columns-attribute
	my $ar_Insert_Columns_Escaped;
	my @Ignore_Columns;
	foreach my $ColumnName (@{$ar_Insert_Columns}) {
		#		print("Processing [$ColumnName]\n");
		my $ColumnIndex = SleLib::IndexOf($ColumnName, @{$self->columns});
		if ($self->useintable->[$ColumnIndex] eq 'N') {
			Carp::carp("Specified column [$ColumnName] is has useintable=N, skipping");
			push (@Ignore_Columns, $ColumnIndex);    # Queue for deletion from $ar_Insert_Columns
		}
	} ## end foreach my $ColumnName (@{$ar_Insert_Columns...})
	foreach (0 .. $#Ignore_Columns) { splice (@{$ar_Insert_Columns}, $Ignore_Columns[$_] - $_, 1); }    # Delete from $ar_Insert_Columns
	my $Query_Insert;
	# Escape columnnames to allow columns named with reserved words
	@{$ar_Insert_Columns_Escaped} = map {"`$_`"} @{$ar_Insert_Columns};
	$Query_Insert = $self->CreateInsertQuery($ar_Insert_Columns_Escaped);
	$Query_Insert = $dbh->prepare($Query_Insert) or Carp::confess("Error preparing Insert-query: " . $dbh->errstr);
	if (!defined $Query_Insert) { return undef; }
	foreach my $hr_record (@{$ar_data}) {
		my @a_values = SleLib::GetHashValues($ar_Insert_Columns, $hr_record);
		foreach (0 .. $#a_values) {
			if (!defined $a_values[$_] and defined $self->default->[$_]) { $a_values[$_] = $self->default->[$_]; }
		}
		my $query_result = $Query_Insert->execute(@a_values);
		if (!defined $query_result) {
			Data::Dump::dd($Query_Insert->{Statement});
			Data::Dump::dd($hr_record);
			Carp::confess("Error inserting values into " . $self->name . ": " . $dbh->errstr);
		} else {
			$returnvalue += $query_result;
		}
	} ## end foreach my $hr_record (@{$ar_data...})
	return $returnvalue;
} ## end sub WriteData

# ReadData ($dbhandle, $hr_options)
# Options consist of:	columns = [ columns.. ]	# Select only these columns
#						modifications = { column => function, .. } # Like CreateSelectQuery
#						suffix = " WHERE ..."	# Gets appended to the query returned by CreateSelectQuery
#						parameters = [ parameter1, parameter2, ..] # Array of parameters to be supplied to the query
#						query = "SELECT..."		# Overrides everything (except parameters) and uses this query instead of creating one.
#						mode = array | hash		# Defaults to array. Indicates the use of selectall_arrayref or selectall_hashref. Using mode=hash requires the option "keys" to be specified too
#						keys = [columns]		# Arrayref of one or more keys used with mode=hash
method ReadData ($dbh !, HashRef $hr_options ?) {
	if (!defined $dbh) {
		Carp::carp("Database-handle is undefined");
		return undef;
	}
	if (!exists $hr_options->{mode}) {
		$hr_options->{mode} = "array";
	}
	my $ar_Select_Columns;
	if (!exists $hr_options->{query}) {
		$ar_Select_Columns = (exists $hr_options->{columns}) ? $hr_options->{columns} : [ $self->columns ];
		#Make a shallow copy, otherwise splicing ignored columns tampers with the object's columns-attribute
		# $ar_Select_Columns
		my @Ignore_Columns;
		foreach my $ColumnName (@{$ar_Select_Columns}) {
			#			print("Processing [$ColumnName]\n");
			my $ColumnIndex = SleLib::IndexOf($ColumnName, @{$self->columns});
			if ($ColumnIndex == -1 or $self->useintable->[$ColumnIndex] ne 'Y') {
				Carp::carp("Specified column [$ColumnName] does not exist or has useintable=N, skipping");
				push (@Ignore_Columns, $ColumnIndex);    # Queue for deletion from $ar_Insert_Columns
			}
		} ## end foreach my $ColumnName (@{$ar_Select_Columns...})
		foreach (0 .. $#Ignore_Columns) { splice (@{$ar_Select_Columns}, $Ignore_Columns[$_] - $_, 1); }    # Delete from $ar_Insert_Columns
		                                                                                                    # Escape columnnames to allow columns named with reserved words
		@{$ar_Select_Columns} = map {"`$_`"} @{$ar_Select_Columns};
		# Escape columnname-keys in $hr_options->{modifications}
		foreach (keys (%{$hr_options->{modifications}})) {
			$hr_options->{modifications}->{"`$_`"} = $hr_options->{modifications}->{$_};
			delete $hr_options->{modifications}->{$_};
		}
		$hr_options->{query} = $self->CreateSelectQuery($ar_Select_Columns, $hr_options->{modifications}) . " " . ($hr_options->{suffix} // "");
	} ## end if (!exists $hr_options...)

	#Data::Dump::dd($hr_options);
	my $r_data;                                                                                             # can be either hr or ar
	if ($hr_options->{mode} eq "array") {
		if (exists $hr_options->{parameters} and scalar @{$hr_options->{parameters}} > 0) {
			$r_data = $dbh->selectall_arrayref($hr_options->{query}, {Slice => {}}, @{$hr_options->{parameters}})
			  or Carp::confess("Error retrieving data from [" . $self->name . "]: " . $dbh->errstr);
		} else {
			$r_data = $dbh->selectall_arrayref($hr_options->{query}, {Slice => {}})
			  or Carp::confess("Error retrieving data from [" . $self->name . "]: " . $dbh->errstr);
		}
	} elsif ($hr_options->{mode} eq "hash") {
		if (!exists $hr_options->{keys}) {
			Carp::confess("No keys given for hash-mode query");
		}
		if (exists $hr_options->{parameters} and scalar @{$hr_options->{parameters}} > 0) {
			$r_data = $dbh->selectall_hashref($hr_options->{query}, $hr_options->{keys}, undef, @{$hr_options->{parameters}})
			  or Carp::confess("Error retrieving data from [" . $self->name . "]: " . $dbh->errstr);
		} else {
			$r_data = $dbh->selectall_hashref($hr_options->{query}, $hr_options->{keys})
			  or Carp::confess("Error retrieving data from [" . $self->name . "]: " . $dbh->errstr);
		}
	} else {
		Carp::confess("Unknown mode [$hr_options->{mode}] given for DataTableRead");
	}

	# Fix double/floats to not be returned as PV '0.00', but as NV
	if ($hr_options->{mode} eq "array") {
		foreach my $hr_record (@{$r_data}) {
			# TODO
		}
	}

	#print("Returning size: [" . Devel::Size::total_size($r_data) . "]\n");
	return $r_data;
} ## end sub ReadData ($$$)

1;    # so the require or use succeeds
