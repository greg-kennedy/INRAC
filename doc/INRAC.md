# INRAC LANGUAGE SPEC
*Draft version*

Greg Kennedy, 2020

![Mac Classic Racter Screenshot](racter.png)

## OVERVIEW
The INRAC interpreter is a virtual machine that operates on code written in a special template language.  The VM has a short memory bank, the ability to load or unload further code to fit into RAM, and functions for reading user input, printing text to output, or performing text matching and parsing.

The original INRAC machine ("Racter") was written by William Chamberlain and Thomas Etter in 1983, to help write the book "The Policeman's Beard is Half-Constructed".  This version (hereafter, "Version 0") was not released to the public.  It was reportedly written in BASIC, targeting a Z80-based machine running CP/M with 64kb of RAM.

In 1984 Mindscape, Inc. released a version of the Racter program for MS-DOS computers (Version 1).  This version was written in (or ported to) Microsoft BASIC-86 and compiled using Microsoft BASIC Compiler 5.35.

Mindscape also ported Racter to Apple II, Amiga, and Macintosh computers (Version 2).  These ports use a slightly different data file format than the MS-DOS version.

In addition, the Racter developers attempted to license the underlying INRAC language to others interested in electronic literature or AI development.  There was at least one user, Hale Chatfield (of Hiram College Ohio) who released some works under the name "Chatfield Software".  The re-licensed version also appears to use Version 2 files.

## THE INRAC VIRTUAL MACHINE
This section describes some features of the INRAC interpreter, and known limitations.

### CODE STORAGE
INRAC code is stored in "sections" up to 255 lines in length.  There are 99 section slots available, which can be loaded and unloaded at will.  Each code file specifies the intended slot, numbered 1 to 99, which it will load into.  Loading code to an already used section will unload the section first.  In this way, memory usage can be controlled, by keeping only sections in RAM that are needed for processing.

In the BASIC interpreter, this is stored as a 99 by 256 array of strings.

Code sections have different "type" values, stored in the header.  The "type" may or may not affect the interpreter rules.  The most common type is 5, which seems to indicate a "code" (normal) parsing.  Others such as 2 or 8 may indicate some sort of vocabulary handling.

### INTERNAL MEMORY
The INRAC "machine" has a limited internal memory: a 100-slot array of strings.  This array index is 1-based.  For the most part, the variable store is generic - the programmer may assign locations freely.  However, there are certain built-in functions which rely on specific reserved slots.  For instance, user input is always copied into variable 1.

There are built-in functions for loading, saving, and clearing the variable array.

Typically, an INRAC program will use some convention for persisted info (for example, the Racter data file always uses location 40 for user's first name, 53 for their last).

In addition to the strings array, there is a pointer called "F" which points to a word in a sentence.  This pointer can be moved around and compared to other words - it is how INRAC programs do matching of text.

Finally, there is a Condition flag which can be set / cleared using some Test functions.  It can be also be checked and thus used to do branching.

### PROCESSING
Code lines begin with a label, then contain a series of character opcodes with embedded text.  It helps to think of the lines as "smart templates," where text output is the "default" case, and opcodes trigger special interpolation or other behavior.

Each line of a code section begins with some letter opcodes.

* `$xx` - Recall a variable from internal memory.  Memory is an array of 100 strings, which can be stored to or read from.
* `??` - Get user input.  This triggers the interpreter to read a line of text from the user, and store it into internal memory (variable #1)
* `%aaa` - Load an additional script file aaa.rac.  The initial Racter file is small, but additional sections can be loaded from disk as needed.
* `:` - Call interpreter function.  These hooks invoke special functions provided by the interpreter, typically for file access or similar.
  * `:ZAP` - Clear internal variable memory
  * `:LOADaaa` - Load variable memory from file named "aaa.iv"
  * `:PUTaaa` - Save variable memory to file named "aaa.iv"
  * `:OUTaaa` - Open "aaa.out" and record a copy of all I/O to it
  * `:F` - Manipulate the F word-pointer.
    * `:F=n` - Set F to point at the nth word, e.g. F=0 points to the beginning of the string, F=1 to the second word, etc
    * `:F=E` - As a special case of F=n above, F=E will move the pointer to the last word in the sentence.
    * `:F+n` - Advance F by n words, advancing past the end sets the pointer to the last word
    * `:F-n` - Backtrack F by n words, going beyond the first word will simply set F=0.
  * `>n` - Functions to set the internal variable array.  Sets a value for slot n in the array based on the following...
    * `*` - Call a subroutine and ... ???
    * `=` - Set nth item to a value
      * `=F` - Copy the word pointed to by F into this variable slot
      * `=xx` - Copy variable slot xx into n
      * `=R` - Copy all words after F into this variable
      * `=C` - Uppercase the first letter of the string in n, and store back to itself
* `?` - Functions to execute tests and set or clear the condition flag.
  * `?n=a` - Tests if variable n equals constant a
* `#` - Stops line processing at this point, and immediately advances to the start of the next line.
  * `#*n` - Stops line processing and advances to the specified label (instead of the next line)
* `/` - Only perform the next opcode if condition flag is TRUE
* `\` - Only perform the next opcode if condition flag is FALSE

If none of these opcodes are hit, the word is just a piece of embedded (literal) text, and is passed as-is to the output string builder.

Words are usually separated by a space, except where a token ends with `>` or the next begins with `<`.

Punctuation is usually separated by a double space.

## DATA FILE LAYOUT
There are at least two data file formats in use.  These are not interchangeable between interpreters.
* The first format is used for the MS-DOS version of Racter.  Data files in this format use a `.RAC` file extension.
* The second is for Apple II and Mac, but it also appears in third-party MS-DOS programs built on INRAC.  Data files in this format use a `.ZIP` file extension, although they are not actually PK-Zip compressed file archives.

### VERSION 1 (MS-DOS) DATA LAYOUT
The INRAC data fles are ASCII text and MS-DOS crlf terminated.  Each file consists of a Header, a number of Section Definitions, and then a series of code lines.

Data files begin with a header of the following, one per line:
* Source-file title, comment, or description - can be ignored by the interpreter
* Index of first section - sections are loaded sequentially into internal code memory, beginning from this value
* Count of sections in file
* Total count of lines across all sections

Section definitions follow:
* Section title, comment, or description - can be ignored by the interpreter
* Number - unknown, assumed type
* Number of lines in section

After section definitions, all lines of code follow.  Here is an example data file with two sections, 7 lines of code.  Section 1 begins at label A, section 2 at label B.  (An X is typically used for a dummy label)

    SAMPLE.IF Example file for INRAC documentation 09-02-2018
     1
     2
     7
    SECTION 1 hello
     5
     3
    SECTION 2 goodbye
     5
     4
    A Hello there!  This is a sample line. #
    X There is more text here. #
    X This is the last line of Hello. #
    B Goodbye now. #
    X There is more text here. #
    X There is even more text here. #
    X This is the last line of Goodbye.

### VERSION 2 (APPLE, AMIGA, MAC, 3RD PARTY) DATA LAYOUT
*To Do*
