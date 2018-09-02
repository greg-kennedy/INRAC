#!/usr/bin/env perl
use v5.012;
use warnings;

# fudge @INC
use FindBin qw( $RealBin );
use lib $RealBin;

# INRAC parser / tool
use INRAC;

# racter object
my $racter;
# file handle for log printout
my $log_handle;

# Callback subroutine, which is executed any time the engine
#  needs input from the user.
sub input
{
  # retrieve the latest words from engine
  my $output = shift;

  # print to stdout
  say $output;
  # also log chat
  say $log_handle $output;

  # Get user input and return from callback
  print '>';
  my $input = <STDIN>;
  chomp($input);

  # log user input
  say $log_handle ">$input";

  return $input;
}

# Save variables to disk
sub put
{
  my $filename = shift . '.C';
  my @variables = @{+shift};

  if (open my $fh, '>', $filename)
  {
    for my $i (1 .. @variables - 1)
    {
      if (($variables[$i] // '') ne '')
      {
        printf $fh ("%2d %s\n",$i,$variables[$i]);
      }
    }
  } else {
    say STDERR "ERROR: Unable to write to file $filename: $!";
  }
}

# Load variables from disk (return a list)
sub load
{
  my $filename = shift . '.C';

  my @variables;
  if (open my $fh, '<', $filename)
  {
    while (my $line = <$fh>)
    {
      if ($line =~ m/^([ \d]\d) (.+)[\r\n]*$/)
      {
        $variables[$1] = $2;
      } else {
        say STDERR "Error in load: did not understand line $line";
      }
    }
  } else {
    say STDERR "ERROR: Unable to read from file $filename: $!";
  }

  @variables;
}

sub out
{
  # Callback to open output device for logging.
  #  The usefulness of this is questionable, since you basically
  #  have to do the logging yourself anyway.
  my $filename = shift;
  $filename .= '.OUT';
  open $log_handle, '>', $filename or die "Unable to open logfile $filename: $!\n";
}

# boilerplate
say 'A CONVERSATION WITH RACTER';

# create a new INRAC object, using base RACTER datafile
$racter = new INRAC( { file => 'data/IV.RAC',
                       callback => \&input,
                       callback_put => \&put,
                       callback_load => \&load,
                       callback_out => \&out,
                       debug => 1 } );

# run until script is over
$racter->run;
