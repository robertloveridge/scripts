#!/usr/bin/env perl

use strict;
use warnings;

use DBI;
use Carp;
use Readonly;
use File::Temp;
use File::stat;
use Archive::Zip;
use Text::CSV_XS;
use Getopt::Long;

Readonly my $MAX_FILE_SIZE => 2000; # 2000 bytes
my $db_name = q{chinook.db};
my $sql = q{SELECT * FROM employees};
my $output_path = q{/Users/rob/Documents};
my $output_name = q{employees};

GetOptions (
  "db_name=s" => \$db_name,
  "sql=s" => \$sql,
  "output_path=s" => \$output_path,
  "output_name=s" => \$output_name)
  or die("Error in command line arguments\n");

# only allow SELECT statements
croak "Not a SELECT: '$sql'" unless ( $sql =~ m{ ^ [ ]* SELECT }ixms );

my $dsn = sprintf("dbi:SQLite:dbname=%s",$db_name);

# no username or password set
my $dbh = DBI->connect($dsn, q{}, q{}, { RaiseError => 1 })
   or die $DBI::errstr;

my $csv = Text::CSV_XS->new({
 binary 	=> 1,
 eol 	=> "\r\n",
});

my $current_fh;
my $counter = 0;

my $results = $dbh->prepare($sql);
$results->execute;

while (my $result = $results->fetchrow_arrayref) {

    # create new temp file if not defined
    $current_fh //= File::Temp->new;

    # get the statistics on our file such as its size
    my $stat = stat( $current_fh->filename );

    # if we're over our max size, zip it and reset the fh
    if ( $stat->size > $MAX_FILE_SIZE ) {
        zip_file($current_fh);
        $current_fh = undef;
    }
    else {
        # if the file is available but with no data, then we need headers
        if ($stat->size == 0){
            my @headers = @{$results->{NAME}};
            $csv->print( $current_fh, \@headers);
        }

        # it's not over our limit, so write some data!
        $csv->print( $current_fh, \@{$result} );
        $current_fh->flush;
    }
}

# we finished the loop now write the last file to a zip
if (defined $current_fh && stat($current_fh->filename)->size) {
    zip_file($current_fh);
}

$dbh->disconnect;

sub zip_file {
    my $current_fh = shift;
    my $zip_path = $output_path . q{/} . sprintf($output_name . q{_%04d.zip}, $counter);
    my $csv_name = sprintf($output_name . q{_%04d.csv}, $counter);

    # increase our counter for unique file names
    $counter++;

    my $zip = Archive::Zip->new();
    $zip->addFile($current_fh->filename, $csv_name);
    $zip->writeToFileNamed($zip_path);
}

exit();
