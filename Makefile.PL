# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

BEGIN { require 5.006 }
use ExtUtils::MakeMaker;

WriteMakefile(
	      'NAME'	=> 'RDF::Service',
	      'PMLIBDIRS'    => [ 'lib' ],
 	      'VERSION_FROM' => 'lib/RDF/Service.pm', # finds $VERSION
#	      'HTMLLIBPODS' => 'doc/pod/RDF/Service.pod',
#	      'INSTALLHTMLSITELIBDIR' => 'doc/html/api',
#	      'INST_HTMLLIBDIR' => 'doc/html/api',
	      'AUTHOR' => 'Jonas Liljegren <jonas@paranormal.se>',
	      'ABSTRACT' => 'RDF API with DBI and other backends',
 	      'PREREQ_PM'     =>
	      {
		  'DBI'          => 1,
		  'URI'          => 0,
		  'Time::HiRes'  => 0,
		  'Template'     => 2,
		  'CGI'          => 0,
		  'IO::Socket'   => 1.18,
		  'Data::Dumper' => 0,
		  'FreezeThaw'   => 0,
	          'Time::Object' => 0,
	      },
	      'dist'          =>
	      {
		  'COMPRESS' => 'gzip',
		  'SUFFIX'   => 'gz',
	      }
);
