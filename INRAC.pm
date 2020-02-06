##############################################################################
# INRAC brain, object implementation.
##############################################################################
package INRAC;
# TODO: eliminate version dependency
use v5.010;
use warnings;
use strict;

use autodie;

use Carp;
use File::Basename;

##############################################################################
# DEBUG
##############################################################################
use Term::ANSIColor;
use Data::Dumper;
# Module-wide debug switch
my $debug = 0;

# Debug print when module-wide debug enabled
sub _d { print STDERR @_, "\n" if $debug }

##############################################################################
# STATIC HELPER FUNCTIONS
##############################################################################
# Choose one item at random from a list

# TODO: use and store RNG state from parent object
sub _pick { return $_[rand @_] }

# Checks if item 1 matches item 2
#  item 1 matches if shorter than 2
#  also, ? is a wildcard in item 1
# TODO: add & for * wildcard
# TODO: test
sub _match
{
  my ($pattern, $item) = @_;

  my $pat_len = length $pattern;
  return 0 if length $item < $pat_len;

  for my $i ( 0 .. $pat_len - 1 )
  {
    my $char = substr($pattern, $i, 1);
    next if $char eq '?';
    return 0 if $char ne substr($item, $i, 1);
  }

  return 1;
}

##############################################################################
# MEMBER FUNCTIONS
##############################################################################

# Retrieve a variable (or '' if unset)
# TODO: perform token expansion ?
sub _get_var {
  #my $self = shift;
  #my $token = shift;

  #while ($token =~ m/\$(\d+)/) {
    #my $value = $self->{variable}[$1] // '';
    #$token =~ s/\$$1/$value/;
  #}
  #return $token;
  return $_[0]->{variable}[$_[1]] // '';
}

# Lookup and return frame pointing to random sub
# TODO: validate
sub _call_glob
{
  my $self = shift;
  my $pattern = shift;

  if ($pattern =~ m/^(\d+)(\D+)$/)
  {
    confess "Attempt to peek unknown section $1" unless $self->{code}[$1];

# Use glob to find matches for labels
    my @labels = grep { _match($2, $_) } keys %{$self->{code}[$1]{label}};
    confess "No matches to label $2 in section $1" unless @labels;

# choose a line from selected label and return
    return { section => $1, line => _pick(@{$self->{code}[$1]{label}{_pick(@labels)}}) };
  } else {
    confess "Pattern $pattern found no matches.";
  }
}

# TODO: unimplemented
# Expand out all * from a line
sub _expand
{
  my $self = shift;

  ...;

#return shift;

=pod
    my @words = split /\s/, shift;

  say "pre expand: " . join('|',@words);
  map {
    if (substr($_,0,1) eq '*') {
      my $target = $self->_call_glob(substr($_,1));
      $_ = $self->_expand(@{$self->{code}[$target->{section}]{lines}[$target->{line}]});
    }
  } @words;
say "post expand: " . join('|',@words);

  return join ' ', @words;
=cut
}

# Reads a data file, adds contents to self hash.
sub _read_data_file
{
  my ($self, $datafile) = @_;

  # Safe-ish line read plus trim
  my $_eat = sub {
    my $fh = shift;
    confess "Short read on filehandle!" unless defined(my $line = <$fh>);
    $line =~ s/^\s+//g;
    $line =~ s/\s+$//g;
    return $line;
  };

  _d(colored("OPENING $datafile...", 'bold green'));
  open my $fh, '<:crlf', $datafile;

  # Read header lines
  my $file_header = $_eat->($fh);
  my $file_sec_start = $_eat->($fh) + 0;
  my $file_sec_count = $_eat->($fh) + 0;
  my $file_line_count = $_eat->($fh) + 0;

  _d("> HEADER: '$file_header', $file_line_count lines, $file_sec_count sect (begin $file_sec_start)");

  # Read section definitions
  my @sec_defs;
  for my $section_number ($file_sec_start .. $file_sec_start + $file_sec_count - 1)
  {
    my $section_header = $_eat->($fh);
    # TODO: determine meaning of "type" value
    my $section_type = $_eat->($fh) + 0;
    my $section_line_count = $_eat->($fh) + 0;

    # TODO: the meaning of ALPH and UNIQ in section header is unknown
    my $is_alph = ($section_header =~ m/ALPH/);
    my $is_uniq = ($section_header =~ m/UNIQ/);

    # Push section info into array.
    push @sec_defs, {
      header => $section_header,
      is_alph => $is_alph,
      is_uniq => $is_uniq,
      number => $section_number,
      type => $section_type,
      line_count => $section_line_count
    };

    #_d(">> SECTION $section_number: '$section_header', $section_line_count lines, $section_type type");
  }

  # Got our section definitions. Process lines per section.
  foreach my $sec (@sec_defs)
  {
    # Check for existing section
    #  (sometimes sections called "link" are placeholders unloaded by subsequent scripts)
    #_d(colored("Duplicate entry for $sec->{number}, overwriting", 'yellow')) if $self->{code}[$sec->{number}];

    # store header info (for debug)
    $self->{code}[$sec->{number}]{file_name} = $datafile;
    $self->{code}[$sec->{number}]{file_header} = $file_header;
    $self->{code}[$sec->{number}]{section_header} = $sec->{header};
    $self->{code}[$sec->{number}]{type} = $sec->{type};

    $self->{code}[$sec->{number}]{line} = [];
    $self->{code}[$sec->{number}]{label} = {};
    for (my $idx = 0; $idx < $sec->{line_count}; $idx ++)
    {
      my $line = $_eat->($fh);

      # tokenize and push
      my @tokens = split(/\s+/,$line);

      # Sections contain a list of Lines (strip first Line Label off)
      my $label = shift @tokens;
      #  Need a pointer to previously pushed line too
      my $pushed_line_num = push @{$self->{code}[$sec->{number}]{line}}, \@tokens;
      # Labels stored here which point to Lines above.
      push @{$self->{code}[$sec->{number}]{label}{$label}}, $pushed_line_num - 1;
    }

    #_d(">> Section $sec->{number}: Processed " . scalar @{$self->{code}[$sec->{number}]{line}} . " lines, " . scalar(keys %{$self->{code}[$sec->{number}]{label}}) . " distinct labels.");
  }
}

# Iteratively process until we run out of opcodes.
sub _execute
{
  my ($self, $section, $line, $depth, $exec_type, @code_buffer) = @_;
  #my ($self, $section, $line, $depth, @code_buffer) = @_;

  # Split first and rest off a token
  my $_split = sub {
    my $first = substr($_[0],0,1);
    my $rest = (length($_[0]) > 1 ? substr($_[0],1) : '');
    return ($first, $rest);
  };

  _d("\t" x $depth,
    #colored("_execute(sec=$section, line=$line, buf=[" . join(' ', @code_buffer) . '])', 'bold blue'));
    colored("_execute(sec=$section, line=$line, exec_type=$exec_type, buf=[" . join(' ', @code_buffer) . '])', 'bold blue'));

  # Contains the local output of this sub.
  #  Generally ignored, but it is useful if called with exec_type = 1
  my $local_output = '';

  # Output mods
  # TODO: These are lost when recursing and should possibly be Global
  my %mods = ( NO_SPACE => 1 );

  #for (my $idx = 0; $idx < scalar @code_buffer; $idx ++)
  while (@code_buffer)
  {
    # Retrieve next opcode from the queue
    #my $token = $code_buffer[$idx];
    my $token = shift @code_buffer;

    # debug
    _d("->\t" x $depth, $token);

=pod
    #$token = $self->_get_var($token);
    elsif ($first eq '$')
      # GET IV: retrieves a variable and returns its value.
      #  TODO: Variables retrieved may contain more variables, needs actual parsing.
      #$self->{output} .= ($self->_expand($self->_get_var($rest)) . ' ');
      my $val = $self->_get_var($rest);
      $self->{output} .= ($val . ' ');
    _d("\t" x ($depth + 1), colored(" ($token)", 'blue'));
=cut

    # process opcode here
    my ($first, $rest) = $_split->($token);

    #####################################
    # Conditional execution: process or skip token depending on set/unset flag
    if ($first eq '/') {
      # "Execute if condition SET"
      if ($self->{condition}) {
        ($first, $rest) = $_split->($rest);
        _d("\t" x ($depth + 1), colored(' (taken)', 'green'));
      } else {
        _d("\t" x ($depth + 1), colored(' (skipped)', 'red'));
        next;
      }
    } elsif ($first eq '\\') {
      # "Execute if condition UNSET"
      if (!$self->{condition}) {
        ($first, $rest) = $_split->($rest);
        _d("\t" x ($depth + 1), colored(' (taken)', 'green'));
      } else {
        _d("\t" x ($depth + 1), colored(' (skipped)', 'red'));
        next;
      }
    }

    #####################################
    # MASTER DECODE METHOD - Process current "opcode", perform actions.
    #####################################
    # Special-Case Functions
    if ($first eq '?' && $rest eq '?') {
      # TRIGGER USER INPUT CALLBACK
      # Read user input into var1
      # TODO: major work around parsing user input
      my $input = $self->{callback}->($self->{output});
      $self->{variable}[1] = $input;

      # Clean up input
      $self->{input_words} = [];

      my @words = split /\s+/, $input;
      foreach my $word (@words)
      {
        if ($word =~ m/^(.+)([.,!?])$/) {
          push @{$self->{input_words}}, $1, $2;
        } else {
          push @{$self->{input_words}}, $word;
        }
      }

      $self->{input_ptr} = 0;

      # reset output before continuing
      $self->{output} = '';
      %mods = ( NO_SPACE => 1 );

    } elsif ($first eq ':') {
      # OTHER SUPERVISOR FUNCTION
      #  File manip
      if ($rest =~ m/^LOAD(.+)/) {
        if (defined $self->{callback_load}) {
          # Trigger load callback, if defined.  Callback should return a sparsearray of
          #  variables, loaded from filename.
          my @loaded_iv = $self->{callback_load}->($1);
          # merge - Variables set in file overwrite internal vars.
          map { $self->{variable}[$_] = $loaded_iv[$_] if defined $loaded_iv[$_] } ( 1 .. @loaded_iv - 1 );
        }
      } elsif ($rest =~ m/^PUT(.+)/) {
        # Trigger save callback, if defined.  Callback should dump all set variables to disk.
        $self->{callback_put}->($1,@{$self->{variable}}) if defined $self->{callback_put};
      } elsif ($rest =~ m/^OUT(.+)/) {
        # Trigger log callback, if defined.  Callback should open whatever output file handles are needed.
        $self->{callback_out}->($1) if defined $self->{callback_out};
      } elsif ($rest eq 'ZAP') {
        # Erase internal data store - clears only items 10+ from variable list, so preserve 1-9.
        splice @{$self->{variable}}, 10;
      }
      #  Move input (word) opcode pointer
      elsif ($rest =~ m/^F/) {
        if ($rest =~ m/^F=(\d+)$/) { $self->{input_ptr} = $1;
        } elsif ($rest =~ m/^F\+(\d+)$/) { $self->{input_ptr} += $1;
        } elsif ($rest =~ m/^F-(\d+)$/) { $self->{input_ptr} -= $1;
        } elsif ($rest eq 'F=E') { $self->{input_ptr} = scalar @{$self->{input_words}}- 1;
        } else { confess "Unimplemented special-function '$rest'"; ... }

        _d("\t" x ($depth + 1), colored(" (F=$self->{input_ptr})", 'yellow'));
      }
      #  Unknown.
      elsif ($rest =~ m/T/) { carp "Unknown special-function 'T', unimp"; }
      else { confess "Unimplemented special-function '$rest'"; ... }
    } elsif ($first eq '%') {
      # LOAD SCRIPT FILE
      $self->_read_data_file($self->{data_dir} . '/' . $rest . '.RAC');
    #####################################
    # VARIABLE MANIP
    } elsif ($first eq '>') {
      # SET IV: sets an internal variable
      if ($rest =~ m/^(\d+)([*=])(.*)$/) {
        my $dest = $1;
        my $right = $3 // '';

        my $val;
        if ($2 eq '*') {
          # random call -
          # TODO: needs significant testing
          my $target = $self->_call_glob($right);

          # execute sub and STORE (no print!) result
          $val = $self->_execute( $target->{section}, $target->{line}, $depth + 1, 1,
            @{$self->{code}[$target->{section}]{line}[$target->{line}]}
          );
        } else {
          # TODO: can this be made more clear?

          # This is char-by-char parsing for assignment.
          #  Digits found are replaced with their variable.
          # HOWEVER, things in double-quotes are copied as-is.
          my @rhs = split /(")/, $right;

          $val = '';
          my $in_quote = 0;
          foreach my $piece (@rhs) {
            if ($piece eq '"') {
              $in_quote = !$in_quote;
            } else {
              if ($in_quote) {
                # Quoted content copied verbatim!
                $val .= $piece;
              } else {
                # Number to variable substitution
                $piece =~ s/(\d+)/$self->_get_var($1)/ge;

                # comma to space
                $piece =~ s/,/ /g;
                $val .= $piece;
              }
            }
          }

          # TODO: test these other functions: can they be combined?
          if ($val eq 'F') { $val = $self->{input_words}[$self->{input_ptr}]; }
          elsif ($val eq 'L') { $val = join(' ', @{$self->{input_words}}[0 .. ($self->{input_ptr} - 1)]); }
          elsif ($val eq 'R') { my $end = scalar @{$self->{input_words}} - 1; $val = join(' ', @{$self->{input_words}}[($self->{input_ptr} + 1) .. $end]); }
          #elsif ($val eq 'C') { $val = ucfirst($val); }
          # TODO: this is meant to catch unknown tokens for now
          elsif (length($val) == 1 && $val ne 'I') { ... }
        }

        # set final var
        _d("\t" x ($depth + 1), colored(" ($dest=$val)", 'green'));
        $self->{variable}[$dest] = $val;
      } else { confess "Malformed SET-token $first (full cmd: '$token')"; }
    #####################################
    # CONDITION TESTING
    } elsif ($first eq '?' && $rest ne '') {
      # ? is crazily overloaded

      # invert match flag if prefaced with -:
      my $invert = 0;
      if ($rest =~ m/^(-:)(.*)/)
      {
        $invert = 1;
        $rest = $2;
      }

      # Perform comparisons, set result in $result
      my $result = 0;
      if ($rest =~ m/^(\d+)=(.*)/) {
        # compare register to string
        my $comp = $2 // '';
        $result = ($self->_get_var($1) eq $comp);
      } elsif ( $rest =~ m/^([A-Z]+)([+-])?(\d)?/ ) {
        # Special test functions.
        #  Many of these support an "offset" to move the F ptr relative
        my $offset = 0;
        if ($2 && $3) {
          if ($2 eq '+') { $offset = $3 }
          elsif ($2 eq '-') { $offset = -$3 }
        }

        # Get the word pointed at
        my $f = $self->{input_words}[$self->{input_ptr}] // '';

        if ($1 eq 'CAP') {
          # Check if word is capitalized.
          $result = ($f eq ucfirst($f));
        } elsif ($1 eq 'PUNC') {
          # Check if word is punctuation
          $result = ($f =~ m/[.?!,]$/);
        } elsif ($1 eq 'Q') {
          # Check if sentence ends in a question mark
          #  This is a whole-sentence test and does not use offsets
          $result = ($self->_get_var(1) =~ m/\?$/);
        } else {
          confess "Malformed TEST-token $first (full cmd: '$token')";
        }
      } else {
        # Iteratively search input_line for a match, beginning from the
        #  current opcode.  If found, set the condition code, and advance
        #  opcode ptr.
        my @search_items = split /,/, $rest;

        for (my $i = 0; $i < scalar @{$self->{input_words}}; $i ++)
        {
          # normalizes a substring (remove punct, lowercase)
          my $input_word = lc($self->{input_words}[$i]);
          # TODO: verify this is the correct patterns
          #$input_word =~ s/[^a-z0-9']//g;

          if (grep {$input_word eq $_} @search_items)
          {
            # It is a match.
            $self->{input_ptr} = $i;
            $result = 1;
            last;
          }
        }
        # confess "Malformed TEST-token $first (full cmd: '$token')";
      }
      $self->{condition} = ($result xor $invert);
      if ($self->{condition}) {
        _d("\t" x ($depth + 1), colored(' (condition flag SET)', 'green'));
      } else {
        _d("\t" x ($depth + 1), colored(' (condition flag UNSET)', 'red'));
      }

    ####################################
    # FLOW CONTROL
    } elsif ($first eq '*') {
      # GOSUB

      if ($rest eq '') {
        # RETURN: pop stack frame, return
        return $local_output;
      } else {
        my $target = $self->_call_glob($rest);

        # push a new stack frame
        # execute sub and return
        $self->_execute( $target->{section}, $target->{line}, $depth + 1, $exec_type,
          @{$self->{code}[$target->{section}]{line}[$target->{line}]}
        );
      }
    } elsif ($first eq '#') {
      # JUMP

      if ($rest eq '')
      {
        # Advance to next line
        $line ++;
        @code_buffer = @{$self->{code}[$section]{line}[$line]};
      } elsif ($rest eq '#') {
        # Refill the code buffer from same line again
        @code_buffer = @{$self->{code}[$section]{line}[$line]};
      } elsif ($rest eq 'RND') {
        # Advance opcode-ptr to a random position somewhere in this line.
        my $skip = _pick(0 .. scalar @code_buffer);
        for (0 .. $skip) { shift @code_buffer }

      } elsif ($rest =~ m/^\*(.+)$/) {
        # jump to label
        my $target = $self->_call_glob($1);

        $section = $target->{section};
        $line = $target->{line};

        # TODO: could be error if jumping outside existing code
        @code_buffer = @{$self->{code}[$section]{line}[$line]};
      } else {
        confess "Malformed JUMP token: $rest";
      }

    #####################################
    # OUTPUT / PRINTING
    } elsif ($token eq 'C') {
      # Output modifier: capitalize next word
      $mods{TO_UPPER} = 1;
    } elsif ($token eq 'D') {
      # Output modifier: DEcapitalize next word
      $mods{TO_LOWER} = 1;
    } else {
      # LITERAL: apply any modifiers, and append / print
      my $final = '';

      # substitute all numbers with variable reps
      $token =~ s/\$(\d+)/$self->_get_var($1)/ge;

      if ($first eq '<') {
        # Delete preceding space.
        $mods{NO_SPACE} = 1;
        $token = $rest;
      } elsif ($first =~ m/^[.!?,]$/) {
        # Singular punct. characters need to remove preceding space too
        $mods{NO_SPACE} = 1;
      }

      # Output without trailing space if token ends with >
      my $skip_trailing_space;
      if ($token =~ m/^(.+)>$/) {
        $skip_trailing_space = 1;
        $token = $1;
      }

      # Output leading space, unless modifier list prevents it
      if (! $mods{NO_SPACE}) {
        $final .= ' ';
      }

      # Append the substring.  Apply any mods.
      if ($mods{TO_UPPER}) {
        $final .= ucfirst($token);
      } elsif ($mods{TO_LOWER} && lc($token) ne 'i') {
        $final .= lcfirst($token);
      } else {
        $final .= $token;
      }

      # Correct double-spacing after sentence endings
      # TODO: verify behavior of this against space-deleting tokens
      if ($token =~ m/[.!?]$/) {
        $final .= ' ';
      }

      # All done.  Reset the modifier hash.
      %mods = ();
      if ($skip_trailing_space) {
        $mods{NO_SPACE} = 1;
      }

      #if ($exec_type) {
        $local_output .= $final;
      if (! $exec_type) {
        $self->{output} .= $final;
      }
    }
  }

  return $local_output;
}


##############################################################################
# PUBLIC METHODS
##############################################################################
# Constructor
#  (accepts one optional parameter to change the data dir)
sub new
{
  my $class = shift;

  my $args_ref = shift;

  # switch global debug flag
  $debug = $args_ref->{debug} // 0;

  _d('Constructing new INRAC object: ' . Dumper($args_ref));

  my $file = $args_ref->{file} or confess "No base input file specified";
  my $callback = $args_ref->{callback} or confess "No input callback specified";

  # Initial empty class
  my $self = bless {
    # Register a callback function to process input
    callback => $callback,

    # Save, load, and log callbacks
    callback_put => $args_ref->{callback_put},
    callback_load => $args_ref->{callback_load},
    callback_out => $args_ref->{callback_out},

    # Filesystem interaction
    data_dir => dirname($file),

    # Script in use (fill by _read_data_file)
    code => [],

    # Internal RAM storage
    variable => [],
    # Conditional result register
    condition => 0,

    # Index to char in variable1 (user input)
    input_ptr => 0,
    input_words => [],

    # Output buffer
    output => '',
  }, $class;

  # read first datafile
  $self->_read_data_file($file);

  # return object
  return $self;
}

# Kicks off the INRAC parser
#  This runs until script termination
#  Callback will fire when ?? is read from script
sub run
{
  my ($self, $initial_script) = @_;

  # Execute from default starting position
  $self->_execute( 0, 0, 0, 0, $initial_script );
}

1;
