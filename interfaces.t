#!/usr/bin/perl

use strict;
use English;
use Test::More;
use Data::Dump;
use Try::Tiny;
use v5.10.0;
no if $] >= 5.018, warnings => "experimental"; # Only suppress experimental warnings in Perl 5.18.0 or greater

# Test 1: Module inclusion
BEGIN { no strict; use_ok(Interfaces); use strict; }

my $OVERFLOW_METHOD_TRUNC = $Interfaces::OVERFLOW_METHOD_TRUNC;
my $OVERFLOW_METHOD_ROUND = $Interfaces::OVERFLOW_METHOD_ROUND;

# Testfiles for various interfaces
my $hr_testfiles = {
	delimited => 'testdata/delimited.csv',
	flat => 'testdata/flat.txt',
	xls => 'testdata/Excel.xls',
	xlsx => 'testdata/Excel.xlsx',
};

# Test 2: Object creation
no strict;
my $interface = new_ok(Interfaces);
use strict;

# Test single interactions
my $test_single = 0;
# Single field tests for various datatypes
my $hr_interface_config = {
	Fields => { 
		testfield1 => {
			tablename => 'test',
			fieldname => 'testfield1',
			displayname => 'DisplayName Test 1',
			length => 30,
			fieldid => 1,
			flatfield_start => 0,
			flatfield_length => 30,
		},
	}
};

foreach my $datatype (qw(CHAR VARCHAR)) {
	$hr_interface_config->{Fields}->{testfield1}->{datatype} = $datatype;
	subtest 'Configuring interface with single ' . $datatype . '[30] field' => sub {
		ok( $interface->ReConfigureFromHash($hr_interface_config),	'ReConfigureFromHash');
		is( $interface->name, 'test',								'Get name');
		is( $interface->columns->[0], 'testfield1',				'Get column name');
		is( $interface->displayname->[0], 'DisplayName Test 1',	'Get column displayname');
		is( $interface->datatype->[0], $datatype,					'Get column type');
		is( $interface->length->[0], 30,							'Get column size');
		is( $interface->fieldid->[0], 1,							'Get column fieldid');
		ok( $interface->Check(),									'Interface self-check');

		ok(
			$interface->DelimitedFile_ConfigureUseInFile($interface->displayname),
			'DelimitedFile_ConfigureUseInFile'
		);
		is_deeply(
			$interface->DelimitedFile_ReadRecord('thisisjusttestletter'),
			{ testfield1 => 'thisisjusttestletter' },
			'DelimitedFile_ReadRecord'
		);
		is(
			$interface->FlatFile_WriteRecord( { testfield1 => 'thisisjusttestletter' } ),
			'thisisjusttestletter          ',
			'FlatFile_WriteRecord'
		);
		is_deeply(
			$interface->FlatFile_ReadRecord( '     thisisjusttestletter     '),
			{ testfield1 => 'thisisjusttestletter' },
			'FlatFile_ReadRecord (with auto-trimming)'
		);
	};
}
delete $hr_interface_config->{Fields}->{testfield1}->{length};

my $hr_minmax_value = {
	TINYINT		=> {	min => { Y => sub { - (2**7); },	N => sub { 0; } },
						max => { N => sub { 2**8 - 1; },	Y => sub { 2**7 - 1; } } },
	SMALLINT	=> {	min => { Y => sub { - (2**15); },	N => sub { 0; } },
						max => { N => sub { 2**16 - 1; },	Y => sub { 2**15 - 1; } } },
	MEDIUMINT	=> {	min => { Y => sub { - (2**23); },	N => sub { 0; } },
						max => { N => sub { 2**24 - 1; },	Y => sub { 2**23 - 1; } } },
	INT			=> {	min => { Y => sub { - (2**31); },	N => sub { 0; } },
						max => { N => sub { 2**32 - 1; },	Y => sub { 2**31 - 1; } } },
	INTEGER		=> {	min => { Y => sub { - (2**31); },	N => sub { 0; } },
						max => { N => sub { 2**32 - 1; },	Y => sub { 2**31 - 1; } } },
	BIGINT		=> {	min => { Y => sub { - (2**63); },	N => sub { 0; } },
						max => { N => sub { 2**64 - 1; },	Y => sub { 2**63 - 1; } } },
	FLOAT		=> {	min => { Y => sub { my ($length, $decimals) = @_; - (10**($length - $decimals)) + (10**(-$decimals)); }, N => sub { 0; } }, 
						max => { N => sub { my ($length, $decimals) = @_; 10**($length - $decimals) - 10**(-$decimals); }, Y => sub { my ($length, $decimals) = @_; (10**($length - $decimals)) - (10**(-$decimals)); } } },
	DOUBLE		=> {	min => { Y => sub { my ($length, $decimals) = @_; - (10**($length - $decimals)) + (10**(-$decimals)); }, N => sub { 0; } }, 
						max => { N => sub { my ($length, $decimals) = @_; 10**($length - $decimals) - 10**(-$decimals); }, Y => sub { my ($length, $decimals) = @_; (10**($length - $decimals)) - (10**(-$decimals)); } } },
	DECIMAL		=> {	min => { Y => sub { my ($length, $decimals) = @_; - (10**($length - $decimals)) + (10**(-$decimals)); }, N => sub { 0; } }, 
						max => { N => sub { my ($length, $decimals) = @_; 10**($length - $decimals) - 10**(-$decimals); }, Y => sub { my ($length, $decimals) = @_; (10**($length - $decimals)) - (10**(-$decimals)); } } },
	NUMERIC		=> {	min => { Y => sub { my ($length, $decimals) = @_; - (10**($length - $decimals)) + (10**(-$decimals)); }, N => sub { 0; } }, 
						max => { N => sub { my ($length, $decimals) = @_; 10**($length - $decimals) - 10**(-$decimals); }, Y => sub { my ($length, $decimals) = @_; (10**($length - $decimals)) - (10**(-$decimals)); } } },
};

# Expected resultvalues for single tests
my $hr_testvalues_results = {
	testvalues => [
		{	regular => 7,				flat => '0'x29 . '7',					delimited => '7',	},
		{	regular => -7,				flat => '-' . '0'x28 . '7',				delimited => '-7',	},
		{	regular => 123,				flat => '0'x27 . '123',					delimited => '123',	},
		{	regular => -123,			flat => '-' . '0'x26 . '123',			delimited => '-123',	},
		{	regular => 23.4,			flat => '0'x27 . '234',					delimited => '23.4',	},
		{	regular => -23.4,			flat => '-' . '0'x26 . '234',			delimited => '-23.4',	},
		{	regular => 45.67,			flat => '0'x26 . '4567',				delimited => '45.67',	},
		{	regular => -45.67,			flat => '-' . '0'x25 . '4567',			delimited => '-45.67',	},
		{	regular => 67.890,			flat => '0'x25 . '67890',				delimited => '67.890',	},
		{	regular => -67.890,			flat => '-' . '0'x24 . '67890',			delimited => '-67.890',	},
		{	regular => 1928.3746,		flat => '0'x22 . '19283746',			delimited => '1928.3746',	},
		{	regular => -1928.3746,		flat => '-' . '0'x21 . '19283746',		delimited => '-1928.3746',	},
		{	regular => 45678.90123,		flat => '0'x20 . '4567890123',			delimited => '45678.90123',	},
		{	regular => -45678.90123,	flat => '-' . '0'x19 . '4567890123',	delimited => '-45678.90123',	},
		{	regular => 78912345.6,		flat => '0'x21 . '789123456',			delimited => '78912345.6',	},
		{	regular => -78912345.6,		flat => '-' . '0'x20 . '789123456',		delimited => '-78912345.6',	},
	],
	results => {
		TINYINT		=> {
			# signed
			1			=> {
				# length
				2			=> {
					# decimals
					0			=> {
						# overflow_method
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x28 . '7',		flatread_result => -7,		delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 23,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-' . '0'x27 . '23',	flatread_result => -23,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 34,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-' . '0'x27 . '23',	flatread_result => -34,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 67,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-' . '0'x27 . '45',	flatread_result => -67,		delimitedwrite_result => '-45',		delimitedread_result => -45, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 90,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '-' . '0'x27 . '67',	flatread_result => -90,		delimitedwrite_result => '-67',		delimitedread_result => -67, },
							{	flatwrite_result => '0'x28 . '28',			flatread_result => 46,		delimitedwrite_result => '28',		delimitedread_result => 28, },
							{	flatwrite_result => '-' . '0'x27 . '28',	flatread_result => -46,		delimitedwrite_result => '-28',		delimitedread_result => -28, },
							{	flatwrite_result => '0'x28 . '78',			flatread_result => 23,		delimitedwrite_result => '78',		delimitedread_result => 78, },
							{	flatwrite_result => '-' . '0'x27 . '78',	flatread_result => -23,		delimitedwrite_result => '-78',		delimitedread_result => -78, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 56,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-' . '0'x27 . '45',	flatread_result => -56,		delimitedwrite_result => '-45',		delimitedread_result => -45, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x28 . '7',		flatread_result => -7,		delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '-' . '0'x27 . '99',	flatread_result => -99,		delimitedwrite_result => '-99',		delimitedread_result => -99, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 99,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-' . '0'x27 . '23',	flatread_result => -99,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 99,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '-' . '0'x27 . '46',	flatread_result => -99,		delimitedwrite_result => '-46',		delimitedread_result => -46, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 99,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '-' . '0'x27 . '68',	flatread_result => -99,		delimitedwrite_result => '-68',		delimitedread_result => -68, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '-' . '0'x27 . '99',	flatread_result => -99,		delimitedwrite_result => '-99',		delimitedread_result => -99, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '-' . '0'x27 . '99',	flatread_result => -99,		delimitedwrite_result => '-99',		delimitedread_result => -99, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '-' . '0'x27 . '99',	flatread_result => -99,		delimitedwrite_result => '-99',		delimitedread_result => -99, },
						],
					},
				},
				5			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x28 . '7',		flatread_result => -7,		delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,		delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-' . '0'x26 . '123',	flatread_result => -123,	delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 127,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-' . '0'x27 . '23',	flatread_result => -128,	delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 127,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-' . '0'x27 . '45',	flatread_result => -128,	delimitedwrite_result => '-45',		delimitedread_result => -45, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 127,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '-' . '0'x27 . '67',	flatread_result => -128,	delimitedwrite_result => '-67',		delimitedread_result => -67, },
							{	flatwrite_result => '0'x27 . '127',			flatread_result => 127,		delimitedwrite_result => '127',		delimitedread_result => 127, },
							{	flatwrite_result => '-' . '0'x26 . '128',	flatread_result => -128,	delimitedwrite_result => '-128',	delimitedread_result => -128, },
							{	flatwrite_result => '0'x27 . '127',			flatread_result => 127,		delimitedwrite_result => '127',		delimitedread_result => 127, },
							{	flatwrite_result => '-' . '0'x26 . '128',	flatread_result => -128,	delimitedwrite_result => '-128',	delimitedread_result => -128, },
							{	flatwrite_result => '0'x27 . '127',			flatread_result => 127,		delimitedwrite_result => '127',		delimitedread_result => 127, },
							{	flatwrite_result => '-' . '0'x26 . '128',	flatread_result => -128,	delimitedwrite_result => '-128',	delimitedread_result => -128, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x28 . '7',		flatread_result => -7,		delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,		delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-' . '0'x26 . '123',	flatread_result => -123,	delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 127,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-' . '0'x27 . '23',	flatread_result => -128,	delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 127,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '-' . '0'x27 . '46',	flatread_result => -128,	delimitedwrite_result => '-46',		delimitedread_result => -46, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 127,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '-' . '0'x27 . '68',	flatread_result => -128,	delimitedwrite_result => '-68',		delimitedread_result => -68, },
							{	flatwrite_result => '0'x27 . '127',			flatread_result => 127,		delimitedwrite_result => '127',		delimitedread_result => 127, },
							{	flatwrite_result => '-' . '0'x26 . '128',	flatread_result => -128,	delimitedwrite_result => '-128',	delimitedread_result => -128, },
							{	flatwrite_result => '0'x27 . '127',			flatread_result => 127,		delimitedwrite_result => '127',		delimitedread_result => 127, },
							{	flatwrite_result => '-' . '0'x26 . '128',	flatread_result => -128,	delimitedwrite_result => '-128',	delimitedread_result => -128, },
							{	flatwrite_result => '0'x27 . '127',			flatread_result => 127,		delimitedwrite_result => '127',		delimitedread_result => 127, },
							{	flatwrite_result => '-' . '0'x26 . '128',	flatread_result => -128,	delimitedwrite_result => '-128',	delimitedread_result => -128, },
						],
					},
				},
			},
			# signed
			0		=> {
				# length
				2		=> {
					# decimals
					0		=> {
						# overflow_method
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',	flatread_result => 7,	delimitedwrite_result => '7',	delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',	flatread_result => 23,	delimitedwrite_result => '23',	delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',	flatread_result => 34,	delimitedwrite_result => '23',	delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',	flatread_result => 67,	delimitedwrite_result => '45',	delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '67',	flatread_result => 90,	delimitedwrite_result => '67',	delimitedread_result => 67, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '28',	flatread_result => 46,	delimitedwrite_result => '28',	delimitedread_result => 28, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '78',	flatread_result => 23,	delimitedwrite_result => '78',	delimitedread_result => 78, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',	flatread_result => 56,	delimitedwrite_result => '45',	delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',	flatread_result => 7,	delimitedwrite_result => '7',	delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '99',	flatread_result => 99,	delimitedwrite_result => '99',	delimitedread_result => 99, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',	flatread_result => 99,	delimitedwrite_result => '23',	delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '46',	flatread_result => 99,	delimitedwrite_result => '46',	delimitedread_result => 46, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '68',	flatread_result => 99,	delimitedwrite_result => '68',	delimitedread_result => 68, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '99',	flatread_result => 99,	delimitedwrite_result => '99',	delimitedread_result => 99, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '99',	flatread_result => 99,	delimitedwrite_result => '99',	delimitedread_result => 99, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '99',	flatread_result => 99,	delimitedwrite_result => '99',	delimitedread_result => 99, },
							{	flatwrite_result => '0'x30,			flatread_result => 0,	delimitedwrite_result => '0',	delimitedread_result => 0, },
						],
					},
				},
				5		=> {
					0		=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,		delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 255,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 255,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '255',			flatread_result => 255,		delimitedwrite_result => '255',		delimitedread_result => 255, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '255',			flatread_result => 255,		delimitedwrite_result => '255',		delimitedread_result => 255, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '255',			flatread_result => 255,		delimitedwrite_result => '255',		delimitedread_result => 255, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,		delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 255,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 255,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '255',			flatread_result => 255,		delimitedwrite_result => '255',		delimitedread_result => 255, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '255',			flatread_result => 255,		delimitedwrite_result => '255',		delimitedread_result => 255, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '255',			flatread_result => 255,		delimitedwrite_result => '255',		delimitedread_result => 255, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
						],
					},
				},
			},
		},
		SMALLINT	=> {
			# signed
			1			=> {
				# length
				2			=> {
					# decimals
					0			=> {
						# overflow_method
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x28 . '7',		flatread_result => -7,		delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 23,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-' . '0'x27 . '23',	flatread_result => -23,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 34,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-' . '0'x27 . '23',	flatread_result => -34,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 67,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-' . '0'x27 . '45',	flatread_result => -67,		delimitedwrite_result => '-45',		delimitedread_result => -45, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 90,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '-' . '0'x27 . '67',	flatread_result => -90,		delimitedwrite_result => '-67',		delimitedread_result => -67, },
							{	flatwrite_result => '0'x28 . '28',			flatread_result => 46,		delimitedwrite_result => '28',		delimitedread_result => 28, },
							{	flatwrite_result => '-' . '0'x27 . '28',	flatread_result => -46,		delimitedwrite_result => '-28',		delimitedread_result => -28, },
							{	flatwrite_result => '0'x28 . '78',			flatread_result => 23,		delimitedwrite_result => '78',		delimitedread_result => 78, },
							{	flatwrite_result => '-' . '0'x27 . '78',	flatread_result => -23,		delimitedwrite_result => '-78',		delimitedread_result => -78, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 56,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-' . '0'x27 . '45',	flatread_result => -56,		delimitedwrite_result => '-45',		delimitedread_result => -45, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x28 . '7',		flatread_result => -7,		delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '-' . '0'x27 . '99',	flatread_result => -99,		delimitedwrite_result => '-99',		delimitedread_result => -99, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 99,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-' . '0'x27 . '23',	flatread_result => -99,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 99,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '-' . '0'x27 . '46',	flatread_result => -99,		delimitedwrite_result => '-46',		delimitedread_result => -46, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 99,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '-' . '0'x27 . '68',	flatread_result => -99,		delimitedwrite_result => '-68',		delimitedread_result => -68, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '-' . '0'x27 . '99',	flatread_result => -99,		delimitedwrite_result => '-99',		delimitedread_result => -99, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '-' . '0'x27 . '99',	flatread_result => -99,		delimitedwrite_result => '-99',		delimitedread_result => -99, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '-' . '0'x27 . '99',	flatread_result => -99,		delimitedwrite_result => '-99',		delimitedread_result => -99, },
						],
					},
				},
				5			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x28 . '7',		flatread_result => -7,		delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,		delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-' . '0'x26 . '123',	flatread_result => -123,	delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-' . '0'x27 . '23',	flatread_result => -234,	delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,	delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-' . '0'x27 . '45',	flatread_result => -4567,	delimitedwrite_result => '-45',		delimitedread_result => -45, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 32767,	delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '-' . '0'x27 . '67',	flatread_result => -32768,	delimitedwrite_result => '-67',		delimitedread_result => -67, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 32767,	delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-' . '0'x25 . '1928',	flatread_result => -32768,	delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '32767',		flatread_result => 32767,	delimitedwrite_result => '32767',	delimitedread_result => 32767, },
							{	flatwrite_result => '-' . '0'x24 . '32768',	flatread_result => -32768,	delimitedwrite_result => '-32768',	delimitedread_result => -32768, },
							{	flatwrite_result => '0'x25 . '12345',		flatread_result => 23456,	delimitedwrite_result => '12345',	delimitedread_result => 12345, },
							{	flatwrite_result => '-' . '0'x24 . '12345',	flatread_result => -23456,	delimitedwrite_result => '-12345',	delimitedread_result => -12345, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x28 . '7',		flatread_result => -7,		delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,		delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-' . '0'x26 . '123',	flatread_result => -123,	delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-' . '0'x27 . '23',	flatread_result => -234,	delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,	delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '-' . '0'x27 . '46',	flatread_result => -4567,	delimitedwrite_result => '-46',		delimitedread_result => -46, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 32767,	delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '-' . '0'x27 . '68',	flatread_result => -32768,	delimitedwrite_result => '-68',		delimitedread_result => -68, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 32767,	delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-' . '0'x25 . '1928',	flatread_result => -32768,	delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '32767',		flatread_result => 32767,	delimitedwrite_result => '32767',	delimitedread_result => 32767, },
							{	flatwrite_result => '-' . '0'x24 . '32768',	flatread_result => -32768,	delimitedwrite_result => '-32768',	delimitedread_result => -32768, },
							{	flatwrite_result => '0'x25 . '32767',		flatread_result => 32767,	delimitedwrite_result => '32767',	delimitedread_result => 32767, },
							{	flatwrite_result => '-' . '0'x24 . '32768',	flatread_result => -32768,	delimitedwrite_result => '-32768',	delimitedread_result => -32768, },
						],
					},
				},
			},
			0			=> {
				# length
				2			=> {
					# decimals
					0			=> {
						# overflow_method
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 23,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 34,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 67,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 90,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '28',			flatread_result => 46,		delimitedwrite_result => '28',		delimitedread_result => 28, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '78',			flatread_result => 23,		delimitedwrite_result => '78',		delimitedread_result => 78, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 56,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 99,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 99,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 99,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
						],
					},
				},
				5			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,		delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,	delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 65535,	delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 65535,	delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 65535,	delimitedwrite_result => '45678',	delimitedread_result => 45678, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '12345',		flatread_result => 23456,	delimitedwrite_result => '12345',	delimitedread_result => 12345, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,		delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,	delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 65535,	delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 65535,	delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 65535,	delimitedwrite_result => '45679',	delimitedread_result => 45679, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '65535',		flatread_result => 65535,	delimitedwrite_result => '65535',	delimitedread_result => 65535, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
						],
					},
				},
				16			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,		delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,	delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 65535,	delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 65535,	delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 65535,	delimitedwrite_result => '45678',	delimitedread_result => 45678, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '65535',		flatread_result => 65535,	delimitedwrite_result => '65535',	delimitedread_result => 65535, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,		delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,	delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 65535,	delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 65535,	delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 65535,	delimitedwrite_result => '45679',	delimitedread_result => 45679, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '65535',		flatread_result => 65535,	delimitedwrite_result => '65535',	delimitedread_result => 65535, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
						],
					},
				},
			},
		},
		MEDIUMINT	=> {
			# signed
			1			=> {
				# length
				2			=> {
					# decimals
					0			=> {
						# overflow_method
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x28 . '7',		flatread_result => -7,		delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 23,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-' . '0'x27 . '23',	flatread_result => -23,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 34,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-' . '0'x27 . '23',	flatread_result => -34,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 67,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-' . '0'x27 . '45',	flatread_result => -67,		delimitedwrite_result => '-45',		delimitedread_result => -45, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 90,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '-' . '0'x27 . '67',	flatread_result => -90,		delimitedwrite_result => '-67',		delimitedread_result => -67, },
							{	flatwrite_result => '0'x28 . '28',			flatread_result => 46,		delimitedwrite_result => '28',		delimitedread_result => 28, },
							{	flatwrite_result => '-' . '0'x27 . '28',	flatread_result => -46,		delimitedwrite_result => '-28',		delimitedread_result => -28, },
							{	flatwrite_result => '0'x28 . '78',			flatread_result => 23,		delimitedwrite_result => '78',		delimitedread_result => 78, },
							{	flatwrite_result => '-' . '0'x27 . '78',	flatread_result => -23,		delimitedwrite_result => '-78',		delimitedread_result => -78, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 56,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-' . '0'x27 . '45',	flatread_result => -56,		delimitedwrite_result => '-45',		delimitedread_result => -45, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x28 . '7',		flatread_result => -7,		delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '-' . '0'x27 . '99',	flatread_result => -99,		delimitedwrite_result => '-99',		delimitedread_result => -99, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 99,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-' . '0'x27 . '23',	flatread_result => -99,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 99,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '-' . '0'x27 . '46',	flatread_result => -99,		delimitedwrite_result => '-46',		delimitedread_result => -46, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 99,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '-' . '0'x27 . '68',	flatread_result => -99,		delimitedwrite_result => '-68',		delimitedread_result => -68, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '-' . '0'x27 . '99',	flatread_result => -99,		delimitedwrite_result => '-99',		delimitedread_result => -99, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '-' . '0'x27 . '99',	flatread_result => -99,		delimitedwrite_result => '-99',		delimitedread_result => -99, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '-' . '0'x27 . '99',	flatread_result => -99,		delimitedwrite_result => '-99',		delimitedread_result => -99, },
						],
					},
				},
				5			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-'.'0'x27 . '45',		flatread_result => -4567,		delimitedwrite_result => '-45',		delimitedread_result => -45, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '-'.'0'x27 . '67',		flatread_result => -67890,		delimitedwrite_result => '-67',		delimitedread_result => -67, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 83746,		delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -83746,		delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 90123,		delimitedwrite_result => '45678',	delimitedread_result => 45678, },
							{	flatwrite_result => '-'.'0'x24 . '45678',	flatread_result => -90123,		delimitedwrite_result => '-45678',	delimitedread_result => -45678, },
							{	flatwrite_result => '0'x25 . '12345',		flatread_result => 23456,		delimitedwrite_result => '12345',	delimitedread_result => 12345, },
							{	flatwrite_result => '-'.'0'x24 . '12345',	flatread_result => -23456,		delimitedwrite_result => '-12345',	delimitedread_result => -12345, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '-'.'0'x27 . '46',		flatread_result => -4567,		delimitedwrite_result => '-46',		delimitedread_result => -46, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '-'.'0'x27 . '68',		flatread_result => -67890,		delimitedwrite_result => '-68',		delimitedread_result => -68, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 99999,		delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -99999,		delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 99999,		delimitedwrite_result => '45679',	delimitedread_result => 45679, },
							{	flatwrite_result => '-'.'0'x24 . '45679',	flatread_result => -99999,		delimitedwrite_result => '-45679',	delimitedread_result => -45679, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 99999,		delimitedwrite_result => '99999',	delimitedread_result => 99999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -99999,		delimitedwrite_result => '-99999',	delimitedread_result => -99999, },
						],
					},
				},
				16			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',			delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',		delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',			delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',			delimitedread_result => 45, },
							{	flatwrite_result => '-'.'0'x27 . '45',		flatread_result => -4567,		delimitedwrite_result => '-45',			delimitedread_result => -45, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',			delimitedread_result => 67, },
							{	flatwrite_result => '-'.'0'x27 . '67',		flatread_result => -67890,		delimitedwrite_result => '-67',			delimitedread_result => -67, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 8388607,		delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -8388608,	delimitedwrite_result => '-1928',		delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 8388607,		delimitedwrite_result => '45678',		delimitedread_result => 45678, },
							{	flatwrite_result => '-'.'0'x24 . '45678',	flatread_result => -8388608,	delimitedwrite_result => '-45678',		delimitedread_result => -45678, },
							{	flatwrite_result => '0'x23 . '8388607',		flatread_result => 8388607,		delimitedwrite_result => '8388607',		delimitedread_result => 8388607, },
							{	flatwrite_result => '-'.'0'x22 .'8388608',	flatread_result => -8388608,	delimitedwrite_result => '-8388608',	delimitedread_result => -8388608, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',			delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',		delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',			delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',			delimitedread_result => 46, },
							{	flatwrite_result => '-'.'0'x27 . '46',		flatread_result => -4567,		delimitedwrite_result => '-46',			delimitedread_result => -46, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',			delimitedread_result => 68, },
							{	flatwrite_result => '-'.'0'x27 . '68',		flatread_result => -67890,		delimitedwrite_result => '-68',			delimitedread_result => -68, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 8388607,		delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -8388608,	delimitedwrite_result => '-1928',		delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 8388607,		delimitedwrite_result => '45679',		delimitedread_result => 45679, },
							{	flatwrite_result => '-'.'0'x24 . '45679',	flatread_result => -8388608,	delimitedwrite_result => '-45679',		delimitedread_result => -45679, },
							{	flatwrite_result => '0'x23 . '8388607',		flatread_result => 8388607,		delimitedwrite_result => '8388607',		delimitedread_result => 8388607, },
							{	flatwrite_result => '-'.'0'x22 .'8388608',	flatread_result => -8388608,	delimitedwrite_result => '-8388608',	delimitedread_result => -8388608, },
						],
					},
				},
			},
			0			=> {
				# length
				2			=> {
					# decimals
					0			=> {
						# overflow_method
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 23,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 34,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 67,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 90,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '28',			flatread_result => 46,		delimitedwrite_result => '28',		delimitedread_result => 28, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '78',			flatread_result => 23,		delimitedwrite_result => '78',		delimitedread_result => 78, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 56,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,		delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 99,		delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 99,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 99,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '99',			flatread_result => 99,		delimitedwrite_result => '99',		delimitedread_result => 99, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,		delimitedwrite_result => '0',		delimitedread_result => 0, },
						],
					},
				},
				5			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',			delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',			delimitedread_result => 67, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 83746,		delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 90123,		delimitedwrite_result => '45678',		delimitedread_result => 45678, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '12345',		flatread_result => 23456,		delimitedwrite_result => '12345',		delimitedread_result => 12345, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',			delimitedread_result => 46, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',			delimitedread_result => 68, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 99999,		delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 99999,		delimitedwrite_result => '45679',		delimitedread_result => 45679, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 99999,		delimitedwrite_result => '99999',		delimitedread_result => 99999, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
						],
					},
				},
				16			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',			delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',			delimitedread_result => 67, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 16777215,	delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 16777215,	delimitedwrite_result => '45678',		delimitedread_result => 45678, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x22 . '16777215',	flatread_result => 16777215,	delimitedwrite_result => '16777215',	delimitedread_result => 16777215, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',			delimitedread_result => 46, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',			delimitedread_result => 68, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 16777215,	delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 16777215,	delimitedwrite_result => '45679',		delimitedread_result => 45679, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x22 . '16777215',	flatread_result => 16777215,	delimitedwrite_result => '16777215',	delimitedread_result => 16777215, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
						],
					},
				},
			},
		},
		INTEGER	=> {
			# signed
			1			=> {
				# length
				5			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-'.'0'x27 . '45',		flatread_result => -4567,		delimitedwrite_result => '-45',		delimitedread_result => -45, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '-'.'0'x27 . '67',		flatread_result => -67890,		delimitedwrite_result => '-67',		delimitedread_result => -67, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 83746,		delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -83746,		delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 90123,		delimitedwrite_result => '45678',	delimitedread_result => 45678, },
							{	flatwrite_result => '-'.'0'x24 . '45678',	flatread_result => -90123,		delimitedwrite_result => '-45678',	delimitedread_result => -45678, },
							{	flatwrite_result => '0'x25 . '12345',		flatread_result => 23456,		delimitedwrite_result => '12345',	delimitedread_result => 12345, },
							{	flatwrite_result => '-'.'0'x24 . '12345',	flatread_result => -23456,		delimitedwrite_result => '-12345',	delimitedread_result => -12345, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '-'.'0'x27 . '46',		flatread_result => -4567,		delimitedwrite_result => '-46',		delimitedread_result => -46, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '-'.'0'x27 . '68',		flatread_result => -67890,		delimitedwrite_result => '-68',		delimitedread_result => -68, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 99999,		delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -99999,		delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 99999,		delimitedwrite_result => '45679',	delimitedread_result => 45679, },
							{	flatwrite_result => '-'.'0'x24 . '45679',	flatread_result => -99999,		delimitedwrite_result => '-45679',	delimitedread_result => -45679, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 99999,		delimitedwrite_result => '99999',	delimitedread_result => 99999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -99999,		delimitedwrite_result => '-99999',	delimitedread_result => -99999, },
						],
					},
				},
				16			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-'.'0'x27 . '45',		flatread_result => -4567,		delimitedwrite_result => '-45',		delimitedread_result => -45, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '-'.'0'x27 . '67',		flatread_result => -67890,		delimitedwrite_result => '-67',		delimitedread_result => -67, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 19283746,	delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -19283746,	delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 2147483647,	delimitedwrite_result => '45678',	delimitedread_result => 45678, },
							{	flatwrite_result => '-'.'0'x24 . '45678',	flatread_result => -2147483648,	delimitedwrite_result => '-45678',	delimitedread_result => -45678, },
							{	flatwrite_result => '0'x22 . '78912345',	flatread_result => 789123456,	delimitedwrite_result => '78912345',	delimitedread_result => 78912345, },
							{	flatwrite_result => '-'.'0'x21 .'78912345',	flatread_result => -789123456,	delimitedwrite_result => '-78912345',	delimitedread_result => -78912345, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '-'.'0'x27 . '46',		flatread_result => -4567,		delimitedwrite_result => '-46',		delimitedread_result => -46, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '-'.'0'x27 . '68',		flatread_result => -67890,		delimitedwrite_result => '-68',		delimitedread_result => -68, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 19283746,	delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -19283746,	delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 2147483647,	delimitedwrite_result => '45679',	delimitedread_result => 45679, },
							{	flatwrite_result => '-'.'0'x24 . '45679',	flatread_result => -2147483648,	delimitedwrite_result => '-45679',	delimitedread_result => -45679, },
							{	flatwrite_result => '0'x22 . '78912346',	flatread_result => 789123456,	delimitedwrite_result => '78912346',	delimitedread_result => 78912346, },
							{	flatwrite_result => '-'.'0'x21 .'78912346',	flatread_result => -789123456,	delimitedwrite_result => '-78912346',	delimitedread_result => -78912346, },
						],
					},
				},
			},
			0			=> {
				# length
				5			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',			delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',			delimitedread_result => 67, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 83746,		delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 90123,		delimitedwrite_result => '45678',		delimitedread_result => 45678, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '12345',		flatread_result => 23456,		delimitedwrite_result => '12345',		delimitedread_result => 12345, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',			delimitedread_result => 46, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',			delimitedread_result => 68, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 99999,		delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 99999,		delimitedwrite_result => '45679',		delimitedread_result => 45679, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 99999,		delimitedwrite_result => '99999',		delimitedread_result => 99999, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
						],
					},
				},
				16			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',			delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',			delimitedread_result => 67, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 19283746,	delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 4294967295,	delimitedwrite_result => '45678',		delimitedread_result => 45678, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x22 . '78912345',	flatread_result => 789123456,	delimitedwrite_result => '78912345',	delimitedread_result => 78912345, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',			delimitedread_result => 46, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',			delimitedread_result => 68, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 19283746,	delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 4294967295,	delimitedwrite_result => '45679',		delimitedread_result => 45679, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x22 . '78912346',	flatread_result => 789123456,	delimitedwrite_result => '78912346',	delimitedread_result => 78912346, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
						],
					},
				},
			},
		},
		BIGINT	=> {
			# signed
			1			=> {
				# length
				5			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-'.'0'x27 . '45',		flatread_result => -4567,		delimitedwrite_result => '-45',		delimitedread_result => -45, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '-'.'0'x27 . '67',		flatread_result => -67890,		delimitedwrite_result => '-67',		delimitedread_result => -67, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 83746,		delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -83746,		delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 90123,		delimitedwrite_result => '45678',	delimitedread_result => 45678, },
							{	flatwrite_result => '-'.'0'x24 . '45678',	flatread_result => -90123,		delimitedwrite_result => '-45678',	delimitedread_result => -45678, },
							{	flatwrite_result => '0'x25 . '12345',		flatread_result => 23456,		delimitedwrite_result => '12345',	delimitedread_result => 12345, },
							{	flatwrite_result => '-'.'0'x24 . '12345',	flatread_result => -23456,		delimitedwrite_result => '-12345',	delimitedread_result => -12345, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '-'.'0'x27 . '46',		flatread_result => -4567,		delimitedwrite_result => '-46',		delimitedread_result => -46, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '-'.'0'x27 . '68',		flatread_result => -67890,		delimitedwrite_result => '-68',		delimitedread_result => -68, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 99999,		delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -99999,		delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 99999,		delimitedwrite_result => '45679',	delimitedread_result => 45679, },
							{	flatwrite_result => '-'.'0'x24 . '45679',	flatread_result => -99999,		delimitedwrite_result => '-45679',	delimitedread_result => -45679, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 99999,		delimitedwrite_result => '99999',	delimitedread_result => 99999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -99999,		delimitedwrite_result => '-99999',	delimitedread_result => -99999, },
						],
					},
				},
				16			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-'.'0'x27 . '45',		flatread_result => -4567,		delimitedwrite_result => '-45',		delimitedread_result => -45, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '-'.'0'x27 . '67',		flatread_result => -67890,		delimitedwrite_result => '-67',		delimitedread_result => -67, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 19283746,	delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -19283746,	delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 4567890123,	delimitedwrite_result => '45678',	delimitedread_result => 45678, },
							{	flatwrite_result => '-'.'0'x24 . '45678',	flatread_result => -4567890123,	delimitedwrite_result => '-45678',	delimitedread_result => -45678, },
							{	flatwrite_result => '0'x22 . '78912345',	flatread_result => 789123456,	delimitedwrite_result => '78912345',	delimitedread_result => 78912345, },
							{	flatwrite_result => '-'.'0'x21 .'78912345',	flatread_result => -789123456,	delimitedwrite_result => '-78912345',	delimitedread_result => -78912345, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '-'.'0'x27 . '46',		flatread_result => -4567,		delimitedwrite_result => '-46',		delimitedread_result => -46, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '-'.'0'x27 . '68',		flatread_result => -67890,		delimitedwrite_result => '-68',		delimitedread_result => -68, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 19283746,	delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -19283746,	delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 4567890123,	delimitedwrite_result => '45679',	delimitedread_result => 45679, },
							{	flatwrite_result => '-'.'0'x24 . '45679',	flatread_result => -4567890123,	delimitedwrite_result => '-45679',	delimitedread_result => -45679, },
							{	flatwrite_result => '0'x22 . '78912346',	flatread_result => 789123456,	delimitedwrite_result => '78912346',	delimitedread_result => 78912346, },
							{	flatwrite_result => '-'.'0'x21 .'78912346',	flatread_result => -789123456,	delimitedwrite_result => '-78912346',	delimitedread_result => -78912346, },
						],
					},
				},
			},
			0			=> {
				# length
				5			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',			delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',			delimitedread_result => 67, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 83746,		delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 90123,		delimitedwrite_result => '45678',		delimitedread_result => 45678, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '12345',		flatread_result => 23456,		delimitedwrite_result => '12345',		delimitedread_result => 12345, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',			delimitedread_result => 46, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',			delimitedread_result => 68, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 99999,		delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 99999,		delimitedwrite_result => '45679',		delimitedread_result => 45679, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 99999,		delimitedwrite_result => '99999',		delimitedread_result => 99999, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
						],
					},
				},
				16			=> {
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',			delimitedread_result => 45, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',			delimitedread_result => 67, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 19283746,	delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 4567890123,	delimitedwrite_result => '45678',		delimitedread_result => 45678, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x22 . '78912345',	flatread_result => 789123456,	delimitedwrite_result => '78912345',	delimitedread_result => 78912345, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',			delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',			delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',			delimitedread_result => 23, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',			delimitedread_result => 46, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',			delimitedread_result => 68, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 19283746,	delimitedwrite_result => '1928',		delimitedread_result => 1928, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 4567890123,	delimitedwrite_result => '45679',		delimitedread_result => 45679, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
							{	flatwrite_result => '0'x22 . '78912346',	flatread_result => 789123456,	delimitedwrite_result => '78912346',	delimitedread_result => 78912346, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0',			delimitedread_result => 0, },
						],
					},
				},
			},
		},
		DECIMAL	=> {
			# signed
			1			=> {
				# length
				5			=> {
					# decimals
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-'.'0'x27 . '45',		flatread_result => -4567,		delimitedwrite_result => '-45',		delimitedread_result => -45, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '-'.'0'x27 . '67',		flatread_result => -67890,		delimitedwrite_result => '-67',		delimitedread_result => -67, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 83746,		delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -83746,		delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 90123,		delimitedwrite_result => '45678',	delimitedread_result => 45678, },
							{	flatwrite_result => '-'.'0'x24 . '45678',	flatread_result => -90123,		delimitedwrite_result => '-45678',	delimitedread_result => -45678, },
							{	flatwrite_result => '0'x25 . '12345',		flatread_result => 23456,		delimitedwrite_result => '12345',	delimitedread_result => 12345, },
							{	flatwrite_result => '-'.'0'x24 . '12345',	flatread_result => -23456,		delimitedwrite_result => '-12345',	delimitedread_result => -12345, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '-'.'0'x27 . '46',		flatread_result => -4567,		delimitedwrite_result => '-46',		delimitedread_result => -46, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '-'.'0'x27 . '68',		flatread_result => -67890,		delimitedwrite_result => '-68',		delimitedread_result => -68, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 99999,		delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -99999,		delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 99999,		delimitedwrite_result => '45679',	delimitedread_result => 45679, },
							{	flatwrite_result => '-'.'0'x24 . '45679',	flatread_result => -99999,		delimitedwrite_result => '-45679',	delimitedread_result => -45679, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 99999,		delimitedwrite_result => '99999',	delimitedread_result => 99999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -99999,		delimitedwrite_result => '-99999',	delimitedread_result => -99999, },
						],
					},
					1			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x28 . '70',			flatread_result => 0.7,			delimitedwrite_result => '7.0',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x27 . '70',		flatread_result => -0.7,		delimitedwrite_result => '-7.0',	delimitedread_result => -7, },
							{	flatwrite_result => '0'x26 . '1230',		flatread_result => 12.3,		delimitedwrite_result => '123.0',	delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x25 . '1230',	flatread_result => -12.3,		delimitedwrite_result => '-123.0',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x27 . '234',			flatread_result => 23.4,		delimitedwrite_result => '23.4',	delimitedread_result => 23.4, },
							{	flatwrite_result => '-'.'0'x26 . '234',		flatread_result => -23.4,		delimitedwrite_result => '-23.4',	delimitedread_result => -23.4, },
							{	flatwrite_result => '0'x27 . '456',			flatread_result => 456.7,		delimitedwrite_result => '45.6',	delimitedread_result => 45.6, },
							{	flatwrite_result => '-'.'0'x26 . '456',		flatread_result => -456.7,		delimitedwrite_result => '-45.6',	delimitedread_result => -45.6, },
							{	flatwrite_result => '0'x27 . '678',			flatread_result => 6789.0,		delimitedwrite_result => '67.8',	delimitedread_result => 67.8, },
							{	flatwrite_result => '-'.'0'x26 . '678',		flatread_result => -6789.0,		delimitedwrite_result => '-67.8',	delimitedread_result => -67.8, },
							{	flatwrite_result => '0'x25 . '19283',		flatread_result => 8374.6,		delimitedwrite_result => '1928.3',	delimitedread_result => 1928.3, },
							{	flatwrite_result => '-'.'0'x24 . '19283',	flatread_result => -8374.6,		delimitedwrite_result => '-1928.3',	delimitedread_result => -1928.3, },
							{	flatwrite_result => '0'x25 . '56789',		flatread_result => 9012.3,		delimitedwrite_result => '5678.9',	delimitedread_result => 5678.9, },
							{	flatwrite_result => '-'.'0'x24 . '56789',	flatread_result => -9012.3,		delimitedwrite_result => '-5678.9',	delimitedread_result => -5678.9, },
							{	flatwrite_result => '0'x25 . '23456',		flatread_result => 2345.6,		delimitedwrite_result => '2345.6',	delimitedread_result => 2345.6, },
							{	flatwrite_result => '-'.'0'x24 .'23456',	flatread_result => -2345.6,		delimitedwrite_result => '-2345.6',	delimitedread_result => -2345.6, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x28 . '70',			flatread_result => 0.7,			delimitedwrite_result => '7.0',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x27 . '70',		flatread_result => -0.7,		delimitedwrite_result => '-7.0',	delimitedread_result => -7, },
							{	flatwrite_result => '0'x26 . '1230',		flatread_result => 12.3,		delimitedwrite_result => '123.0',	delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x25 . '1230',	flatread_result => -12.3,		delimitedwrite_result => '-123.0',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x27 . '234',			flatread_result => 23.4,		delimitedwrite_result => '23.4',	delimitedread_result => 23.4, },
							{	flatwrite_result => '-'.'0'x26 . '234',		flatread_result => -23.4,		delimitedwrite_result => '-23.4',	delimitedread_result => -23.4, },
							{	flatwrite_result => '0'x27 . '457',			flatread_result => 456.7,		delimitedwrite_result => '45.7',	delimitedread_result => 45.7, },
							{	flatwrite_result => '-'.'0'x26 . '457',		flatread_result => -456.7,		delimitedwrite_result => '-45.7',	delimitedread_result => -45.7, },
							{	flatwrite_result => '0'x27 . '679',			flatread_result => 6789.0,		delimitedwrite_result => '67.9',	delimitedread_result => 67.9, },
							{	flatwrite_result => '-'.'0'x26 . '679',		flatread_result => -6789.0,		delimitedwrite_result => '-67.9',	delimitedread_result => -67.9, },
							{	flatwrite_result => '0'x25 . '19284',		flatread_result => 9999.9,		delimitedwrite_result => '1928.4',	delimitedread_result => 1928.4, },
							{	flatwrite_result => '-'.'0'x24 . '19284',	flatread_result => -9999.9,		delimitedwrite_result => '-1928.4',	delimitedread_result => -1928.4, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9999.9,		delimitedwrite_result => '9999.9',	delimitedread_result => 9999.9, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -9999.9,		delimitedwrite_result => '-9999.9',	delimitedread_result => -9999.9, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9999.9,		delimitedwrite_result => '9999.9',	delimitedread_result => 9999.9, },
							{	flatwrite_result => '-'.'0'x24 .'99999',	flatread_result => -9999.9,		delimitedwrite_result => '-9999.9',	delimitedread_result => -9999.9, },
						],
					},
					4			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x25 . '70000',		flatread_result => 0.0007,		delimitedwrite_result => '7.0000',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x24 . '70000',	flatread_result => -0.0007,		delimitedwrite_result => '-7.0000',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x25 . '30000',		flatread_result => 0.0123,		delimitedwrite_result => '3.0000',		delimitedread_result => 3, },
							{	flatwrite_result => '-' . '0'x24 . '30000',	flatread_result => -0.0123,		delimitedwrite_result => '-3.0000',		delimitedread_result => -3, },
							{	flatwrite_result => '0'x25 . '34000',		flatread_result => 0.0234,		delimitedwrite_result => '3.4000',		delimitedread_result => 3.4, },
							{	flatwrite_result => '-'.'0'x24 . '34000',	flatread_result => -0.0234,		delimitedwrite_result => '-3.4000',		delimitedread_result => -3.4, },
							{	flatwrite_result => '0'x25 . '56700',		flatread_result => 0.4567,		delimitedwrite_result => '5.6700',		delimitedread_result => 5.67, },
							{	flatwrite_result => '-'.'0'x24 . '56700',	flatread_result => -0.4567,		delimitedwrite_result => '-5.6700',		delimitedread_result => -5.67, },
							{	flatwrite_result => '0'x25 . '78900',		flatread_result => 6.7890,		delimitedwrite_result => '7.8900',		delimitedread_result => 7.89, },
							{	flatwrite_result => '-'.'0'x24 . '78900',	flatread_result => -6.7890,		delimitedwrite_result => '-7.8900',		delimitedread_result => -7.89, },
							{	flatwrite_result => '0'x25 . '83746',		flatread_result => 8.3746,		delimitedwrite_result => '8.3746',		delimitedread_result => 8.3746, },
							{	flatwrite_result => '-'.'0'x24 . '83746',	flatread_result => -8.3746,		delimitedwrite_result => '-8.3746',		delimitedread_result => -8.3746, },
							{	flatwrite_result => '0'x25 . '89012',		flatread_result => 9.0123,		delimitedwrite_result => '8.9012',		delimitedread_result => 8.9012, },
							{	flatwrite_result => '-'.'0'x24 . '89012',	flatread_result => -9.0123,		delimitedwrite_result => '-8.9012',		delimitedread_result => -8.9012, },
							{	flatwrite_result => '0'x25 . '56000',		flatread_result => 2.3456,		delimitedwrite_result => '5.6000',		delimitedread_result => 5.6, },
							{	flatwrite_result => '-'.'0'x24 .'56000',	flatread_result => -2.3456,		delimitedwrite_result => '-5.6000',	delimitedread_result => -5.6, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x25 . '70000',		flatread_result => 0.0007,		delimitedwrite_result => '7.0000',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x24 . '70000',	flatread_result => -0.0007,		delimitedwrite_result => '-7.0000',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 0.0123,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-' . '0'x24 . '99999',	flatread_result => -0.0123,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 0.0234,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -0.0234,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 0.4567,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -0.4567,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 6.7890,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -6.7890,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9.9999,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -9.9999,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9.9999,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -9.9999,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9.9999,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-'.'0'x24 .'99999',	flatread_result => -9.9999,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
						],
					},
				},
				16			=> {
					# decimals
					4			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x25 . '70000',			flatread_result => 0.0007,			delimitedwrite_result => '7.0000',			delimitedread_result => 7, },
							{	flatwrite_result => '-'. '0'x24 .'70000',		flatread_result => -0.0007,			delimitedwrite_result => '-7.0000',			delimitedread_result => -7, },
							{	flatwrite_result => '0'x23 . '1230000',			flatread_result => 0.0123,			delimitedwrite_result => '123.0000',		delimitedread_result => 123, },
							{	flatwrite_result => '-'. '0'x22 .'1230000',		flatread_result => -0.0123,			delimitedwrite_result => '-123.0000',		delimitedread_result => -123, },
							{	flatwrite_result => '0'x24 . '234000',			flatread_result => 0.0234,			delimitedwrite_result => '23.4000',			delimitedread_result => 23.4, },
							{	flatwrite_result => '-'.'0'x23 .'234000',		flatread_result => -0.0234,			delimitedwrite_result => '-23.4000',		delimitedread_result => -23.4, },
							{	flatwrite_result => '0'x24 . '456700',			flatread_result => 0.4567,			delimitedwrite_result => '45.6700',			delimitedread_result => 45.67, },
							{	flatwrite_result => '-'.'0'x23 .'456700',		flatread_result => -0.4567,			delimitedwrite_result => '-45.6700',		delimitedread_result => -45.67, },
							{	flatwrite_result => '0'x24 . '678900',			flatread_result => 6.7890,			delimitedwrite_result => '67.8900',			delimitedread_result => 67.89, },
							{	flatwrite_result => '-'.'0'x23 .'678900',		flatread_result => -6.7890,			delimitedwrite_result => '-67.8900',		delimitedread_result => -67.89, },
							{	flatwrite_result => '0'x22 . '19283746',		flatread_result => 1928.3746,		delimitedwrite_result => '1928.3746',		delimitedread_result => 1928.3746, },
							{	flatwrite_result => '-'.'0'x21 .'19283746',		flatread_result => -1928.3746,		delimitedwrite_result => '-1928.3746',		delimitedread_result => -1928.3746, },
							{	flatwrite_result => '0'x21 . '456789012',		flatread_result => 456789.0123,		delimitedwrite_result => '45678.9012',		delimitedread_result => 45678.9012, },
							{	flatwrite_result => '-'.'0'x20 .'456789012',	flatread_result => -456789.0123,	delimitedwrite_result => '-45678.9012',		delimitedread_result => -45678.9012, },
							{	flatwrite_result => '0'x18 . '789123456000',	flatread_result => 78912.3456,		delimitedwrite_result => '78912345.6000',	delimitedread_result => 78912345.6, },
							{	flatwrite_result => '-'.'0'x17 .'789123456000',	flatread_result => -78912.3456,		delimitedwrite_result => '-78912345.6000',	delimitedread_result => -78912345.6, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x25 . '70000',			flatread_result => 0.0007,			delimitedwrite_result => '7.0000',			delimitedread_result => 7, },
							{	flatwrite_result => '-'. '0'x24 .'70000',		flatread_result => -0.0007,			delimitedwrite_result => '-7.0000',			delimitedread_result => -7, },
							{	flatwrite_result => '0'x23 . '1230000',			flatread_result => 0.0123,			delimitedwrite_result => '123.0000',		delimitedread_result => 123, },
							{	flatwrite_result => '-'. '0'x22 .'1230000',		flatread_result => -0.0123,			delimitedwrite_result => '-123.0000',		delimitedread_result => -123, },
							{	flatwrite_result => '0'x24 . '234000',			flatread_result => 0.0234,			delimitedwrite_result => '23.4000',			delimitedread_result => 23.4, },
							{	flatwrite_result => '-'.'0'x23 .'234000',		flatread_result => -0.0234,			delimitedwrite_result => '-23.4000',		delimitedread_result => -23.4, },
							{	flatwrite_result => '0'x24 . '456700',			flatread_result => 0.4567,			delimitedwrite_result => '45.6700',			delimitedread_result => 45.67, },
							{	flatwrite_result => '-'.'0'x23 .'456700',		flatread_result => -0.4567,			delimitedwrite_result => '-45.6700',		delimitedread_result => -45.67, },
							{	flatwrite_result => '0'x24 . '678900',			flatread_result => 6.7890,			delimitedwrite_result => '67.8900',			delimitedread_result => 67.89, },
							{	flatwrite_result => '-'.'0'x23 .'678900',		flatread_result => -6.7890,			delimitedwrite_result => '-67.8900',		delimitedread_result => -67.89, },
							{	flatwrite_result => '0'x22 . '19283746',		flatread_result => 1928.3746,		delimitedwrite_result => '1928.3746',		delimitedread_result => 1928.3746, },
							{	flatwrite_result => '-'.'0'x21 .'19283746',		flatread_result => -1928.3746,		delimitedwrite_result => '-1928.3746',		delimitedread_result => -1928.3746, },
							{	flatwrite_result => '0'x21 . '456789012',		flatread_result => 456789.0123,		delimitedwrite_result => '45678.9012',		delimitedread_result => 45678.9012, },
							{	flatwrite_result => '-'.'0'x20 .'456789012',	flatread_result => -456789.0123,	delimitedwrite_result => '-45678.9012',		delimitedread_result => -45678.9012, },
							{	flatwrite_result => '0'x18 . '789123456000',	flatread_result => 78912.3456,		delimitedwrite_result => '78912345.6000',	delimitedread_result => 78912345.6, },
							{	flatwrite_result => '-'.'0'x17 .'789123456000',	flatread_result => -78912.3456,		delimitedwrite_result => '-78912345.6000',	delimitedread_result => -78912345.6, },
						],
					},
				},
			},
			0			=> {
				# length
				5			=> {
					# decimals
					1			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x28 . '70',			flatread_result => 0.7,			delimitedwrite_result => '7.0',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1230',		flatread_result => 12.3,		delimitedwrite_result => '123.0',	delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '234',			flatread_result => 23.4,		delimitedwrite_result => '23.4',	delimitedread_result => 23.4, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '456',			flatread_result => 456.7,		delimitedwrite_result => '45.6',	delimitedread_result => 45.6, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '678',			flatread_result => 6789.0,		delimitedwrite_result => '67.8',	delimitedread_result => 67.8, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '19283',		flatread_result => 8374.6,		delimitedwrite_result => '1928.3',	delimitedread_result => 1928.3, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '56789',		flatread_result => 9012.3,		delimitedwrite_result => '5678.9',	delimitedread_result => 5678.9, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '23456',		flatread_result => 2345.6,		delimitedwrite_result => '2345.6',	delimitedread_result => 2345.6, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x28 . '70',			flatread_result => 0.7,			delimitedwrite_result => '7.0',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1230',		flatread_result => 12.3,		delimitedwrite_result => '123.0',	delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '234',			flatread_result => 23.4,		delimitedwrite_result => '23.4',	delimitedread_result => 23.4, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '457',			flatread_result => 456.7,		delimitedwrite_result => '45.7',	delimitedread_result => 45.7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '679',			flatread_result => 6789.0,		delimitedwrite_result => '67.9',	delimitedread_result => 67.9, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '19284',		flatread_result => 9999.9,		delimitedwrite_result => '1928.4',	delimitedread_result => 1928.4, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9999.9,		delimitedwrite_result => '9999.9',	delimitedread_result => 9999.9, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9999.9,		delimitedwrite_result => '9999.9',	delimitedread_result => 9999.9, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
						],
					},
				},
			},
		},
		FLOAT	=> {
			# signed
			1			=> {
				# length
				5			=> {
					# decimals
					0			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '45',			flatread_result => 4567,		delimitedwrite_result => '45',		delimitedread_result => 45, },
							{	flatwrite_result => '-'.'0'x27 . '45',		flatread_result => -4567,		delimitedwrite_result => '-45',		delimitedread_result => -45, },
							{	flatwrite_result => '0'x28 . '67',			flatread_result => 67890,		delimitedwrite_result => '67',		delimitedread_result => 67, },
							{	flatwrite_result => '-'.'0'x27 . '67',		flatread_result => -67890,		delimitedwrite_result => '-67',		delimitedread_result => -67, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 83746,		delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -83746,		delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45678',		flatread_result => 90123,		delimitedwrite_result => '45678',	delimitedread_result => 45678, },
							{	flatwrite_result => '-'.'0'x24 . '45678',	flatread_result => -90123,		delimitedwrite_result => '-45678',	delimitedread_result => -45678, },
							{	flatwrite_result => '0'x25 . '12345',		flatread_result => 23456,		delimitedwrite_result => '12345',	delimitedread_result => 12345, },
							{	flatwrite_result => '-'.'0'x24 . '12345',	flatread_result => -23456,		delimitedwrite_result => '-12345',	delimitedread_result => -12345, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x29 . '7',			flatread_result => 7,			delimitedwrite_result => '7',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x28 . '7',		flatread_result => -7,			delimitedwrite_result => '-7',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x27 . '123',			flatread_result => 123,			delimitedwrite_result => '123',		delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x26 . '123',		flatread_result => -123,		delimitedwrite_result => '-123',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x28 . '23',			flatread_result => 234,			delimitedwrite_result => '23',		delimitedread_result => 23, },
							{	flatwrite_result => '-'.'0'x27 . '23',		flatread_result => -234,		delimitedwrite_result => '-23',		delimitedread_result => -23, },
							{	flatwrite_result => '0'x28 . '46',			flatread_result => 4567,		delimitedwrite_result => '46',		delimitedread_result => 46, },
							{	flatwrite_result => '-'.'0'x27 . '46',		flatread_result => -4567,		delimitedwrite_result => '-46',		delimitedread_result => -46, },
							{	flatwrite_result => '0'x28 . '68',			flatread_result => 67890,		delimitedwrite_result => '68',		delimitedread_result => 68, },
							{	flatwrite_result => '-'.'0'x27 . '68',		flatread_result => -67890,		delimitedwrite_result => '-68',		delimitedread_result => -68, },
							{	flatwrite_result => '0'x26 . '1928',		flatread_result => 99999,		delimitedwrite_result => '1928',	delimitedread_result => 1928, },
							{	flatwrite_result => '-'.'0'x25 . '1928',	flatread_result => -99999,		delimitedwrite_result => '-1928',	delimitedread_result => -1928, },
							{	flatwrite_result => '0'x25 . '45679',		flatread_result => 99999,		delimitedwrite_result => '45679',	delimitedread_result => 45679, },
							{	flatwrite_result => '-'.'0'x24 . '45679',	flatread_result => -99999,		delimitedwrite_result => '-45679',	delimitedread_result => -45679, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 99999,		delimitedwrite_result => '99999',	delimitedread_result => 99999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -99999,		delimitedwrite_result => '-99999',	delimitedread_result => -99999, },
						],
					},
					1			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x28 . '70',			flatread_result => 0.7,			delimitedwrite_result => '7.0',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x27 . '70',		flatread_result => -0.7,		delimitedwrite_result => '-7.0',	delimitedread_result => -7, },
							{	flatwrite_result => '0'x26 . '1230',		flatread_result => 12.3,		delimitedwrite_result => '123.0',	delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x25 . '1230',	flatread_result => -12.3,		delimitedwrite_result => '-123.0',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x27 . '234',			flatread_result => 23.4,		delimitedwrite_result => '23.4',	delimitedread_result => 23.4, },
							{	flatwrite_result => '-'.'0'x26 . '234',		flatread_result => -23.4,		delimitedwrite_result => '-23.4',	delimitedread_result => -23.4, },
							{	flatwrite_result => '0'x27 . '456',			flatread_result => 456.7,		delimitedwrite_result => '45.6',	delimitedread_result => 45.6, },
							{	flatwrite_result => '-'.'0'x26 . '456',		flatread_result => -456.7,		delimitedwrite_result => '-45.6',	delimitedread_result => -45.6, },
							{	flatwrite_result => '0'x27 . '678',			flatread_result => 6789.0,		delimitedwrite_result => '67.8',	delimitedread_result => 67.8, },
							{	flatwrite_result => '-'.'0'x26 . '678',		flatread_result => -6789.0,		delimitedwrite_result => '-67.8',	delimitedread_result => -67.8, },
							{	flatwrite_result => '0'x25 . '19283',		flatread_result => 8374.6,		delimitedwrite_result => '1928.3',	delimitedread_result => 1928.3, },
							{	flatwrite_result => '-'.'0'x24 . '19283',	flatread_result => -8374.6,		delimitedwrite_result => '-1928.3',	delimitedread_result => -1928.3, },
							{	flatwrite_result => '0'x25 . '56789',		flatread_result => 9012.3,		delimitedwrite_result => '5678.9',	delimitedread_result => 5678.9, },
							{	flatwrite_result => '-'.'0'x24 . '56789',	flatread_result => -9012.3,		delimitedwrite_result => '-5678.9',	delimitedread_result => -5678.9, },
							{	flatwrite_result => '0'x25 . '23456',		flatread_result => 2345.6,		delimitedwrite_result => '2345.6',	delimitedread_result => 2345.6, },
							{	flatwrite_result => '-'.'0'x24 .'23456',	flatread_result => -2345.6,		delimitedwrite_result => '-2345.6',	delimitedread_result => -2345.6, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x28 . '70',			flatread_result => 0.7,			delimitedwrite_result => '7.0',		delimitedread_result => 7, },
							{	flatwrite_result => '-'.'0'x27 . '70',		flatread_result => -0.7,		delimitedwrite_result => '-7.0',	delimitedread_result => -7, },
							{	flatwrite_result => '0'x26 . '1230',		flatread_result => 12.3,		delimitedwrite_result => '123.0',	delimitedread_result => 123, },
							{	flatwrite_result => '-'.'0'x25 . '1230',	flatread_result => -12.3,		delimitedwrite_result => '-123.0',	delimitedread_result => -123, },
							{	flatwrite_result => '0'x27 . '234',			flatread_result => 23.4,		delimitedwrite_result => '23.4',	delimitedread_result => 23.4, },
							{	flatwrite_result => '-'.'0'x26 . '234',		flatread_result => -23.4,		delimitedwrite_result => '-23.4',	delimitedread_result => -23.4, },
							{	flatwrite_result => '0'x27 . '457',			flatread_result => 456.7,		delimitedwrite_result => '45.7',	delimitedread_result => 45.7, },
							{	flatwrite_result => '-'.'0'x26 . '457',		flatread_result => -456.7,		delimitedwrite_result => '-45.7',	delimitedread_result => -45.7, },
							{	flatwrite_result => '0'x27 . '679',			flatread_result => 6789.0,		delimitedwrite_result => '67.9',	delimitedread_result => 67.9, },
							{	flatwrite_result => '-'.'0'x26 . '679',		flatread_result => -6789.0,		delimitedwrite_result => '-67.9',	delimitedread_result => -67.9, },
							{	flatwrite_result => '0'x25 . '19284',		flatread_result => 9999.9,		delimitedwrite_result => '1928.4',	delimitedread_result => 1928.4, },
							{	flatwrite_result => '-'.'0'x24 . '19284',	flatread_result => -9999.9,		delimitedwrite_result => '-1928.4',	delimitedread_result => -1928.4, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9999.9,		delimitedwrite_result => '9999.9',	delimitedread_result => 9999.9, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -9999.9,		delimitedwrite_result => '-9999.9',	delimitedread_result => -9999.9, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9999.9,		delimitedwrite_result => '9999.9',	delimitedread_result => 9999.9, },
							{	flatwrite_result => '-'.'0'x24 .'99999',	flatread_result => -9999.9,		delimitedwrite_result => '-9999.9',	delimitedread_result => -9999.9, },
						],
					},
					4			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x25 . '70000',		flatread_result => 0.0007,		delimitedwrite_result => '7.0000',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x24 . '70000',	flatread_result => -0.0007,		delimitedwrite_result => '-7.0000',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x25 . '30000',		flatread_result => 0.0123,		delimitedwrite_result => '3.0000',		delimitedread_result => 3, },
							{	flatwrite_result => '-' . '0'x24 . '30000',	flatread_result => -0.0123,		delimitedwrite_result => '-3.0000',		delimitedread_result => -3, },
							{	flatwrite_result => '0'x25 . '34000',		flatread_result => 0.0234,		delimitedwrite_result => '3.4000',		delimitedread_result => 3.4, },
							{	flatwrite_result => '-'.'0'x24 . '34000',	flatread_result => -0.0234,		delimitedwrite_result => '-3.4000',		delimitedread_result => -3.4, },
							{	flatwrite_result => '0'x25 . '56700',		flatread_result => 0.4567,		delimitedwrite_result => '5.6700',		delimitedread_result => 5.67, },
							{	flatwrite_result => '-'.'0'x24 . '56700',	flatread_result => -0.4567,		delimitedwrite_result => '-5.6700',		delimitedread_result => -5.67, },
							{	flatwrite_result => '0'x25 . '78900',		flatread_result => 6.7890,		delimitedwrite_result => '7.8900',		delimitedread_result => 7.89, },
							{	flatwrite_result => '-'.'0'x24 . '78900',	flatread_result => -6.7890,		delimitedwrite_result => '-7.8900',		delimitedread_result => -7.89, },
							{	flatwrite_result => '0'x25 . '83746',		flatread_result => 8.3746,		delimitedwrite_result => '8.3746',		delimitedread_result => 8.3746, },
							{	flatwrite_result => '-'.'0'x24 . '83746',	flatread_result => -8.3746,		delimitedwrite_result => '-8.3746',		delimitedread_result => -8.3746, },
							{	flatwrite_result => '0'x25 . '89012',		flatread_result => 9.0123,		delimitedwrite_result => '8.9012',		delimitedread_result => 8.9012, },
							{	flatwrite_result => '-'.'0'x24 . '89012',	flatread_result => -9.0123,		delimitedwrite_result => '-8.9012',		delimitedread_result => -8.9012, },
							{	flatwrite_result => '0'x25 . '56000',		flatread_result => 2.3456,		delimitedwrite_result => '5.6000',		delimitedread_result => 5.6, },
							{	flatwrite_result => '-'.'0'x24 .'56000',	flatread_result => -2.3456,		delimitedwrite_result => '-5.6000',	delimitedread_result => -5.6, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x25 . '70000',		flatread_result => 0.0007,		delimitedwrite_result => '7.0000',		delimitedread_result => 7, },
							{	flatwrite_result => '-' . '0'x24 . '70000',	flatread_result => -0.0007,		delimitedwrite_result => '-7.0000',		delimitedread_result => -7, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 0.0123,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-' . '0'x24 . '99999',	flatread_result => -0.0123,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 0.0234,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -0.0234,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 0.4567,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -0.4567,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 6.7890,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -6.7890,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9.9999,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -9.9999,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9.9999,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-'.'0'x24 . '99999',	flatread_result => -9.9999,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9.9999,		delimitedwrite_result => '9.9999',		delimitedread_result => 9.9999, },
							{	flatwrite_result => '-'.'0'x24 .'99999',	flatread_result => -9.9999,		delimitedwrite_result => '-9.9999',		delimitedread_result => -9.9999, },
						],
					},
				},
				16			=> {
					# decimals
					4			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x25 . '70000',			flatread_result => 0.0007,			delimitedwrite_result => '7.0000',			delimitedread_result => 7, },
							{	flatwrite_result => '-'. '0'x24 .'70000',		flatread_result => -0.0007,			delimitedwrite_result => '-7.0000',			delimitedread_result => -7, },
							{	flatwrite_result => '0'x23 . '1230000',			flatread_result => 0.0123,			delimitedwrite_result => '123.0000',		delimitedread_result => 123, },
							{	flatwrite_result => '-'. '0'x22 .'1230000',		flatread_result => -0.0123,			delimitedwrite_result => '-123.0000',		delimitedread_result => -123, },
							{	flatwrite_result => '0'x24 . '234000',			flatread_result => 0.0234,			delimitedwrite_result => '23.4000',			delimitedread_result => 23.4, },
							{	flatwrite_result => '-'.'0'x23 .'234000',		flatread_result => -0.0234,			delimitedwrite_result => '-23.4000',		delimitedread_result => -23.4, },
							{	flatwrite_result => '0'x24 . '456700',			flatread_result => 0.4567,			delimitedwrite_result => '45.6700',			delimitedread_result => 45.67, },
							{	flatwrite_result => '-'.'0'x23 .'456700',		flatread_result => -0.4567,			delimitedwrite_result => '-45.6700',		delimitedread_result => -45.67, },
							{	flatwrite_result => '0'x24 . '678900',			flatread_result => 6.7890,			delimitedwrite_result => '67.8900',			delimitedread_result => 67.89, },
							{	flatwrite_result => '-'.'0'x23 .'678900',		flatread_result => -6.7890,			delimitedwrite_result => '-67.8900',		delimitedread_result => -67.89, },
							{	flatwrite_result => '0'x22 . '19283746',		flatread_result => 1928.3746,		delimitedwrite_result => '1928.3746',		delimitedread_result => 1928.3746, },
							{	flatwrite_result => '-'.'0'x21 .'19283746',		flatread_result => -1928.3746,		delimitedwrite_result => '-1928.3746',		delimitedread_result => -1928.3746, },
							{	flatwrite_result => '0'x21 . '456789012',		flatread_result => 456789.0123,		delimitedwrite_result => '45678.9012',		delimitedread_result => 45678.9012, },
							{	flatwrite_result => '-'.'0'x20 .'456789012',	flatread_result => -456789.0123,	delimitedwrite_result => '-45678.9012',		delimitedread_result => -45678.9012, },
							{	flatwrite_result => '0'x18 . '789123456000',	flatread_result => 78912.3456,		delimitedwrite_result => '78912345.6000',	delimitedread_result => 78912345.6, },
							{	flatwrite_result => '-'.'0'x17 .'789123456000',	flatread_result => -78912.3456,		delimitedwrite_result => '-78912345.6000',	delimitedread_result => -78912345.6, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x25 . '70000',			flatread_result => 0.0007,			delimitedwrite_result => '7.0000',			delimitedread_result => 7, },
							{	flatwrite_result => '-'. '0'x24 .'70000',		flatread_result => -0.0007,			delimitedwrite_result => '-7.0000',			delimitedread_result => -7, },
							{	flatwrite_result => '0'x23 . '1230000',			flatread_result => 0.0123,			delimitedwrite_result => '123.0000',		delimitedread_result => 123, },
							{	flatwrite_result => '-'. '0'x22 .'1230000',		flatread_result => -0.0123,			delimitedwrite_result => '-123.0000',		delimitedread_result => -123, },
							{	flatwrite_result => '0'x24 . '234000',			flatread_result => 0.0234,			delimitedwrite_result => '23.4000',			delimitedread_result => 23.4, },
							{	flatwrite_result => '-'.'0'x23 .'234000',		flatread_result => -0.0234,			delimitedwrite_result => '-23.4000',		delimitedread_result => -23.4, },
							{	flatwrite_result => '0'x24 . '456700',			flatread_result => 0.4567,			delimitedwrite_result => '45.6700',			delimitedread_result => 45.67, },
							{	flatwrite_result => '-'.'0'x23 .'456700',		flatread_result => -0.4567,			delimitedwrite_result => '-45.6700',		delimitedread_result => -45.67, },
							{	flatwrite_result => '0'x24 . '678900',			flatread_result => 6.7890,			delimitedwrite_result => '67.8900',			delimitedread_result => 67.89, },
							{	flatwrite_result => '-'.'0'x23 .'678900',		flatread_result => -6.7890,			delimitedwrite_result => '-67.8900',		delimitedread_result => -67.89, },
							{	flatwrite_result => '0'x22 . '19283746',		flatread_result => 1928.3746,		delimitedwrite_result => '1928.3746',		delimitedread_result => 1928.3746, },
							{	flatwrite_result => '-'.'0'x21 .'19283746',		flatread_result => -1928.3746,		delimitedwrite_result => '-1928.3746',		delimitedread_result => -1928.3746, },
							{	flatwrite_result => '0'x21 . '456789012',		flatread_result => 456789.0123,		delimitedwrite_result => '45678.9012',		delimitedread_result => 45678.9012, },
							{	flatwrite_result => '-'.'0'x20 .'456789012',	flatread_result => -456789.0123,	delimitedwrite_result => '-45678.9012',		delimitedread_result => -45678.9012, },
							{	flatwrite_result => '0'x18 . '789123456000',	flatread_result => 78912.3456,		delimitedwrite_result => '78912345.6000',	delimitedread_result => 78912345.6, },
							{	flatwrite_result => '-'.'0'x17 .'789123456000',	flatread_result => -78912.3456,		delimitedwrite_result => '-78912345.6000',	delimitedread_result => -78912345.6, },
						],
					},
				},
			},
			0		=> {
				# length
				5			=> {
					# decimals
					1			=> {
						$OVERFLOW_METHOD_TRUNC	=> [
							{	flatwrite_result => '0'x28 . '70',			flatread_result => 0.7,			delimitedwrite_result => '7.0',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1230',		flatread_result => 12.3,		delimitedwrite_result => '123.0',	delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '234',			flatread_result => 23.4,		delimitedwrite_result => '23.4',	delimitedread_result => 23.4, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '456',			flatread_result => 456.7,		delimitedwrite_result => '45.6',	delimitedread_result => 45.6, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '678',			flatread_result => 6789.0,		delimitedwrite_result => '67.8',	delimitedread_result => 67.8, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '19283',		flatread_result => 8374.6,		delimitedwrite_result => '1928.3',	delimitedread_result => 1928.3, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '56789',		flatread_result => 9012.3,		delimitedwrite_result => '5678.9',	delimitedread_result => 5678.9, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '23456',		flatread_result => 2345.6,		delimitedwrite_result => '2345.6',	delimitedread_result => 2345.6, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
						],
						$OVERFLOW_METHOD_ROUND	=> [
							{	flatwrite_result => '0'x28 . '70',			flatread_result => 0.7,			delimitedwrite_result => '7.0',		delimitedread_result => 7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x26 . '1230',		flatread_result => 12.3,		delimitedwrite_result => '123.0',	delimitedread_result => 123, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '234',			flatread_result => 23.4,		delimitedwrite_result => '23.4',	delimitedread_result => 23.4, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '457',			flatread_result => 456.7,		delimitedwrite_result => '45.7',	delimitedread_result => 45.7, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x27 . '679',			flatread_result => 6789.0,		delimitedwrite_result => '67.9',	delimitedread_result => 67.9, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '19284',		flatread_result => 9999.9,		delimitedwrite_result => '1928.4',	delimitedread_result => 1928.4, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9999.9,		delimitedwrite_result => '9999.9',	delimitedread_result => 9999.9, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
							{	flatwrite_result => '0'x25 . '99999',		flatread_result => 9999.9,		delimitedwrite_result => '9999.9',	delimitedread_result => 9999.9, },
							{	flatwrite_result => '0'x30,					flatread_result => 0,			delimitedwrite_result => '0.0',		delimitedread_result => 0, },
						],
					},
				},
			},
		},
	},
};

# Execution of single tests
if ($test_single) {
	foreach my $datatype (keys %{$hr_testvalues_results->{results}}) {
		$hr_interface_config->{Fields}->{testfield1}->{datatype} = $datatype;
		foreach my $signed (keys %{$hr_testvalues_results->{results}->{$datatype}}) {
			$hr_interface_config->{Fields}->{testfield1}->{signed} = $signed;
			foreach my $length (keys %{$hr_testvalues_results->{results}->{$datatype}->{$signed}}) {
				$hr_interface_config->{Fields}->{testfield1}->{length} = $length;
				foreach my $decimals (keys %{$hr_testvalues_results->{results}->{$datatype}->{$signed}->{$length}}) {
					$hr_interface_config->{Fields}->{testfield1}->{decimals} = $decimals;
					foreach my $overflow_method (keys %{$hr_testvalues_results->{results}->{$datatype}->{$signed}->{$length}->{$decimals}}) {
						$interface->overflow_method($overflow_method);
						ok( $interface->ReConfigureFromHash($hr_interface_config),	'ReConfigureFromHash');
						ok( $interface->Check(),									'Interface self-check');
						is( $interface->datatype->[0], $datatype,					'Get column type');
						is( $interface->signed->[0], $signed,						'Get column signedness');
						is( $interface->length->[0], $length,						'Get column length');
						is( $interface->decimals->[0], $decimals,					'Get column decimals');
						ok(
							$interface->DelimitedFile_ConfigureUseInFile($interface->displayname),
							'DelimitedFile_ConfigureUseInFile'
						);
						my $ar_results = $hr_testvalues_results->{results}->{$datatype}->{$signed}->{$length}->{$decimals}->{$overflow_method};
						print("Rounding method [" . $overflow_method . "]\n");
						foreach my $index (0 .. $#{$hr_testvalues_results->{testvalues}}) {
							my $hr_testvalue = $hr_testvalues_results->{testvalues}->[$index];
							my $hr_results = $ar_results->[$index];
							# Direct tests (value in, value out)
							# DelimitedFile (write, read)
							is(
								$interface->DelimitedFile_WriteRecord( { testfield1 => $hr_testvalue->{regular} } ),
								$hr_results->{delimitedwrite_result},
								"DelimitedFile_WriteRecord for [$datatype], [$signed], [$length], [$decimals] with value [" . $hr_testvalue->{regular} . "] -> [" . $hr_results->{delimitedwrite_result} . ']',
							);
							cmp_ok(
								$interface->DelimitedFile_ReadRecord($hr_testvalue->{delimited})->{testfield1}, '==',
								$hr_results->{delimitedread_result},
								"DelimitedFile_ReadRecord for [$datatype], [$signed], [$length], [$decimals] with value [" . $hr_testvalue->{delimited} . "] -> [" . $hr_results->{delimitedread_result} . "]",
							);
							# FlatFile (write, read)
							is(
							$interface->FlatFile_WriteRecord( { testfield1 => $hr_testvalue->{regular} } ),
								$hr_results->{flatwrite_result},
								"FlatFile_WriteRecord for [$datatype], [$signed], [$length], [$decimals] with value [" . $hr_testvalue->{regular} . "] -> [" . $hr_results->{flatwrite_result} . ']',
							);
							cmp_ok(
								$interface->FlatFile_ReadRecord($hr_testvalue->{flat})->{testfield1}, '==', 
								$hr_results->{flatread_result},
								"FlatFile_ReadRecord for [$datatype], [$signed], [$length], [$decimals] with value [" . $hr_testvalue->{flat} . "] -> [" . $hr_results->{flatread_result} . "]",
							);
							# XMLFile (write)
							is(
							$interface->XMLFile_WriteRecord( { testfield1 => $hr_testvalue->{regular} } ),
								"\t<item>\n\t\t<testfield1>" . $hr_results->{delimitedwrite_result} . "</testfield1>\n\t</item>\n",
								"XMLFile_WriteRecord for [$datatype], [$signed], [$length], [$decimals] with value [" . $hr_testvalue->{regular} . "] -> [" . '<item>' . $hr_testvalue->{delimitedwrite_result} . '</item>' . ']',
							);
							
							$interface->{default}->[0] = $hr_testvalue->{regular};
							# Default value write tests (nothing in, default out)
							$interface->write_defaultvalues(1);
							is(
								$interface->DelimitedFile_WriteRecord( { testfield1 => undef } ),
								$hr_results->{delimitedwrite_result},
								"Default DelimitedFile_WriteRecord for [$datatype], [$signed], [$length], [$decimals] with no value but default [" . $hr_testvalue->{regular} . "] -> [" . $hr_results->{delimitedwrite_result} . ']',
							);
							is(
							$interface->FlatFile_WriteRecord( { testfield1 => undef } ),
								$hr_results->{flatwrite_result},
								"Default FlatFile_WriteRecord for [$datatype], [$signed], [$length], [$decimals] with no value but default [" . $hr_testvalue->{regular} . "] -> [" . $hr_results->{flatwrite_result} . ']',
							);
							# Default value write tests (nothing in, nothing out)
							$interface->write_defaultvalues(0);
							is(
								$interface->DelimitedFile_WriteRecord( { testfield1 => undef } ),
								'0' . ($decimals ? '.' . '0' x $decimals : ''),
								"NoDefault DelimitedFile_WriteRecord for [$datatype], [$signed], [$length], [$decimals] with no value but default [" . $hr_testvalue->{regular} . "] -> [" . $hr_results->{delimitedwrite_result} . ']',
							);
							is(
							$interface->FlatFile_WriteRecord( { testfield1 => undef } ),
								'0' x $interface->{flatfield_length}->[0],
								"NoDefault FlatFile_WriteRecord for [$datatype], [$signed], [$length], [$decimals] with no value but default [" . $hr_testvalue->{regular} . "] -> [" . $hr_results->{flatwrite_result} . ']',
							);
							# Default value read tests (nothing in, default out)
							$interface->read_defaultvalues(1);
							$interface->{default}->[0] = $hr_results->{delimitedread_result};
							cmp_ok(
								$interface->DelimitedFile_ReadRecord('')->{testfield1}, '==',
								$hr_results->{delimitedread_result},
								"Default DelimitedFile_ReadRecord for [$datatype], [$signed], [$length], [$decimals] with no value [" . "] -> [" . $hr_results->{delimitedread_result} . "]",
							);
							$interface->{default}->[0] = $hr_results->{flatread_result};
							cmp_ok(
								$interface->FlatFile_ReadRecord(' ' x $interface->{flatfield_length}->[0])->{testfield1}, '==', 
								$hr_results->{flatread_result},
								"Default FlatFile_ReadRecord for [$datatype], [$signed], [$length], [$decimals] with value [" . $hr_testvalue->{flat} . "] -> [" . $hr_results->{flatread_result} . "]",
							);
						}
					}
				}
			}
		}
	}
}
	
my ($ar_data, $error);

# Test IO from delimited file
if (-e $hr_testfiles->{delimited}) {
	$interface->ClearConfig;
	$interface->AddField( { fieldname => 'quote_date', displayname => 'QUOTE DATE', datatype => 'DATE', length => 12, useinfile => 'Y' } );
	$interface->AddField( { fieldname => 'price', displayname => 'PRICE', datatype => 'DECIMAL', length => 4, decimals => 3, useinfile => 'Y' } );
	$interface->AddField( { fieldname => 'unknown', displayname => 'UNKNOWN', datatype => 'INTEGER', useinfile => 'Y', signed => 'N' } );
	$interface->AddField( { fieldname => 'ask', displayname => 'ASK', datatype => 'DECIMAL', length => 4, decimals => 3, useinfile => 'Y' } );
	$interface->AddField( { fieldname => 'ask_size', displayname => 'ASK SIZE', datatype => 'INTEGER', signed => 'N', useinfile => 'Y' } );
	$interface->AddField( { fieldname => 'bid', displayname => 'BID', datatype => 'DECIMAL', length => 4, decimals => 3, useinfile => 'Y' } );
	$interface->AddField( { fieldname => 'bid_size', displayname => 'BID SIZE', datatype => 'INTEGER', useinfile => 'Y', signed => 'N' } );
	$interface->DelimitedFile_ConfigureUseInFile($interface->displayname);
	$interface->record_delimiter("\n");
	try {
		$ar_data = $interface->DelimitedFile_ReadData($hr_testfiles->{delimited}, { no_header => 1 });
	} catch {
		$error = $_;
		Data::Dump::dd($_);
	};

	ok(!defined $error, 'DelimitedFile: Read data');
	is(@{$ar_data}, 4070, 'DelimitedFile: 4070 Records read');
	# A few record tests:
	is_deeply( { quote_date => "2011-01-03 11:03:00", price => 0.575, unknown => 261844, ask => 0.610, ask_size => 2500, bid => 0.570, bid_size => 2500 }, $ar_data->[41], 'Record 41 data validity');
	is_deeply( { quote_date => "2011-01-04 09:30:00", price => 0.580, unknown => 2500, ask => 0.000, ask_size => 0, bid => 0.000, bid_size => 0 }, $ar_data->[144], 'Record 144 data validity');
	is_deeply( { quote_date => "2011-02-23 14:37:00", price => 0.440, unknown => 111281, ask => 2.200, ask_size => 500, bid => 0.200, bid_size => 5000 }, $ar_data->[1269], 'Record 1269 data validity');
} else {
	print("Testfile for delimited data [$hr_testfiles->{delimited}] does not exist, tests skipped\n");
}

# Test IO from Flat files
if (-e $hr_testfiles->{flat}) {
	$interface->ClearConfig;
	# Add fields here
	$interface->Check();
	try {
		$ar_data = $interface->FlatFile_ReadData($hr_testfiles->{flat});
	} catch {
		$error = $_;
		Data::Dump::dd($_);
	};
	
	ok(!defined $error, 'FlatFile: Read data');
	is(@{$ar_data}, 1000, 'FlatFile: 1000 Records read');
	# A few record tests:
} else {
	print("Testfile for flat data [$hr_testfiles->{flat}] does not exist, tests skipped\n");
}

# Test IO from ExcelBinary files
if (-e $hr_testfiles->{xls}) {
	$interface->ClearConfig;
	# Add fields here
	$interface->Check();
	try {
		$ar_data = $interface->ExcelBinary_ReadData($hr_testfiles->{xls}, { worksheet_id => 1 } );
	} catch {
		$error = $_;
		Data::Dump::dd($_);
	};

	ok(!defined $error, 'XLS Binary: Read data');
	is(@{$ar_data}, 5137, 'XLS Binary: 5137 Records read');
	# A few record tests:
} else {
	print("Testfile for Excel binary (xls) data [$hr_testfiles->{xls}] does not exist, tests skipped\n");
}

# Test IO from ExcelX files
if (-e $hr_testfiles->{flat}) {
	$interface->ClearConfig;
	# Add fields here
	$interface->Check();
	$interface->ExcelX_ConfigureUseInFile($interface->displayname);
	try {
		$ar_data = $interface->ExcelX_ReadData($hr_testfiles->{xlsx}, { worksheet_id => 0 } );
	} catch {
		$error = $_;
		Data::Dump::dd($_);
	};

	ok(!defined $error, 'XLSX: Read data');
	is(@{$ar_data}, 58034, 'XLSX: 58034 Records read');
	# A few record tests:
} else {
	print("Testfile for ExcelXML (xlsx) data [$hr_testfiles->{xlsx}] does not exist, tests skipped\n");
}

# IO from MySQL database

# IO from SQLServer database

done_testing();
