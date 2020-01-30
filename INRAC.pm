##########################################################
# INRAC brain, object implementation.
package INRAC;
#use v5.012;
use warnings;

use autodie;

use Carp;
use File::Basename;

##########################################################
# DEBUG
use Term::ANSIColor;
use Data::Dumper;
# Module-wide debug switch
my $debug = 0;

# Debug print when module-wide debug enabled
sub _d { print STDERR @_ if $debug }

##########################################################
# STATIC HELPER FUNCTIONS
# Choose one item at random from a list
sub _pick { return $_[rand @_] }

# normalizes a substring (remove punct, lowercase)
sub _norm
{
	my $str = shift // '';
	$str =~ s/[^A-Za-z0-9']//g;
	return lc($str);
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
# TODO: add & for * wildcard
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

	return 1;
}

sub _get_word
{
	my $sentence = shift;
	my $word_num = shift;

	my @words = split /\s+/, $sentence;
	return ($words[$word_num] // '');
}

sub _get_rest
{
	my $sentence = shift;
	my $word_num = shift;

	my @words = split /\s+/, $sentence;
#say "get_rest called with $sentence, $word_num: result " . join(' ', @words[$word_num .. $#words]);

	return join(' ', @words[$word_num .. $#words]);
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

# Expand out all * from a line
sub _expand
{
	my $self = shift;

	die "Unimplemented";

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
  my $self = shift;
  my $datafile = shift;

  _d(colored("OPENING $datafile...\n", 'bold green'));
  if (open my $fh, '<:crlf', $datafile)
  {
    # Read header lines
    my $file_header = _eat($fh);
    my $file_sec_start = _eat($fh) + 0;
    my $file_sec_count = _eat($fh) + 0;
    my $file_line_count = _eat($fh) + 0;

    _d("> HEADER: '$file_header', $file_line_count lines, $file_sec_count sect (begin $file_sec_start)\n");

    # Read section definitions
    my @sec_defs;
    for my $section_number ($file_sec_start .. $file_sec_start + $file_sec_count - 1)
    {
      my $section_header = _eat($fh);
      my $section_type = _eat($fh) + 0; # type
      my $section_line_count = _eat($fh) + 0;

      # Push section info into array.
      push @sec_defs, {
        header => $section_header,
        number => $section_number,
        type => $section_type,
        line_count => $section_line_count
      };

      _d(">> SECTION $section_number: '$section_header', $section_line_count lines, $section_type type\n");
    }

    # Got our section definitions. Process lines per section.
    foreach my $sec (@sec_defs)
    {
      # Check for existing section
      #  (sometimes sections called "link" are placeholders unloaded by subsequent scripts)
      _d(colored("Duplicate entry for " . $sec->{number} . ", overwriting\n", 'yellow')) if $self->{code}[$sec->{number}];

      # store header info (for debug)
      $self->{code}[$sec->{number}]{file_name} = $datafile;
      $self->{code}[$sec->{number}]{file_header} = $file_header;
      $self->{code}[$sec->{number}]{section_header} = $sec->{header};
      $self->{code}[$sec->{number}]{type} = $sec->{type};

      $self->{code}[$sec->{number}]{line} = [];
      $self->{code}[$sec->{number}]{label} = {};
      for (my $idx = 0; $idx < $sec->{line_count}; $idx ++)
      {
        my $line = _eat($fh);

        # tokenize and push
        my @tokens = split(/\s+/,$line);

        # Sections contain a list of Lines (strip first Line Label off)
        my $label = shift @tokens;
        #  Need a pointer to previously pushed line too
        my $pushed_line_num = push @{$self->{code}[$sec->{number}]{line}}, \@tokens;
        # Labels stored here which point to Lines above.
        push @{$self->{code}[$sec->{number}]{label}{$label}}, $pushed_line_num - 1;
      }
      _d('>> Section ' . $sec->{number} . ": Processed " . scalar @{$self->{code}[$sec->{number}]{line}} . " lines, " . scalar(keys %{$self->{code}[$sec->{number}]{label}}) . " distinct labels.\n");
    }
  } else {
    confess "Failed opening datafile $datafile: $!\n";
  }

  return 1;
}

# Retrieve a variable (or '' if unset)
sub _get_var { return $_[0]->{variable}[$_[1]] // ''; }

# Split first and rest off a token
sub _split {
  my $first = substr($_[0],0,1);
  my $rest = (length($_[0]) > 1 ? substr($_[0],1) : '');
  return ($first, $rest);
}

# Iteratively process until we run out of opcodes.
sub _execute
{
  my ($self, $section, $line, $depth, @code_buffer) = @_;

  _d("\t" x $depth, colored("_execute(sec=$section, line=$line, buf=" . join(' ', @code_buffer) . ")\n", 'bold blue'));

  while (@code_buffer)
  {
    # Retrieve next opcode from the queue
    my $token = shift @code_buffer;

    # debug
    _d("->\t" x $depth, "$token\n");

    # process opcode here
    my ($first, $rest) = _split($token);

    #####################################
    # Conditional execution: process or skip token depending on set/unset flag
    if ($first eq '/') {
      # "Execute if condition SET"
      if ($self->{condition}) { 
        ($first, $rest) = _split($rest);
        _d("\t" x ($depth + 1), colored(" (taken)\n", 'green'));
      } else {
        _d("\t" x ($depth + 1), colored(" (skipped)\n", 'red'));
        next;
      }
    } elsif ($first eq '\\') {
      # "Execute if condition UNSET"
      if (!$self->{condition}) {
        ($first, $rest) = _split($rest);
        _d("\t" x ($depth + 1), colored(" (taken)\n", 'green'));
      } else {
        _d("\t" x ($depth + 1), colored(" (skipped)\n", 'red'));
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
      $self->{variable}[1] = $self->{callback}->($self->{output});

      # Clean up input
      #$self->{variable}[1] =~ s/\s+/ /g;
      #$self->{input_ptr} = 0;

      # Call helper function to set up index ptrs to words
      #$self->{input_words} = _word_points($self->{variable}[1]);
      #@{$self->{input_words}} = split /\s+/, $self->{variable}[1];

      # reset output before continuing
      $self->{output} = '';
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
        $self->{callback_put}->($1,$self->{variable}) if defined $self->{callback_put};
      } elsif ($rest =~ m/^OUT(.+)/) {
        # Trigger log callback, if defined.  Callback should open whatever output file handles are needed.
        $self->{callback_out}->($1) if defined $self->{callback_out};
      } elsif ($rest eq 'ZAP') {
        # Erase internal data store - clears only items 10+ from variable list, so preserve 1-9.
        @{$self->{variable}} = splice (@{$self->{variable}},1,10);
      }
      #  Move input (word) opcode pointer
      elsif ($rest =~ m/^F/) {
        if ($rest =~ m/^F=(\d+)$/) { $self->{input_ptr} = $1;
        } elsif ($rest =~ m/^F\+(\d+)$/) { $self->{input_ptr} += $1;
        } elsif ($rest =~ m/^F-(\d+)$/) { $self->{input_ptr} -= $1;
        } elsif ($rest eq 'F=E') { $self->{input_ptr} = split(/\s+/, $self->_get_var(1))- 1;
        } else { confess "Unimplemented special-function '$rest'"; ... }

        _d("\t" x ($depth + 1), colored(' (F=' . $self->{input_ptr} . ")\n", 'yellow'));
      }
      #  Unknown.
      elsif ($rest =~ m/T/) { carp "Unknown special-function 'T', unimp"; }
      else { confess "Unimplemented special-function '$rest'"; ... }
    } elsif ($first eq '%') {
      # LOAD SCRIPT FILE
      $self->_read_data_file($self->{data_dir} . '/' . $rest . '.RAC');
    #####################################
    # VARIABLE MANIP
    } elsif ($first eq '$') {
      # GET IV: retrieves a variable and returns its value.
      #  TODO: Variables retrieved may contain more variables, needs actual parsing.
      #$self->{output} .= ($self->_expand($self->_get_var($rest)) . ' ');
      my $val = $self->_get_var($rest);
      $self->{output} .= ($val . ' ');
      _d("\t" x ($depth + 1), colored(" ($val)\n", 'blue'));
    } elsif ($first eq '>') {
      # SET IV: sets an internal variable
      if ($rest =~ m/(\d+)([*=])(.*)/) {
        my $right = $3;
        if ($2 eq '*') {
          # random call -
          ...
       #die "unimp";
          #$right = $self->_expand('*' . $3);
        }
        my @rhs = split /,/, $right;
        my $val = '';

        while (my $mod = pop @rhs)
        {
          if ($mod eq 'F') { $val = _get_word($self->_get_var(1),$self->{input_ptr}); }
          elsif ($mod =~ m/^\d+$/) { $val = $self->_get_var($mod); }
          elsif ($mod eq 'R') { $val = _get_rest($self->_get_var(1),$self->{input_ptr} + 1); }
          elsif ($mod eq 'C') { $val = ucfirst($val); }
          else { $val .= $mod; } #confess "Unknown modifier $mod in SET-token (full cmd: '$token')"; 
        }
        # set final var
        $self->{variable}[$1] = $val;
        _d("\t" x ($depth + 1), colored(" ($1=$val)\n", 'green'));
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
        my $f = _get_word($self->_get_var(1),$self->{input_ptr} + $offset);

        if ($1 eq 'CAP') {
          # Check if word is capitalized.
          $result = ($f eq ucfirst($f));
        } elsif ($1 eq 'PUNC') {
          # Check if word ends in punctuation
          $result = ($f =~ m/[.?]$/);
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

        my @searchable_words = split /\s+/, $self->_get_var(1);
        for my $i (0 .. scalar @searchable_words)
        {
          my $input_word = _norm($searchable_words[$i]);

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
        _d("\t" x ($depth + 1), colored(" (condition flag SET)\n", 'green'));
      } else {
        _d("\t" x ($depth + 1), colored(" (condition flag UNSET)\n", 'red'));
      }

    ####################################
    # FLOW CONTROL
    } elsif ($first eq '*') {
      # GOSUB

      if ($rest eq '') {
        # RETURN: pop stack frame, return
        return 1;
      } else {
        my $target = $self->_call_glob($rest);

        # push a new stack frame
        # execute sub and return
        $self->_execute( $target->{section}, $target->{line}, $depth + 1,
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
    } else {
      my $final = $token;

      if ($first eq '<') {
        # Delete preceding space.
        chop $self->{output};
	$final = $rest;
      } elsif ($first =~ m/^[.!?,]$/) {
        # Singular punct. characters need to remove preceding space too
        chop $self->{output};
      }

      # Output without trailing space if token ends with >
      if ($final =~ m/^(.+)>$/) {
        $final = $1;
      } else {
        $final .= ' ';
      }

      # Append the substring.
      $self->{output} .= $final;

      # Correct double-spacing after sentence endings
      #  The original flushes the buffer here too
      $self->{output} .= ' ' if $self->{output} =~ m/[.!?] $/;
    }
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

  _d("Constructing new INRAC object: " . Dumper($args_ref) . "\n");

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
    #input_words => [],
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
  $self->_execute( 0, 0, 0, $initial_script );
}

1;
