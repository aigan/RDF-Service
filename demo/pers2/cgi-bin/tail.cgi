#!/usr/bin/perl -wT
use strict;

use lib "../../../lib";
use RDF::Service;

my $version = $RDF::Service::VERSION;
$version =~ s/\./_/;

$|=1;

print "Content-type: text/html\n\n";

$ENV{'PATH'} = "";
!$ENV{'QUERY_STRING'} or
  $ENV{'QUERY_STRING'} =~ m/(\d+)/ or die;

my $row = $1 || 1;

print <<"EOT;";
<?xml version="1.0" encoding="iso-8859-1"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "dtd/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
  <head>
    <title>
      Wraf $version log
    </title>
  </head>
  <body>
    <h1>tail -n $row RDF-Service-$version.log</h1>
    <pre>
EOT;

open FILE, "/usr/bin/tail -n $row /tmp/RDF-Service-$version.log |" or die $!;
while( my $row = <FILE> )
{
    $row =~ s/&/&amp;/g;
    $row =~ s/</&lt;/g;
    print $row;
}

print "</pre></body></html>\n";


