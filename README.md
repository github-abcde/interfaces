Perl Interfaces module. A dynamically extendable module that can interface with various file/database-readers and writers.
Currently implemented:
  - Fixed width files (Flat files)
  - Delimited files (RFC 4180 compliant)
  - XLS files
  - XLSX files
  - MySQL tables
Partly implemented:
  - XML
  - JSON

Currently uses the following Perl modules (haven't separated debugging and release builds yet):
- Data::Dump
- Try::Tiny
- Moose
- Smart::Comments
- MooseX::Method::Signatures
- Readonly
- Spreadsheet::ParseExcel::S?tream
- Spreadsheet::Xlsx
- Excel::Writer::xlsx
- XML::Twig
- JSON
