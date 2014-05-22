package Interfaces::DataTable;
# Version 2.0.0	3-1-2012
# Copyright (C) OGD 2011-2012

#use Devel::Size;
use Smart::Comments;
use Moose::Role;
use MooseX::Method::Signatures;
use v5.10;
#use Devel::Peek;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater

has 'indices'       => (is => 'rw', isa => 'Maybe[HashRef[ArrayRef[Str]]]', lazy_build => 1,);
has 'useintable'    => (is => 'rw', isa => 'ArrayRef[Bool]',                lazy_build => 1,);
has 'autoincrement' => (is => 'rw', isa => 'ArrayRef[Bool]',                lazy_build => 1,);

requires qw(columns displayname datatype length decimals signed allownull default fieldid);

after 'Check' => sub {
	my $self = shift;
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
};

after 'ReConfigureFromHash' => sub {
	my ($self, $hr_config) = @_;
	my @keys = keys (%{$hr_config->{Fields}});
	# Set tablename
	$self->name($hr_config->{Fields}->{$keys[0]}->{tablename});
	# Set indices
	my $hr_indices;
	foreach my $keyname (keys (%{$hr_config->{Indices}})) {
		$hr_indices->{$keyname} = [ map { s/^\s*(.+)\s*$/$1/; $_; } split (',', $hr_config->{Indices}->{$keyname}->{keyfields}) ];
	}
	if (defined $hr_indices) { $self->indices($hr_indices); }
};

# ReConfigureFromDatabase configures self using a specified table in a specified databasehandle.
# Configures self for datatable-interfacing only, all values pertaining to other interfaces are left undefined
method ReConfigureFromDatabase(Object $dbh !, Str $tablename !) {
	my $meta = $self->meta;
	# Clear attributes
	foreach ($meta->get_attribute_list) { eval "$self->clear_" . "$_"; }
	# Get columns-list from database
	my $ar_ColumnInfo = $dbh->selectall_arrayref("SHOW COLUMNS FROM `$tablename`", {Slice => {}})
	  or Carp::confess("Error getting column-info for [$tablename]: " . $dbh->errstr);
	if (!@{$ar_ColumnInfo}) { return; }    # No query results -> nothing to do
	my $ar_IndexInfo = $dbh->selectall_arrayref("SHOW INDEX FROM `$tablename`", {Slice => {}})
	  or Carp::confess("Error getting index-info for [$tablename]: " . $dbh->errstr);
	# Start setting attributes
	$self->name("$tablename");
	# Interface.pm supplies these column-attributes:
	# columns, datatype, length, decimals, signed, allownull, default, fieldid
	#		if ($_->type_constraint->name =~ /^ArrayRef/) {
	#			push (@{$self->$attributename}, $hr_config->{$Column}->{$attributename});
	my $hr_indices;
	my $hr_config;
	foreach my $fieldid (0 .. $#$ar_ColumnInfo) {
		my $column = $ar_ColumnInfo->[$fieldid];
		my $columntype;
		($columntype = $column->{Type}) =~ s/^(.*)[(]([0-9]+(?:,[0-9]+)?)[)][ ]?(.*)$/$1;$2;$3/;
		my ($dbtype, $dbsize, $dbsigned) = split (';', $columntype);
		my $decimals;
		($dbsize, $decimals) = split (',', ($dbsize // "0,0"));
		
		$hr_config->{Fields}->{$column->{Field}}->{columns} = $column->{Field};
		$hr_config->{Fields}->{$column->{Field}}->{displayname} = $column->{Field};
		$hr_config->{Fields}->{$column->{Field}}->{datatype} = uc $dbtype;
		$hr_config->{Fields}->{$column->{Field}}->{length} = $dbsize;
		
		if ($dbtype =~ /REAL|FLOAT|DOUBLE|DECIMAL|NUMERIC/i) {
			$hr_config->{Fields}->{$column->{Field}}->{decimals} = $decimals;
		}
		if ($dbtype =~ /(TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT|FLOAT|DOUBLE|REAL|DECIMAL|NUMERIC)/i) {
			$hr_config->{Fields}->{$column->{Field}}->{signed} = ($dbsigned eq "unsigned") ? "0" : "1";
		}
		$hr_config->{Fields}->{$column->{Field}}->{allownull} = ($column->{Null} eq "YES") ? "1" : "0";
		$hr_config->{Fields}->{$column->{Field}}->{default} = $column->{Default};
		$hr_config->{Fields}->{$column->{Field}}->{fieldid} = $fieldid + 1;
		$hr_config->{Fields}->{$column->{Field}}->{useintable} = 'Y';
		$hr_config->{Fields}->{$column->{Field}}->{autoincrement} = ($column->{Extra} =~ /auto_increment/i) ? 1 : 0;
	} ## end foreach my $fieldid (0 .. $#$ar_ColumnInfo)
	foreach (@{$ar_IndexInfo}) {
		push (@{$hr_indices->{$_->{Key_name}}}, $_->{Column_name});
	}
	$self->ReConfigureFromHash($hr_config);
	foreach (keys (%{$hr_indices})) {
		$self->{Indices}->{$_} = [@{$hr_indices->{$_}}];
	}
	#$self->MakeNewConfig();
} ## end sub ReConfigureFromDatabase ($$$)

# CheckDatabase checks if the interface matches the table in the given database-handle, Carp::confesses any differences
# Arguments: self, $dbh
sub CheckDatabase ($$) {
	my $self = shift;
	my $dbh  = shift;
	if (!defined $dbh) {
		Carp::confess "Supplied databasehandle is undefined";
	}
	if (ref($dbh) ne 'DBI::db') {
		Carp::confess "Supplied databasehandle is not a DBI::db handle";
	}
	my $hr_columns = $dbh->selectall_hashref("SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = '" . $self->name . "'", "COLUMN_NAME")
	  or Carp::carp("Error fetching column info for table [" . $self->name . "] from database: " . $dbh->errstr);
	if (!defined $hr_columns) { return; }
	#Data::Dump::dd($hr_columns);
	my @columns_not_in_database;
	my @columns_not_in_interface;
	my $hr_mismatches;
	my @fieldids;
	my $fieldid = 1;

	for (0 .. $#{$self->columns}) {
		my $current_field = $self->columns->[$_];
		if ($self->useintable->[$_] eq 'Y') {
			if (!exists $hr_columns->{$current_field}) { push (@columns_not_in_database, $current_field); }
			else {
				# The column is defined both in the interface and in the database. Let's check all the other fields
				# FieldID (We need to use the newly built list of fieldid's that only include fields with useintable=Y
				$fieldids[$_] = $fieldid++;
				if ($hr_columns->{$current_field}->{ORDINAL_POSITION} != $fieldids[$_]) {    #$self->fieldid->[$_]) {
					  #$hr_mismatches->{fieldid}->{$current_field} = "Interface vs DB: [" . $self->fieldid->[$_] . " vs " . $hr_columns->{$current_field}->{ORDINAL_POSITION} . "]";
					$hr_mismatches->{fieldid}->{$current_field} = "Interface vs DB: [" . $fieldids[$_] . "] vs [" . $hr_columns->{$current_field}->{ORDINAL_POSITION} . "]";
				}
				my $columntype;
				($columntype = $hr_columns->{$current_field}->{COLUMN_TYPE}) =~ s/^(.*)[(]([0-9]+),?([0-9]*)[)][ ]?(.*)$/$1,$2,$3,$4/;
				my ($dbtype, $dbsize, $dbdecimals, $dbsigned) = split (',', $columntype);
				if (!defined $dbsize) { $dbsize = $hr_columns->{$current_field}->{NUMERIC_PRECISION}; }
				#				print("$current_field: Type,Size,Decimals,Signed: [$dbtype,$dbsize,$dbdecimals,$dbsigned]\n");
				if (lc ($self->datatype->[$_]) ne lc ($dbtype)) {
					$hr_mismatches->{type}->{$current_field} = "Interface vs DB: [" . $self->datatype->[$_] . "] vs [$dbtype]";
				}
				if ($dbtype !~ /date|time/i and $self->length->[$_] != $dbsize)
				  #				if ($dbtype !~ /date|time|tinyint|smallint|mediumint|int|integer|bigint|float|double|real/i and $self->length->[$_] != $dbsize)
				{    # MySQL types DATE, TIME and numeric types do not have a size
					$hr_mismatches->{size}->{$current_field} = "Interface vs DB: [" . $self->length->[$_] . "] vs [$dbsize]";
				}
				if ($dbtype =~ /real|float|double|decimal/i) {
					if (!defined $dbdecimals and defined $self->decimals->[$_]) {
						$hr_mismatches->{decimals}->{$current_field} = "Interface vs DB: [" . $self->decimals->[$_] . "] vs NULL]";
					} elsif (defined $dbdecimals and !defined $self->decimals->[$_]) {
						$hr_mismatches->{decimals}->{$current_field} = "Interface vs DB: [NULL vs [$dbdecimals]";
					} elsif ($self->decimals->[$_] != $dbdecimals) {
						$hr_mismatches->{decimals}->{$current_field} = "Interface vs DB: [" . $self->decimals->[$_] . "] vs [$dbdecimals]";
					}
				} ## end if ($dbtype =~ /real|float|double|decimal/i)
				$dbsigned = ($dbsigned // '') eq '' ? 'Y' : $dbsigned;
				#				print("dbsigned [$dbsigned], self->signed [" . $self->signed->[$_] . "]\n");
				if (
					$dbtype =~ /TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT|FLOAT|DOUBLE|REAL|DECIMAL|NUMERIC/i
					and (   ($dbsigned eq 'Y' and $self->signed->[$_] == 0)
						 or ($dbsigned eq 'unsigned' and $self->signed->[$_] == 1))
				   )
				{
					$hr_mismatches->{signed}->{$current_field} = "Interface vs DB: [" . $self->signed->[$_] . " vs $dbsigned]";
				} ## end if ($dbtype =~ /TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT|FLOAT|DOUBLE|REAL|DECIMAL|NUMERIC/i...)
				if (substr ($hr_columns->{$current_field}->{IS_NULLABLE}, 0, 1) ne ($self->allownull->[$_] ? "Y" : "N")) {
					$hr_mismatches->{allownull}->{$current_field} = "Interface vs DB: [" . $self->allownull->[$_] . "] vs [$hr_columns->{$current_field}->{IS_NULLABLE}]";
				}
				if (defined $self->default->[$_] or defined $hr_columns->{$current_field}->{COLUMN_DEFAULT}) {
					if (!defined $self->default->[$_] and defined $hr_columns->{$current_field}->{COLUMN_DEFAULT}) {
						$hr_mismatches->{default}->{$current_field} = "Interface vs DB: NULL vs [$hr_columns->{$current_field}->{COLUMN_DEFAULT}]";
					} elsif (defined $self->default->[$_] and !defined $hr_columns->{$current_field}->{COLUMN_DEFAULT}) {
						$hr_mismatches->{default}->{$current_field} = "Interface vs DB: [" . $self->default->[$_] . "] vs NULL";
					} elsif ($self->default->[$_] ne $hr_columns->{$current_field}->{COLUMN_DEFAULT}) {
						$hr_mismatches->{default}->{$current_field} = "Interface vs DB: [" . $self->default->[$_] . "] vs [$hr_columns->{$current_field}->{COLUMN_DEFAULT}]";
					}
				} ## end if (defined $self->default...)
			} ## end else [ if (!exists $hr_columns...)]
		} ## end if ($self->useintable->...)
	} ## end for (0 .. $#{$self->columns...})
	foreach my $dbcolumn (keys (%{$hr_columns})) {
		if (!scalar grep { $_ eq $dbcolumn } @{$self->columns}) {
			push (@columns_not_in_interface, $dbcolumn);
		}
	}

	my $ar_indices = $dbh->selectall_arrayref("SHOW INDEX FROM " . $self->name, {Slice => {}})
	  or Carp::carp("Error fetching index info for table [" . $self->name . "] from database: " . $dbh->errstr);
	# Convert the array of (possibly) multiple rows with the same Key_name (but different Column_name) to a single array of Column_names
	my $hr_indices = {};
	my @keys_not_in_database;
	my @keys_not_in_interface;
	foreach (@{$ar_indices}) {
		push (@{$hr_indices->{$_->{Key_name}}->{keyfields}}, $_->{Column_name});
	}
	if ($self->has_indices) {
		foreach my $current_index (keys (%{$self->indices})) {
			if (!exists $hr_indices->{$current_index}) { push (@keys_not_in_database, $current_index); }
			else {
				my $keyfields = join(',', @{$self->{indices}->{$current_index}});
				if ($keyfields ne join (',', @{$hr_indices->{$current_index}->{keyfields}})) {
					$hr_mismatches->{indices}->{$current_index} = "Interface vs DB: [" . $keyfields . " vs " . join (',', @{$hr_indices->{$current_index}->{keyfields}}) . "]";
				}
			} ## end else [ if (!exists $hr_indices...)]
		} ## end foreach my $current_index (...)
	}
	foreach my $current_index (keys (%{$hr_indices})) {
		if (!defined $self->indices or !exists $self->indices->{$current_index}) { push (@keys_not_in_interface, $current_index); }
	}

	if (@columns_not_in_database) {
		print ("Columns not in database: " . join (',', @columns_not_in_database) . "\n");
	}
	if (@columns_not_in_interface) {
		print ("Columns not in interface: " . join (',', @columns_not_in_interface) . "\n");
	}
	if (@keys_not_in_database) {
		print ("Keys not in database: " . join (',', map { "$_: [" . join (',', @{$hr_indices->{$_}->{keyfields}}) . "]" } @keys_not_in_database) . "\n");
	}
	if (@keys_not_in_interface) {
		print ("Keys not in interface: " . join (',', map { "$_: [" . join (',', @{$hr_indices->{$_}->{keyfields}}) . "]" } @keys_not_in_interface) . "\n");
	}
	if (scalar keys (%{$hr_mismatches})) {
		Data::Dump::dd($hr_mismatches);
		Carp::confess("There were mismatches");
	}
} ## end sub CheckDatabase ($$)

# CreateInsertQuery Returns an SQL statement inserting fields @ with value ? into $self->{name}
# Arguments: self, $ar_fieldnames
sub CreateInsertQuery ($$) {
	my $self       = shift;
	my $ar_columns = shift;
	if (ref($ar_columns) ne 'ARRAY') {
		Carp::confess "1st argument is not an arrayref";
	}
	if (!$self->has_name) {
		Carp::confess "Cannot create INSERT query for object without (table)name";
	}
	return "INSERT INTO " . $self->name . "(" . join (",", @{$ar_columns}) . ") VALUES (" . join (",", map ("?", @{$ar_columns})) . ") ";
} ## end sub CreateInsertQuery ($$)

# CreateUpdateQuery Returns an SQL statement updating table $self->{name} setting fields @ to ?
# Arguments: self, $ar_fieldnames
sub CreateUpdateQuery ($$) {
	my $self       = shift;
	my $ar_columns = shift;
	if (ref($ar_columns) ne 'ARRAY') {
		Carp::confess "1st argument is not an arrayref";
	}
	return "UPDATE " . $self->{name} . " SET " . join (",", map ($_ . "=?", @{$ar_columns})) . " ";
}

# CreateInsertUpdateQuery returns an SQL statement inserting fields @{$_[1]} with value ? into table $_[0]
# On duplicate key values, all non-key values are updated with ?
sub CreateInsertUpdateQuery ($$) {
	my $self          = shift;
	my $ar_columns    = shift;
	if (ref($ar_columns) ne 'ARRAY') {
		Carp::confess "1st argument is not an arrayref";
	}
	my $ar_keycolumns = $self->indices->{PRIMARY};
	if ($#$ar_keycolumns == -1) { Carp::confess("No primary key configured, CreateInsertUpdateQuery not possible"); }
	# Escape keycolumnnames to allow columns named with reserved words
	@{$ar_keycolumns} = map { !/^[`].*[`]$/ ? "`$_`" : $_; } @{$ar_keycolumns};
	my @nonkeyfields = SleLib::Difference($ar_columns, $ar_keycolumns);
	return $self->CreateInsertQuery($ar_columns) . " ON DUPLICATE KEY UPDATE " . join (",", map ("$_=Values($_)", @nonkeyfields)) . " ";
} ## end sub CreateInsertUpdateQuery ($$)

# CreateSelectQuery Returns an SQL statement selecting fields @ from table $
# Arguments: TableName, @fieldnames, %modifications
# %modifications consists of key-value pairs as follows: "FieldName" => "WhatEverYouWant"
# This will change "FieldName" into "WhatEverYouWant AS FieldName"
sub CreateSelectQuery {
	my $self             = shift;
	my $ar_columns       = shift;
	if (ref($ar_columns) ne 'ARRAY') {
		Carp::confess "1st argument is not an arrayref";
	}
	my $hr_modifications = shift;
	if (ref($hr_modifications) ne 'HASH') {
		Carp::confess "1st argument is not a hashref";
	}
	my @Columns          = map { $hr_modifications->{$_} ? "$hr_modifications->{$_} AS $_" : $_; } @{$ar_columns};
	return "SELECT " . join (",", @Columns) . " FROM " . $self->{name};
} ## end sub CreateSelectQuery ($$$)

# TableDiff returns records uit Source that differ in values from non-keyfields compared to Target
# Source and Target tables need to be compatible with this interface (naturally)
# Arguments: dbh, Source_Tablename, Target_Tablename, ar_Fields_to_compare (these need to contain all the primary keyfields)
# Options consist of:
#	mode = array | hash		# Defaults to array. Indicates the use of selectall_arrayref or selectall_hashref. Using mode=hash requires the option "keys" to be specified too
#	keys = [columns]		# Arrayref of one or more keys used with mode=hash
#	debug = 1				# Enable debug-mode
#	null_for_match			# Selects NULL for each column that matches and only shows the value of target.column if it differs
method TableDiff ($dbh !, Str $source_tablename !, Str $target_tablename !, ArrayRef $ar_fields_to_compare !, HashRef $hr_options ?) {
	my $ar_keycolumns = $self->indices->{PRIMARY};
	if ($#$ar_keycolumns == -1) { Carp::confess("No primary key configured, TableDiff not possible"); }
	my $ar_nonkeyfields = [ grep { !($_ ~~ $ar_keycolumns); } @{$ar_fields_to_compare} ]; # preserve order
	# Escape fields
	@{$ar_keycolumns} = map { !/^[`].*[`]$/ ? "`$_`" : $_; } @{$ar_keycolumns};
	@{$ar_nonkeyfields} = map { !/^[`].*[`]$/ ? "`$_`" : $_; } @{$ar_nonkeyfields};
	my $query;
	if ($hr_options->{null_for_match}) {
		$query = "SELECT " . join(",\n", @{$ar_keycolumns}) . ",\n" . join(",\n", map { "NULLIF(target.${_}, source.${_}) AS $_"; } @{$ar_nonkeyfields} );
	} else {
		$query = "SELECT target.* ";
	}
	$query .= "
		FROM $source_tablename AS source
		LEFT JOIN $target_tablename AS target USING (" . join(',', @{$ar_keycolumns}) . ")
		WHERE NOT ISNULL(COALESCE(
			" . join(',', map { "NULLIF(target.${_}, source.${_})"; } @{$ar_nonkeyfields} ) .
		"))";
	$hr_options->{query} = $query . ' ' . ($hr_options->{suffix} // '');
	return ReadData($self, $dbh, $hr_options);
}

# CreateTable 
# Returns a string containing the CREATE TABLE statement 
sub CreateTable {
	my $self         = shift;
	my $returnstring = "CREATE TABLE ";
	my @columnnames;
	$returnstring .= "`" . $self->name . "` (\n";
	@columnnames = map { "`$_`"; } @{$self->columns};
	foreach (0 .. $#{$self->columns}) {
		$returnstring .= "  $columnnames[$_] " . $self->datatype->[$_];
		if ($self->datatype->[$_] !~ /^(DATE|TIME|DATETIME|TEXT|MONEY|BIT)$/i) {
			$returnstring .= sprintf ("(%s", $self->length->[$_]);
			if (($self->decimals->[$_] // 0) > 0) {
				$returnstring .= sprintf (",%s", $self->{decimals}[$_]);
			}
			$returnstring .= ")";
		} 
		if (($self->datatype->[$_] =~ /^(TINYINT|SMALLINT|MEDIUMINT|INT|INTEGER|BIGINT|FLOAT|DOUBLE|REAL|DECIMAL|NUMERIC)$/i) and (($self->signed->[$_] // 1) == 0)) {
			$returnstring .= " UNSIGNED";
		}
		if ($self->allownull->[$_] eq 'N') {
			$returnstring .= " NOT NULL";
		}
		if (defined $self->default->[$_]) {
			if ($self->datatype->[$_] =~ /(VARCHAR|CHAR|DATE|TIME|DATETIME)/i) {
				$returnstring .= sprintf (" DEFAULT '%s'", $self->default->[$_]);
			} else {
				$returnstring .= sprintf (" DEFAULT %s", $self->default->[$_]);
			}
		} ## end if (defined $self->default...)
		if ($self->autoincrement->[$_]) {
			$returnstring .= " AUTO_INCREMENT";
		}
		if ($_ < $#{$self->columns}) {
			$returnstring .= ",\n";
		}
	} ## end foreach (0 .. $#{$self->columns...})
	    # Index opbouwen
	if ($self->has_indices) {
		foreach (keys (%{$self->indices})) {
			if (/PRIMARY/) {
				$returnstring .= sprintf (",\n  $_ KEY (%s) ",           join (',', map { "`$_`"; } @{$self->indices->{$_}}));
			} else {
				$returnstring .= sprintf (",\n  KEY $_ (%s) ", $self->indices->{$_});
			}
		} ## end foreach (keys (%{$self->indices...}))
	} ## end if ($self->has_indices)
	$returnstring .= "\n)";
	$returnstring .= " ENGINE=InnoDB;\n";
	Data::Dump::dd($returnstring) if $Interfaces::Interface::DEBUGMODE;
	return $returnstring;
} ## end sub CreateTable

# WriteData ($dbhandle, $ar_data, $hr_options)
# Options consist of:	Columns = [columns..]	# Insert only these columns
#						Update = 0|1			# use "INSERT...ON DUPLICATE KEY UPDATE"-statements
#						Ignore = 0|1 			# Use INSERT IGNORE, cannot be used together update
# Naturally, columns must have the useintable-attribute set to 'Y'
sub WriteData {
	my ($self, $dbh, $ar_data, $hr_options) = @_;
	if (!defined $dbh) {
		Carp::confess "Database-handle is undefined";
	}
	if (ref($dbh) ne 'DBI::db') {
		Carp::confess "Supplied databasehandle is not a DBI::db handle";
	}
	if (!defined $ar_data) { return; }
	if (ref($ar_data) ne 'ARRAY') {
		Carp::confess "1st argument is not an arrayref";
	}
	my $returnvalue = 0;
	my $ar_Insert_Columns = (defined $hr_options->{Columns}) ? $hr_options->{Columns} : $self->columns;
	my $ar_Insert_Columns_Escaped;
	my @a_insert_columns; # SELF
	my $hr_column_id_translation = {}; # From SELF to QUERY
	foreach my $ColumnName (@{$ar_Insert_Columns}) {
		my $ColumnIndex = SleLib::IndexOf($ColumnName, @{$self->columns});
		if ($self->useintable->[$ColumnIndex] eq 'Y' or $self->useintable->[$ColumnIndex] eq '1') {
			push (@a_insert_columns, $ColumnIndex);
			$hr_column_id_translation->{$ColumnIndex} = $#a_insert_columns;
		} else {
			if ($hr_options->{debug}) { Carp::carp("Specified column [$ColumnName] is has useintable=N, skipping"); }
		}
	} 
	$ar_Insert_Columns = [ map { $self->{columns}->[$_]; } @a_insert_columns ];
	my $Query_Insert;
	# Escape columnnames to allow columns named with reserved words
	@{$ar_Insert_Columns_Escaped} = map {"`$_`"} @{$ar_Insert_Columns};
	if ($hr_options->{Update}) {
		$Query_Insert = $self->CreateInsertUpdateQuery($ar_Insert_Columns_Escaped);
	} else {
		$Query_Insert = $self->CreateInsertQuery($ar_Insert_Columns_Escaped);
		if ($hr_options->{Ignore}) {
			$Query_Insert =~ s/INSERT/INSERT IGNORE/;
		}
	} ## end else [ if ($hr_options->{Update...})]
	$Query_Insert = $dbh->prepare($Query_Insert) or Carp::confess("Error preparing Insert-query: " . $dbh->errstr);
	if (!defined $Query_Insert) { return; }
	foreach my $hr_record (@{$ar_data}) { ### Writing [===[%]    ]
		my @a_values = SleLib::GetHashValues($ar_Insert_Columns, $hr_record);
		if (defined $hr_options->{debug}) {
			Data::Dump::dd($hr_record);
		}
		foreach (@a_insert_columns) {
			if (!defined $a_values[$hr_column_id_translation->{$_}] and defined $self->{default}->[$_]) {
				$a_values[$hr_column_id_translation->{$_}] = $self->{default}->[$_];
			}
		}
		if (defined $hr_options->{debug}) {
			print("Values:\n");
			Data::Dump::dd(@a_values);
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
#						debug = 1				# Enable debug-mode
sub ReadData ($$$) {
	my ($self, $dbh, $hr_options) = @_;
	if (!defined $dbh) {
		Carp::confess("Database-handle is undefined");
	}
	if (ref($dbh) ne 'DBI::db') {
		Carp::confess "Supplied databasehandle is not a DBI::db handle";
	}
	if (ref($hr_options // {}) ne 'HASH') {
		Carp::confess "2nd argument is not a hashref";
	}
	if (!exists $hr_options->{mode}) {
		$hr_options->{mode} = "array";
	}
	my $ar_Select_Columns;
	if (!exists $hr_options->{query}) {
		#Make a shallow copy, otherwise splicing ignored columns tampers with the object's columns-attribute
		my $ar_Select_Columns = [@{(defined $hr_options->{columns}) ? $hr_options->{columns} : $self->columns}];
		my @Ignore_Columns;
		foreach my $ColumnName (@{$ar_Select_Columns}) {
			if ($hr_options->{debug}) { print("Processing [$ColumnName]\n"); }
			my $ColumnIndex = SleLib::IndexOf($ColumnName, @{$self->columns});
			if ($ColumnIndex == -1 or $self->useintable->[$ColumnIndex] eq 'N') {
				if ($hr_options->{debug}) { Data::Dump::dd($self); }
				Carp::confess("Specified column [$ColumnName] at index [$ColumnIndex] does not exist or has useintable=N, skipping");
				push (@Ignore_Columns, $ColumnIndex);    # Queue for deletion from $ar_Insert_Columns
			}
		} ## end foreach my $ColumnName (@{$ar_Select_Columns...})
		foreach (0 .. $#Ignore_Columns) { splice (@{$ar_Select_Columns}, $Ignore_Columns[$_] - $_, 1); }    # Delete from $ar_Insert_Columns

		if ($hr_options->{debug}) { Data::Dump::dd($ar_Select_Columns); }

		# Escape columnnames to allow columns named with reserved words
		@{$ar_Select_Columns} = map {"`$_`"} @{$ar_Select_Columns};
		# Escape columnname-keys in $hr_options->{modifications}
		foreach (keys (%{$hr_options->{modifications}})) {
			$hr_options->{modifications}->{"`$_`"} = $hr_options->{modifications}->{$_};
			delete $hr_options->{modifications}->{$_};
		}
		$hr_options->{query} = $self->CreateSelectQuery($ar_Select_Columns, $hr_options->{modifications}) . " " . ($hr_options->{suffix} // "");
		if ($hr_options->{debug}) { Data::Dump::dd($hr_options->{query}); }
	} ## end if (!exists $hr_options...)

	#Data::Dump::dd($hr_options);
	my $r_data;
	# can be either hr or ar
	if ($hr_options->{mode} eq "array") {
		if (exists $hr_options->{parameters} and scalar @{$hr_options->{parameters}} > 0) {
			$r_data = $dbh->selectall_arrayref($hr_options->{query}, {Slice => {}}, @{$hr_options->{parameters}})
			  or Carp::confess("Error retrieving data from [" . $self->name . "]: " . $dbh->errstr);
		} else {
			$r_data = $dbh->selectall_arrayref($hr_options->{query}, {Slice => {}})
			  or Carp::confess("Error retrieving data from [" . $self->name . "]: " . $dbh->errstr);
		}
		# Trim alle textfields, delete all empty fields to save memory
		foreach my $hr_record (@{$r_data}) {
			my @delete_these_columns = ();
			foreach my $column (keys %{$hr_record}) {
				if (!defined $hr_record->{$column}) {
					push(@delete_these_columns, $column);
					next;
				}
				my $ColumnIndex = SleLib::IndexOf($column, @{$self->columns});
				if ($self->datatype->[$ColumnIndex] =~ /^(CHAR|VARCHAR|TEXT)$/) {
					$hr_record->{$column} =~ s/^([ ]*)(.*?)([ ]*)$/$2/; # Trim
					if ($hr_record->{$column} eq '') {
						push(@delete_these_columns, $column);
					}
				}
			}
			foreach my $column (@delete_these_columns) {
				delete $hr_record->{$column};
			}
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
		# TODO: Trim all textfields
	} else {
		Carp::confess("Unknown mode [$hr_options->{mode}] given for DataTableRead");
	}

	# Fix double/floats to not be returned as PV '0.00', but as NV
	if (!defined $hr_options->{query} and $hr_options->{mode} eq "array") {
		foreach my $hr_record (@{$r_data}) { 
			foreach my $ColumnIndex (0 .. $#{$self->columns}) {
				my $ColumnName = $self->columns->[$ColumnIndex];
				if (defined $hr_record->{$ColumnName} and $self->datatype->[$ColumnIndex] =~ /^(?:FLOAT|DOUBLE|DECIMAL|NUMERIC|DEC|FIXED)$/) {
					my $oldvalue = $hr_record->{$ColumnName};
					delete $hr_record->{$ColumnName};
					$hr_record->{$ColumnName} = 0 + $oldvalue;
				}
			}
		}
	}

	#print("Returning size: [" . Devel::Size::total_size($r_data) . "]\n");
	return $r_data;
} ## end sub ReadData ($$$)

1;

=head1 NAME

Interfaces::DataTable - MySQL database extension to Interfaces::Interface

=head1 VERSION

This document refers to Interfaces::DataTable version 1.0.0.

=head1 SYNOPSIS

  use Interfaces::Interface;
  my $interface = Interfaces::Interface->new();
  $interface->ReConfigureFromHash($hr_config);
  my $ar_data = $interface->DataTable_ReadData($dbh);
  $interface->DataTable_WriteData($dbh, $ar_data);

=head1 DESCRIPTION

This module extends the Interfaces::Interface with the capabilities to read from - and
write to MySQL tables.

=head2 Attributes for C<Interfaces::DataTable>

=over 4

=item * C<indices>

=item * C<useintable>

=item * C<autoincrement>

=back

=head2 Methods for C<Interfaces::DataTable>

=over 4

=item * C<$interface-E<gt>ReConfigureFromDatabase($dbh, $tablename);>

Configures the Interface-object from an existing table in the database instead of a supplied $hr_config.

=item * C<$interface-E<gt>CheckDatabase($dbh);>

Checks if the table with $self->tablename exists in the database and has a configuration compatible to the
configuration of the interface-object. Calls Carp::confess if discrepancies are found (after printing those
discrepancies to stdout).

=item * C<$interface-E<gt>CreateInsertQuery($ar_columnnames);>

Returns a string with an INSERT-query created for $self->tablename and the supplied $ar_columnnames.

=item * C<$interface-E<gt>CreateUpdateQuery($ar_columnnames);>

Returns a string with an UPDATE-query created for $self->tablename and the supplied $ar_columnnames.

=item * C<$interface-E<gt>CreateInsertUpdateQuery($ar_columnnames);>

Returns a string with an INSERT ON DUPLICATE KEY UPDATE-query created for $self->tablename and the supplied
$ar_columnnames.

=item * C<$interface-E<gt>CreateSelectQuery($ar_columnnames, $hr_modifications);>

Returns a string with a SELECT-query created for $self->tablename and the supplied $ar_columnnames. For each
columnname that is listed as a key in $hr_modifications, the accompagning value in $hr_modifications is used
instead. For example:

$interface->CreateSelectQuery(['foo'], { foo => 'bar(foo)' })
will result in: 'SELECT foo FROM tablename'

$interface->CreateSelectQuery(['foo'], { foo => 'bar(foo)' })
will result in: 'SELECT bar(foo) AS foo FROM tablename'

=item * C<$interface-E<gt>CreateTable();>

Returns a string with a CREATE TABLE-query that creates a table with a configuration equivalent with the
configuration of the interface-object.

=item * C<$interface-E<gt>ReadData($dbh, $hr_options);>

Options consist of:	columns = [columns..]	# Select only these columns
					modifications = { column => replacement, ..} # Like CreateSelectQuery
					suffix = " WHERE ..."	# Gets appended to the query returned by CreateSelectQuery
					parameters = [parameter1, parameter2, ..] # Arrayref of parameters to be supplied to the query
					query = "SELECT..."		# Overrides everything (except parameters) and uses this query instead of creating one.
					mode = array | hash		# Defaults to array. Indicates the use of selectall_arrayref or selectall_hashref. Using mode=hash requires the option "keys" to be specified too
					keys = [columns]		# Arrayref of one or more keys used with mode=hash
					
Reads data from $self->tablename in $dbh and the supplied (optional) options. Returns an arrayref with a
hashref per record.

=item * C<$interface-E<gt>WriteData($dbh, $ar_data, $hr_options);>

Options consist of:	Columns = [columns..]	# Insert only these columns
					Update = 0|1			# use "INSERT...ON DUPLICATE KEY UPDATE"-statements
					Ignore = 0|1 			# Use INSERT IGNORE, cannot be used together with Update

Only writes columns with attribute useintable[n] ne 'N'.

=back

=head1 DEPENDENCIES

L<Interfaces::Interface>, L<Moose>, L<Carp> and a (DBI::db) MySQL database.

=head1 AUTHOR

The original author is Herbert Buurman

=head1 LICENSE

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See L<perlartistic>.

=cut

