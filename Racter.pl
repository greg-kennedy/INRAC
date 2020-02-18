#!/usr/bin/env perl
###############################################################################
# Racter.pl
#  Greg Kennedy, 2020
# Driver program for playing Racter (MS-DOS) data files
###############################################################################

###############################################################################
# INCLUDES
###############################################################################
use strict;
use warnings;
use autodie;

# fudge @INC
use FindBin qw( $RealBin );
use lib $RealBin;

# INRAC parser / tool
use INRAC;

###############################################################################
# GLOBALS
###############################################################################
# racter object
my $racter;

# file handle for log printout
my $log_handle;

###############################################################################
# CALLBACKS
###############################################################################
# input() called whenever the module needs input from the user.
sub input {

  # retrieve the latest words from engine
  my $output = shift;

  # print to stdout
  print $output, "\n";

  # also log chat
  print $log_handle $output, "\n";

  # Get user input and return from callback
  my $ret;
  do {
    print '>';
    my $input = <STDIN>;
    chomp($input);

    # DEBUG COMMANDS
    if ( $input eq 'D' ) {

      # dump object
      use Data::Dumper;
      print Dumper($racter);
    } elsif ( $input eq 'IV' ) {

      # dump current state
      my @var = @{ $racter->{variable} };

      printf( "Condition flag: [%s]\n",
        ( $racter->{condition} ? 'TRUE' : 'FALSE' ) );
      printf( "Input pointer (F): %d => [%s]\n",
        $racter->{input_ptr},
        ( split /\s+/, $var[1] )[ $racter->{input_ptr} - 1 ] );

      # dump variable table
      for ( my $i = 1; $i < scalar @var; $i++ ) {
        if ( $var[$i] ) {
          printf( "%02d: [%s]\n", $i, $var[$i] );
        }
      }
    } elsif ( $input eq 'C' ) {

      # dump script
      for ( my $i = 0; $i < scalar @{ $racter->{code} }; $i++ ) {
        if ( $racter->{code}[$i] ) {
          my %section = %{ $racter->{code}[$i] };
          my @labels  = @{ $section{label} };
          my @lines   = @{ $section{line} };

          printf(
            "== %02d: [%s] (type: %d, labels: %d, lines: %d) ==\n",
            $i, $section{section_header},
            $section{type},
            scalar @labels,
            scalar @lines
          );
          printf( "- source: [%s] (%s) -\n",
            $section{file_name}, $section{file_header} );
          for ( my $j = 0; $j < scalar @lines; $j++ ) {
            print "\t$labels[$j]\t" . join( ' ', @{ $lines[$j] } ) . "\n";
          }
        }
      }
    } else {

      # log user input
      print $log_handle '>', $input, "\n";

      # pass input back to module
      $ret = $input;
    }
  } while (!$ret);

  return $ret;
}

# put() called when module wants to save variables to disk
sub put {
  my ( $filename, @variables ) = @_;
  $filename .= '.C';

  open my $fh, '>', $filename;
  for ( my $i = 1; $i < scalar @variables; $i++ ) {
    if ( $variables[$i] ) {
      printf $fh ( "%2d %s\n", $i, $variables[$i] );
    }
  }
  close $fh;
}

# load() called when module wants to read variables from disk
sub load {
  my $filename = shift;
  $filename .= '.C';

  # Load variables from disk (return a list)
  my @variables;
  if (-e $filename) {
    open my $fh, '<:crlf', $filename;
    while ( my $line = <$fh> ) {
      if ( $line =~ m/^([ \d]\d) (.+)[\r\n]*$/ ) {
        $variables[$1] = $2;
      } else {
        print STDERR
          "Error in load($filename): did not understand line '$line'\n";
      }
    }
    close $fh;
  }

  return @variables;
}

# out() called when module wants to initialize log device
sub out {

  # Callback to open output device for logging.
  #  The usefulness of this is questionable, since you basically
  #  have to do the logging yourself anyway.
  # It may be interesting to write to printer or TTS device.
  my $filename = shift;
  $filename .= '.OUT';

  open $log_handle, '>', $filename;
}

###############################################################################
# MAIN PROGRAM
###############################################################################
# boilerplate
print "A CONVERSATION WITH RACTER\n";

# create a new INRAC object, using base RACTER datafile
$racter = INRAC->new(
  { file          => 'data/IV.RAC',
    callback      => \&input,
    callback_put  => \&put,
    callback_load => \&load,
    callback_out  => \&out,
    debug         => 1
  }
);

# run until script is over
print $racter->run('*1A') . "\n";

# close log handle if opened
if ($log_handle) { close $log_handle }
