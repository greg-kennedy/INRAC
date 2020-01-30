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
  while(1) {
    print '>';
    my $input = <STDIN>;
    chomp($input);
  
    # debug
    if ($input eq 'D') {
      # dump object
      use Data::Dumper;
      say Dumper($racter)
    } elsif ($input eq 'IV') { 
      # dump variable table
      for (my $i = 0; $i < scalar @{$racter->{variable}}; $i ++)
      {
        if ($racter->{variable}[$i]) {
	  printf("%02d: [%s]\n", $i, $racter->{variable}[$i]);
	}
      }
    } elsif ($input eq 'C') {
      # dump script
      for (my $i = 0; $i < scalar @{$racter->{code}}; $i ++)
      {
        if ($racter->{code}[$i]) {
	  my %section = %{$racter->{code}[$i]};
	  my %labels = %{$section{label}};
	  my @lines = @{$section{line}};

	  printf("== %02d: [%s] (type: %d, labels: %d, lines: %d) ==\n", $i, $section{section_header},
	    $section{type}, scalar keys %labels, scalar @lines);
	  printf("- source: [%s] (%s) -\n", $section{file_name}, $section{file_header});
	  for (my $line = 0; $line < scalar @lines; $line ++)
	  {
	    # reattach label to line
	    use List::Util qw(first);
	    my $label;
	    foreach my $test_label (keys %labels) {
	      if (defined first { $line == $_ } @{$labels{$test_label}}) {
	        $label = $test_label;
	      }
	    }
	    print "\t$label\t" . join(' ', @{$lines[$line]}) . "\n";
	  }
	}
      }
    }
    else {
  
      # log user input
      say $log_handle ">$input";
  
      return $input;
    }
  }
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
  # It may be interesting to write to printer or TTS device.
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
$racter->run("*1A");
