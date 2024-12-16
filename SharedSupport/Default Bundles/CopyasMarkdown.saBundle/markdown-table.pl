# Print Selected Result rows as a markdown table

use v5.10.0;
use strict;
use warnings;
use utf8;
use open qw(:std :utf8);

# read all input, split by tabs and store as 2-dimensional array
my @lines = ();
my @colWidths = ();
while (my $rowData = <>) {
	chomp($rowData);
	my @cols = split(/\t/, $rowData);
	foreach my $i (0 .. $#cols) {
		my $oldW = $colWidths[$i] // 2; # let cols be minimum 2 chars wide
		my $newW = length($cols[$i] // '');
		$colWidths[$i] = $newW > $oldW ? $newW : $oldW;
	}
	push(@lines, [@cols]);
}

exit(0) unless ($#lines > 0); # expecting at least header and one data row.


# subroutine that prints an array as a markdown table row
# first argument is filler (space for data and header rows, "-" for the separator)
sub row {
	my $filler = shift;
	my @cols = @_; # read remaining args

	print "|";
	foreach my $i (0 .. $#cols) {
		print $cols[$i], $filler x ($colWidths[$i] - length($cols[$i])), "|";
	}
	print "\n";
}


# output header, separator and datalines
my $firstline = shift @lines;
row(" ", @$firstline);
row("-", map {"-"} @$firstline);

foreach my $line (@lines) {
	row(" ", @$line);
}

