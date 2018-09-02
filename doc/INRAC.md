# INRAC LANGUAGE SPEC
*Draft version*

Greg Kennedy, 2018

![Mac Classic Racter Screenshot](racter.png)

## OVERVIEW
The INRAC data fles are ASCII text and MS-DOS crlf terminated.  Each file consists of a Header, a number of Section Definitions, and then a series of code lines.

Code lines begin with a label, then contain a series of character opcodes with embedded text.  Think of it as smart templates.

## DATA FILE LAYOUT
Data files begin with a header of the following, one per line
* Source-file title, comment, or description
* Unknown - Maybe "first section to load" ? (can be safely ignored)
* Count of sections in file
* Total count of lines across all sections

Section definitions follow:
* SECTION (number) (section-name)
* Number, unknown
* Number of lines in section

After section definitions, all lines of code follow.  Here is an example data file with two sections, 6 lines of code.  Section 1 begins at label A, section 2 at label B.  (An X is typically used for a dummy label)

    SAMPLE.IF Example file for INRAC documentation 09-02-2018
     1
     2
     10
    SECTION 1 hello
     5
     3
    SECTION 2 goodbye
     5
     3
    A Hello there!  This is a sample line.
    X There is more text here.
    X This is the last line of Hello.
    B Goodbye now.
    X There is more text here.
    X This is the last line of Goodbye.

## INTERNAL MEMORY
The INRAC "machine" has a limited internal memory: a 100-slot "array" of strings.  Typically an INRAC program may have some dedicated slots for persisted info (e.g. 40 for user's first name, 53 for their last).  Certain functions store data in a particular location - for instance, user input is always copied into variable 1.

There are functions for loading, saving, and clearing the variable array.

In addition, there is a pointer called "F" which points to a word in a sentence.  This pointer can be moved around and compared to words - it is how INRAC programs do matching of text.

There is a Condition flag which can be set / cleared using some Test functions.  It can be also be checked and thus used to do branching.

## CODE SECTIONS
Each line of a code section begins with some letter opcodes.

`$xx` - Recall a variable from internal memory.  Memory is an array of 100 strings, which can be stored to or read from.
`??` - Get user input.  This triggers the interpreter to read a line of text from the user, and store it into internal memory (variable #1)
`%aaa` - Load an additional script file aaa.rac.  The initial Racter file is small, but additional sections can be loaded from disk as needed.
`:` - Call interpreter function.  These hooks invoke special functions provided by the interpreter, typically for file access or similar.
  `:ZAP` - Clear internal variable memory
  `:LOADaaa` - Load variable memory from file named "aaa.iv"
  `:PUTaaa` - Save variable memory to file named "aaa.iv"
  `:OUTaaa` - Open "aaa.out" and record a copy of all I/O to it
  `:F` - Manipulate the F word-pointer.
    `:F=n` - Set F to point at the nth word, e.g. F=0 points to the beginning of the string, F=1 to the second word, etc
    `:F=E` - As a special case of F=n above, F=E will move the pointer to the last word in the sentence.
    `:F+n` - Advance F by n words, advancing past the end sets the pointer to the last word
    `:F-n` - Backtrack F by n words, going beyond the first word will simply set F=0.
  `>` - Functions to set the internal variable array.
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

If none of these opcodes are hit, the word is just a piece of embedded (literal) text, and is passed as-is to the output string builder.
