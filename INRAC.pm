##########################################################
# INRAC brain, object implementation.
package INRAC;
use v5.012;
use warnings;

use Carp;
use File::Basename;

##########################################################
# DEBUG
use Data::Dumper;
# Module-wide debug switch
my $debug = 0;

# Debug print when module-wide debug enabled
sub _d { say STDERR @_ if $debug; }

##########################################################
# STATIC HELPER FUNCTIONS
# Choose one item at random from a list
sub _pick { $_[int rand @_]; }

# normalizes a substring (remove punct, lowercase)
sub _norm
{
  my $str = shift // '';
  $str =~ s/[^A-Za-z0-9']//g;
  lc($str);
}

# Safe-ish line read plus chomp
sub _eat
{
  my $fh = shift;
  confess "Short read on filehandle!" unless defined(my $line = <$fh>);
  $line =~ s/[\r\n]+$//g;
  return $line;
}

# Checks if item 1 matches item 2
#  item 1 matches if shorter than 2
#  also, ? is a wildcard in item 1
sub _match
{
  my $pattern = shift;
  my $item = shift;

  my $pat_len = length $pattern;
  return 0 if length $item < $pat_len;

  for my $i ( 0 .. $pat_len - 1 )
  {
    my $char = substr($pattern, $i, 1);
    next if $char eq '?';
    return 0 if $char ne substr($item, $i, 1);
  }

  1;
}

# Prunes a list of items to just wildcard matches
sub _glob
{
  my $pattern = shift;

  my @matches;
  map { push @matches, $_ if _match($pattern, $_) } @_;
  @matches;
}

# Return a list containing the indexes of the start point of each word
sub _word_points
{
  my $sentence = shift;

  my @word_starts;

  my $prev_char_ws = 1;
  for my $i (0 .. length $sentence - 1)
  {
    my $char = substr $sentence,$i,1;
    if ($prev_char_ws && $char =~ m/\S/)
    {
      # prev char was whitespace, push into array if this isn't
      push @word_starts, $i;
      $prev_char_ws = 0;
    } elsif (!$prev_char_ws && $char =~ m/\s/) {
      # prev char not whitespace, set flag if it now is
      $prev_char_ws = 1;
    }
  }

  return @word_starts;
}

sub _get_word
{
  my $sentence = shift;
  my $word_num = shift;

  # skip N words
  my $word = '';

  my $current_word = 0;
  my $prev_char_ws = 1;
  for my $i (0 .. length $sentence - 1)
  {
    # save character
    my $char = substr $sentence,$i,1;
    if ($prev_char_ws && $char ne ' ')
    {
      # prev char was whitespace, this isn't
      $prev_char_ws = 1;
      #  grow the word if this is the right one
      $word .= $char if ($current_word == $word_num);
    } elsif (!$prev_char_ws && $char eq ' ') {
      # prev char not whitespace, set flag if it now is
      $prev_char_ws = 0;
      return $word if ($current_word == $word_num);
      $current_word ++;
    }
  }

  return $word;
}

sub _get_rest
{
  my $sentence = shift;
  my $word_num = shift;

  my $current_word = 0;
  my $prev_char_ws = 1;
  for my $i (0 .. length $sentence - 1)
  {
    # save character
    my $char = substr $sentence,$i,1;
    if ($prev_char_ws && $char ne ' ')
    {
      # prev char was whitespace, this isn't
      $prev_char_ws = 1;
      #  grow the word if this is the right one
    } elsif (!$prev_char_ws && $char eq ' ') {
      # prev char not whitespace, set flag if it now is
      $prev_char_ws = 0;
      return substr($sentence,$i) if ($current_word == $word_num);
      $current_word ++;
    }
  }

  return '';
}

##########################################################
# MEMBER FUNCTIONS

# Lookup and return frame pointing to random sub
sub _call_glob
{
  my $self = shift;
  my $pattern = shift;

  if ($pattern =~ m/^(\d+)(\D+)$/)
  {
    confess "Attempt to peek unknown section $1" unless exists $self->{script}{$1};

    # Use glob to find matches for labels
    my @labels = _glob($2, keys %{$self->{script}{$1}{label}});
    confess "No matches to label $2 in section $1" unless @labels;

    # choose a line from selected label and return
    return { section => $1, line => _pick(@{$self->{script}{$1}{label}{_pick(@labels)}}) };
  } else {
    confess "Pattern $pattern found no matches.";
  }
}

# Expand out all * from a line
sub _expand
{
  my $self = shift;
return shift;

  my @words = split /\s/, shift;

say "pre expand: " . join('|',@words);
  map {
    if (substr($_,0,1) eq '*') {
      my $target = $self->_call_glob(substr($_,1));
      $_ = $self->_expand(@{$self->{script}{$target->{section}}{lines}[$target->{line}]});
    }
  } @words;
say "post expand: " . join('|',@words);

  return join ' ', @words;
}

# Reads a data file, adds contents to self hash.
sub _read_data_file
{
  my $self = shift;
  my $datafile = shift;

  _d("OPENING $datafile...");
  if (open my $fh, '<', $datafile)
  {
    # Read header lines
    my $file_header = _eat($fh);
    my $file_sec_start = _eat($fh) + 0; # basically unused though
    my $file_sec_count = _eat($fh) + 0;
    my $file_line_count = _eat($fh) + 0;

    _d("> HEADER: '$file_header', $file_line_count lines, $file_sec_count sect (begin $file_sec_start)");

    # Read section definitions
    my @sec_defs;
    for my $section (0 .. $file_sec_count - 1)
    {
      my $section_header = _eat($fh);
      my $section_unknown = _eat($fh) + 0; # unknown
      my $section_line_count = _eat($fh) + 0;

      # Verify section_header seems reasonable
      if ($section_header =~ m/(SEC|SECTION) (\d+)(?: (.*))?/)
      {
        # "SECTION" defines a Code block, "SEC" is Vocab
        #my $type = ($1 eq 'SECTION' ? 'code' : 'word');
        # Push section info into array.
        push @sec_defs, {
          #type => $type,
          number => $2,
          #unknown => $section_unknown,
          line_count => $section_line_count
        };
        _d(">> SECTION $2: '" . ($3 || '<unnamed>') . "', $section_line_count lines, $section_unknown (unknown)");
      } else {
        confess "Malformed section header: '$section_header'\n";
      }
    }

    # Got our section definitions. Process lines per section.
    foreach my $sec (@sec_defs)
    {
      # Check for existing section
      _d("Duplicate entry for " . $sec->{number} . ", extending") if (exists $self->{script}{$sec->{number}});

      # autovivify leads to undef concat so...
      $self->{script}{$sec->{number}}{line} //= [];
      $self->{script}{$sec->{number}}{label} //= {};
    
      for (my $idx = 0; $idx < $sec->{line_count}; $idx ++)
      {
        my $line = _eat($fh);

        # tokenize and push
        my @opcodes = split(/\s+/,$line);

        # Sections contain a list of Lines (strip first Line Label off)
        #  Need a pointer to previously pushed line too
        my $pushed_line_num = push @{$self->{script}{$sec->{number}}{line}}, [@opcodes[1 .. $#opcodes]];
        # Labels stored here which point to Lines above.
        push(@{$self->{script}{$sec->{number}}{label}{$opcodes[0]}}, $pushed_line_num - 1);
      }
      _d('>> Section ' . $sec->{number} . ": Processed " . scalar @{$self->{script}{$sec->{number}}{line}} . " lines, " . scalar(keys %{$self->{script}{$sec->{number}}{label}}) . " label.");
    }
  } else {
    confess "Failed opening datafile $datafile: $!\n";
  }
}

# Retrieve a variable (or '' if unset)
sub _get_var { $_[0]->{variable}[$_[1]] // ''; }

# MASTER DECODE METHOD - Process current "opcode", perform actions.
sub _decode
{
  my $self = shift;
  my $frame_ref = shift;

  my $command = shift;

  my $firstchar = substr($command,0,1);
  my $rest = (length($command) > 1 ? substr($command,1) : '');

  #####################################
  # Special-Case Functions
  if ($command eq '??') {
    # TRIGGER USER INPUT CALLBACK
    # Read user input into var1
    $self->{variable}[1] = $self->{callback}->($self->{output});

    # Clean up input
    $self->{variable}[1] =~ s/\s/ /g;
    $self->{input_ptr} = 0;

    # Call helper function to set up index ptrs to words
    #$self->{input_words} = _word_points($self->{variable}[1]);

    # reset output before continuing
    $self->{output} = '';
  } elsif ($firstchar eq ':') { 
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
      $self->{callback_put}->($1,$self->{variable}) if defined $self->{callback_put};
    } elsif ($rest =~ m/^OUT(.+)/) {
      # Trigger log callback, if defined.  Callback should open whatever output file handles are needed.
      $self->{callback_out}->($1) if defined $self->{callback_out};
    } elsif ($rest eq 'ZAP') {
      # Erase internal data store - clears only items 10+ from variable list, so preserve 1-9.
      @{$self->{variable}} = splice (@{$self->{variable}},1,10);
    }
    #  Move input (word) opcode pointer
    elsif ($rest =~ m/^F=(\d+)$/) { $self->{input_ptr} = $1; }
    elsif ($rest =~ m/^F\+(\d+)$/) { $self->{input_ptr} += $1; }
    elsif ($rest =~ m/^F-(\d+)$/) { $self->{input_ptr} -= $1; }
    elsif ($rest eq 'F=E') {
      $self->{input_ptr} = split(/\s+/, $self->_get_var(1))- 1;
    }
    #  Unknown.
    #elsif ($rest =~ m/T/) { carp "Unknown special-function 'T', unimp"; }
    else { confess "Unimplemented special-function '$rest'"; }
  } elsif ($firstchar eq '%') {
    # LOAD SCRIPT FILE
    $self->_read_data_file($self->{data_dir} . '/' . $rest . '.RAC');
  #####################################
  # VARIABLE MANIP
  } elsif ($firstchar eq '$') {
    # GET IV: retrieves a variable and returns its value.
    #  TODO: Variables retrieved may contain more variables, needs actual parsing.
    #$self->{output} .= ($self->_expand($self->_get_var($rest)) . ' ');
    $self->{output} .= ($self->_get_var($rest) . ' ');
  } elsif ($firstchar eq '>') {
    # SET IV: sets an internal variable
    if ($rest =~ m/(\d+)([*=])(.*)/) {
      my $right = $3;
      if ($2 eq '*') {
        # random call - 
     die "unimp";
        $right = $self->_expand('*' . $3);
      }
      my @rhs = split /,/, $right;
      my $val = '';

      while (my $mod = pop @rhs)
      {
        if ($mod eq 'F') { $val = _get_word($self->_get_var(1),$self->{input_ptr}); }
        elsif ($mod =~ m/^\d+$/) { $val = $self->_get_var($mod); }
        elsif ($mod eq 'R') { $val = _get_rest($self->_get_var(1),$self->{input_ptr} + 1); }
        elsif ($mod eq 'C') { $val = ucfirst($val); }
        else { $val .= $mod; } #confess "Unknown modifier $mod in SET-command (full cmd: '$command')"; }
      }
      # set final var
      $self->{variable}[$1] = $val;
    } else { confess "Malformed SET-command $firstchar (full cmd: '$command')"; }
  #####################################
  # CONDITION TESTING
  } elsif ($firstchar eq '?' && $rest ne '') {
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
      if ($1 eq 'CAP') {
        my $f = $self->_get_word($self->_get_var(1),$self->{input_ptr});
#_d("Special case $1: ($f eq " . ucfirst($f) . "): " . ($f eq ucfirst($f)));
        #$result = ($f eq ucfirst($f));
      } elsif ($1 eq 'Q') {
        $result = ($self->{input} =~ m/\?$/);
      } elsif ($1 eq 'PUNC') {
        my $f = $self->_retrieve_f;
        $result = ($f =~ m/[.?]$/);
      } else {
        confess "Malformed TEST-command $firstchar (full cmd: '$command')";
      }
    } else {
      # Iteratively search input_line for a match, beginning from the
      #  current opcode.  If found, set the condition code, and advance
      #  opcode ptr.

      for my $term (split /,/, $rest)
      {
        my $pos = index(lc($self->_get_var(1)),$term);
        if ($pos >= 0)
        {
          $self->{input_ptr} = $pos;
          $result = 1;
          last;
        }
      }

      # Put search terms into a hash for faster lookup
      my %search_items;
      @search_items{split /,/, $rest} = ();

      for my $i (0 .. @{$self->{input_line}} - 1)
      {
#        if (exists $search_items{_norm($self->{input_line}[$i])})
#        {
#          # It is a match.
#          $self->{input_opcode} = $i;
#          $result = 1;
#          last;
#        }
      }
      # confess "Malformed TEST-command $firstchar (full cmd: '$command')";
    }
    $self->{condition} = ($result xor $invert);
  #####################################
  # FLOW CONTROL
  } elsif ($firstchar eq '*') {
    # GOSUB
    if ($rest eq '') {
      # return: pop stack frame, return
      return 1;
    } else {
      my $target = $self->_call_glob($rest);

      # push a new stack frame
      # execute sub and return
      $self->_execute( { section => $target->{section}, line => $target->{line}, opcode => 0, depth => $frame_ref->{depth} + 1 } );
    }
  } elsif ($firstchar eq '/') {
    # "Execute if condition SET"
    if ($self->{condition}) { $self->_decode($frame_ref,$rest); }
  } elsif ($firstchar eq '\\') {
    # "Execute if condition UNSET"
    if (!$self->{condition}) { $self->_decode($frame_ref,$rest); }
  } elsif ($firstchar eq '#') {
    # JUMP
    #  (always resets active_opcode...)
    $frame_ref->{opcode} = 0;

    if ($rest eq '')
    {
      $frame_ref->{line} ++;
    } elsif ($rest eq '#') {
      # Do nothing: jump back to same line
    } elsif ($rest eq 'RND') {
      # Advance opcode-ptr to a random position somewhere in this line.
      $frame_ref->{opcode} += int rand (@{$self->{script}{$frame_ref->{section}}{line}[$frame_ref->{line}]} - $frame_ref->{opcode});
    } elsif ($rest =~ m/^\*(.+)$/) {
      my $target = $self->_call_glob($1);

      # jump to label
      $frame_ref->{section} = $target->{section};
      $frame_ref->{line} = $target->{line};
    } else {
      confess "Malformed JUMP command: $rest";
    }

  #####################################
  # OUTPUT / PRINTING
  } elsif ($firstchar eq '<') {
    # This appears to "delete" the previous char.
    chop $self->{output}; #= substr($self->{output},0,-1);
    $self->_decode($frame_ref,$rest);
  } else {
    if ($firstchar =~ m/^[.!?,]$/) {
      # Singular punct. characters need to remove preceding space
      chop $self->{output};
    }
    # Append this opcode and a trailing space
    $self->{output} .= ($command . ' ');

    # Correct double-spacing after sentence endings
    #  The original probably flushes the buffer here too
    $self->{output} .= ' ' if $self->{output} =~ m/[.!?] $/;
  }

  0;
}

# Iteratively process until we run out of opcodes.
sub _execute
{
  my $self = shift;

  # call stack
  my %frame = %{+shift};

  # Retrieve current opcode
  while (my $opcode = $self->{script}{$frame{section}}{line}[$frame{line}][$frame{opcode}])
  {
    # debug
    _d("->\t" x $frame{depth}, "$opcode");

    # advance opcode ptr
    $frame{opcode} ++;

    # process opcode here
    #  _decode returns 1 if execution of frame needs to stop (e.g. exit sub)
    last if $self->_decode(\%frame,$opcode);
  }
}


##########################################################
# PUBLIC METHODS
# Constructor
#  (accepts one optional parameter to change the data dir)
sub new
{
  my $class = shift;

  my $args_ref = shift;

  # switch global debug flag
  $debug = $args_ref->{debug} // 0;
  
  _d("Constructing new INRAC object: " . Dumper($args_ref));

  my $file = $args_ref->{file} or confess "No base input file specified";
  my $callback = $args_ref->{callback} or confess "No input callback specified";

  # Initial empty class
  my %self = (
    # Register a callback function to process input
    callback => $callback,

    # Save, load, and log callbacks
    callback_put => $args_ref->{callback_put},
    callback_load => $args_ref->{callback_load},
    callback_out => $args_ref->{callback_out},

    # Filesystem interaction
    data_dir => dirname($file),

    # Script in use (fill by _read_data_file)
    script => {},

    # Internal RAM storage
    variable => [],
    # Conditional result register
    condition => 0,
    # Index to char in variable1 (user input)
    input_ptr => 0,
    #input_words => [],
    # Output buffer
    output => '',
  );

  # read first datafile
  _read_data_file(\%self,$file);

  # bless and return
  bless \%self, $class;
}

# Kicks off the INRAC parser
#  This runs until script termination
#  Callback will fire when ?? is read from script
sub run
{
  # Execute from default starting position
  $_[0]->_execute( { section => 1, line => 0, opcode => 0, depth => 1 } );
}

1;
