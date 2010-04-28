#!/usr/bin/env perl
use 5.010;
#use autodie;
use strict;
#use File::Slurp qw[ slurp ];
#BEGIN { *Pod::Simple::DEBUG = sub () { 9001 } }
use Pod::Text;
use File::Temp qw< tempdir tempfile >;
use IO::Handle;
use Test::More 'no_plan';
#use Data::Dump 'dump';
#use Devel::Peek;
#use Encode;

# Output, on my system:
my $test_output = <<'END';
ok 1 - Got all the POD
# Memory handle IO layer: ["scalar"]
# Tempfile IO layer: ["unix", "perlio"]
# Slurp file IO layer: ["unix", "perlio"]
not ok 2 - writing to in-memory open() == writing to temporary file
#   Failed test 'writing to in-memory open() == writing to temporary file'
#   at readmefrompod.pl line 74.
#     Structures begin differing at:
#          $got->[260] = '    *   <http://bit.ly/hailo_rewrite_of_megah'
#     $expected->[260] = '    *   <http://bit.ly/hailo_rewrite_of_megahal> - Hailo: A Perl rewrite of'
not ok 3 - writing to in-string == writing to temporary file
#   Failed test 'writing to in-string == writing to temporary file'
#   at readmefrompod.pl line 75.
#     Structures begin differing at:
#          $got->[264] = '    Hinrik �rn Sigur�sson, hinrik.sig@gmail.com'
#     $expected->[264] = '    Hinrik Örn Sigurðsson, hinrik.sig@gmail.com'
1..3
# Looks like you failed 2 tests of 3.
END

my $mmcontent = join '', <DATA>;#slurp("lib/Hailo.pm");

like($mmcontent, qr/^=cut/m, "Got all the POD");

my ($in_memory, $in_string, $in_file);
{
    open( my $out_fh, ">", \my $content );
    #diag "Memory handle IO layer: " . dump [ PerlIO::get_layers($out_fh) ];
    my $parser = Pod::Text->new();
    $parser->output_fh($out_fh);
    $parser->parse_string_document($mmcontent);

    $in_memory = $content;
}

{
    my $parser = Pod::Text->new();
    $parser->output_string( \my $content );
    $parser->parse_string_document($mmcontent);
    #Encode::_utf8_on($content);
    #Dump($content);

    $in_string = $content;
}

{
    my $dir = tempdir( CLEANUP => 1 );
    my ($out_fh, $filename) = tempfile( DIR => $dir );
    #diag "Tempfile IO layer: " . dump [ PerlIO::get_layers($out_fh) ];

    my $parser = Pod::Text->new();
    $parser->output_fh( $out_fh );
    $parser->parse_string_document( $mmcontent );
    eval { $out_fh->sync(); 1 } or do {
        if ($@ =~ '^IO::Handle::sync not implemented on this architecture') {
            $out_fh->flush();
        }
        else {
            die;
        }
    };
    close $out_fh;

    # Do *not* convert this to something that doesn't use open() for
    # cleverness, that breaks UTF-8 pod files.
    open(my $fh, "<", $filename);
    #diag "Slurp file IO layer: " . dump [ PerlIO::get_layers($fh) ];
    my $content = do { local $/; <$fh> };

    close $fh;

    $in_file = $content;
}

TODO: {
    local $TODO = "In-memory filehandle is truncated for some reason";
    is_deeply([split /\n/, $in_memory], [split /\n/, $in_file], "writing to in-memory open() == writing to temporary file");
}
TODO: {
    local $TODO = "In-string doesn't truncate but fails at encoding";
    is_deeply([split /\n/, $in_string], [split /\n/, $in_file], "writing to in-string == writing to temporary file");
}

__DATA__

=encoding utf8

=head1 NAME

Hailo - A pluggable Markov engine analogous to MegaHAL

=head1 SYNOPSIS

This is the synopsis for using Hailo as a module. See L<hailo> for
command-line invocation.

 # Hailo requires Perl 5.10
 use 5.010;
 use strict;
 use warnings;
 use Hailo;

 # Construct a new in-memory Hailo using the SQLite backend. See
 # backend documentation for other options.
 my $hailo = Hailo->new;

 # Various ways to learn
 my @train_this = qw< I like big butts and I can not lie >;
 $hailo->learn(\@train_this);
 $hailo->learn($_) for @train_this;

 # Heavy-duty training interface. Backends may drop some safety
 # features like journals or synchronous IO to train faster using
 # this mode.
 $hailo->learn("megahal.trn");
 $hailo->learn($filehandle);

 # Make the brain babble
 say $hailo->reply("hello good sir.");

=head1 DESCRIPTION

Hailo is a fast and lightweight markov engine intended to replace
L<AI::MegaHAL|AI::MegaHAL>. It has a L<Mouse|Mouse> (or L<Moose|Moose>)
based core with pluggable L<storage|Hailo::Role::Storage> and
L<tokenizer|Hailo::Role::Tokenizer> backends.

It is similar to MegaHAL in functionality, the main differences (with the
default backends) being better scalability, drastically less memory usage,
an improved tokenizer, and tidier output.

With this distribution, you can create, modify, and query Hailo brains. To
use Hailo in event-driven POE applications, you can use the
L<POE::Component::Hailo|POE::Component::Hailo> wrapper. One example is
L<POE::Component::IRC::Plugin::Hailo|POE::Component::IRC::Plugin::Hailo>,
which implements an IRC chat bot.

=head2 Etymology

I<Hailo> is a portmanteau of I<HAL> (as in MegaHAL) and
L<failo|http://identi.ca/failo>.

=head1 Backends

Hailo supports pluggable L<storage|Hailo::Role::Storage> and
L<tokenizer|Hailo::Role::Tokenizer> backends, it also supports a
pluggable L<UI|Hailo::Role::UI> backend which is used by the L<hailo>
command-line utility.

=head2 Storage

Hailo can currently store its data in either a
L<SQLite|Hailo::Storage::DBD::SQLite>,
L<PostgreSQL|Hailo::Storage::DBD::Pg> or
L<MySQL|Hailo::Storage::DBD::mysql> database, more backends were
supported in earlier versions but they were removed as they had no
redeeming quality.

SQLite is the primary target for Hailo. It's much faster and uses less
resources than the other two. It's highly recommended that you use it.

This benchmark shows how the backends compare when training on the
small testsuite dataset as reported by the F<utils/hailo-benchmark>
utility (found in the distribution):

                         Rate DBD::Pg DBD::mysql DBD::SQLite/file DBD::SQLite/memory
    DBD::Pg            2.22/s      --       -33%             -49%               -56%
    DBD::mysql         3.33/s     50%         --             -23%               -33%
    DBD::SQLite/file   4.35/s     96%        30%               --               -13%
    DBD::SQLite/memory 5.00/s    125%        50%              15%                 --

Under real-world workloads SQLite is much faster than these results
indicate since the time it takes to train/reply is relative to the
existing database size. Here's how long it took to train on a 214,710
line IRC log on a Linode 1080 with Hailo 0.18:

=over

=item * SQLite


=item * MySQL

 real    48m30.334s
 user    8m25.414s
 sys     4m38.175s

=item * PostgreSQL

 real    216m38.906s
 user    11m13.474s
 sys     4m35.509s

=back

In the case of PostgreSQL it's actually much faster to first train
with SQLite, dump that database and then import it with L<psql(1)>,
see L<failo's README|http://github.com/hinrik/failo> for how to do
that.

However when replying with an existing database (using
F<utils/hailo-benchmark-replies>) yields different results. SQLite can
reply really quickly without being warmed up (which is the typical
usecase for chatbots) but once PostgreSQL and MySQL are warmed up they
start replying faster:

Here's a comparison of doing 10 replies:

                        Rate PostgreSQL MySQL SQLite-file SQLite-file-28MB SQLite-memory
    PostgreSQL        71.4/s         --  -14%        -14%             -29%          -50%
    MySQL             83.3/s        17%    --          0%             -17%          -42%
    SQLite-file       83.3/s        17%    0%          --             -17%          -42%
    SQLite-file-28MB 100.0/s        40%   20%         20%               --          -30%
    SQLite-memory      143/s       100%   71%         71%              43%            --

In this test MySQL uses around 28MB of memory (using Debian's
F<my-small.cnf>) and PostgreSQL around 34MB. Plain SQLite uses 2MB of
cache but it's also tested with 28MB of cache as well as with the
entire database in memory.

But doing 10,000 replies is very different:

                       Rate SQLite-file PostgreSQL SQLite-file-28MB MySQL SQLite-memory
    SQLite-file      85.1/s          --        -7%             -18%  -27%          -38%
    PostgreSQL       91.4/s          7%         --             -12%  -21%          -33%
    SQLite-file-28MB  103/s         21%        13%               --  -11%          -25%
    MySQL             116/s         37%        27%              13%    --          -15%
    SQLite-memory     137/s         61%        50%              33%   18%            --

Once MySQL gets more memory (using Debian's F<my-large.cnf>) and a
chance to warm it starts yielding better results (I couldn't find out
how to make PostgreSQL take as much memory as it wanted):

                   Rate         MySQL SQLite-memory
    MySQL         121/s            --          -12%
    SQLite-memory 138/s           14%            --

=head2 Tokenizer

By default Hailo will use L<the word
tokenizer|Hailo::Tokenizer::Words> to split up input by whitespace,
taking into account things like quotes, sentence terminators and more.

There's also a L<the character
tokenizer|Hailo::Tokenizer::Chars>. It's not generally useful for a
conversation bot but can be used to e.g. generate new words given a
list of existing words.

=head1 UPGRADING

Hailo makes no promises about brains generated with earlier versions
being compatable with future version and due to the way Hailo works
there's no practical way to make that promise.

If you're maintaining a Hailo brain that you want to keep using you
should save the input you trained it on and re-train when you upgrade.

The reason for not offering a database schema upgrade for Hailo is
twofold:

=over

=item * We're too lazy to maintain database upgrade scripts for every version.

=item * Even if we weren't there's no way to do it right.

=back

The reason it can't be done right is that Hailo is always going to
lose information present in the input you give it. How input tokens
get split up and saved to the storage backend depends on the version
of the tokenizer being used and how that input gets saved to the
database.

For instance if an earlier version of Hailo tokenized C<"foo+bar">
simply as C<"foo+bar"> but a later version split that up into
C<"foo", "+", "bar">, then an input of C<"foo+bar are my favorite
metasyntactic variables"> wouldn't take into account the existing
C<"foo+bar"> string in the database.

Tokenizer changes like this would cause the brains to accumulate garbage
and would leave other parts in a state they wouldn't otherwise have gotten
into. There have been similar changes to the database format itself.

In short, learning is lossy so an accurate conversion is impossible.

=head1 ATTRIBUTES

=head2 C<brain_resource>

The name of the resource (file name, database name) to use as storage.
There is no default. Whether this gets used at all depends on the
storage backend, currently only SQLite uses it.

=head2 C<save_on_exit>

A boolean value indicating whether Hailo should save its state before
its object gets destroyed. This defaults to true and will simply call
L<save|/save> at C<DEMOLISH> time.

=head2 C<order>

The Markov order (chain length) you want to use for an empty brain.
The default is 2.

=head2 C<storage_class>

The storage backend to use. Default: 'SQLite'.

=head2 C<tokenizer_class>

The tokenizer to use. Default: 'Words';

=head2 C<ui_class>

The UI to use. Default: 'ReadLine';

=head2 C<storage_args>

=head2 C<tokenizer_args>

=head2 C<ui_args>

A C<HashRef> of arguments for storage/tokenizer/ui backends. See the
documentation for the backends for what sort of arguments they accept.

=head1 METHODS

=head2 C<new>

This is the constructor. It accepts the attributes specified in
L</ATTRIBUTES>.

=head2 C<learn>

Takes a string or an array reference of strings and learns from them.

=head2 C<train>

Takes a filename, filehandle or array reference and learns from all its
lines. If a filename is passed, the file is assumed to be UTF-8 encoded.
Unlike L<C<learn>|/learn>, this method sacrifices some safety (disables
the database journal, fsyncs, etc) for speed while learning.

=head2 C<reply>

Takes an optional line of text and generates a reply that might be relevant.

=head2 C<learn_reply>

Takes a string argument, learns from it, and generates a reply that
might be relevant. This is equivalent to calling L<learn|/learn>
followed by L<reply|/reply>.

=head2 C<save>

Tells the underlying storage backend to L<save its
state|Hailo::Role::Storage/"save">, any arguments to this method will
be passed as-is to the backend.

=head2 C<stats>

Takes no arguments. Returns the number of tokens, expressions, previous
token links and next token links.

=head1 PRIVATE METHODS

=head2 C<run>

Run Hailo in accordance with the the attributes that were passed to
it, this method is called by the L<hailo> command-line utility and the
Hailo test suite, it's behavior is subject to change.

=head1 SUPPORT

You can join the IRC channel I<#hailo> on FreeNode if you have questions.

=head1 BUGS

Bugs, feature requests and other issues are tracked in L<Hailo's issue
tracker on Github|http://github.com/hinrik/hailo/issues>.

=head1 SEE ALSO

=over

=item * L<Hailo::UI::Web> - A L<Catalyst> and jQuery powered web interface to Hailo

=item * L<POE::Component::Hailo> - A non-blocking POE wrapper around Hailo

=item * L<POE::Component::IRC::Plugin::Hailo> - A Hailo IRC bot plugin

=item * L<http://github.com/hinrik/failo> - Failo, an IRC bot that uses Hailo

=back

=head1 LINKS

=over

=item * L<http://bit.ly/hailo_rewrite_of_megahal> - Hailo: A Perl rewrite of
MegaHAL, A blog posting about the motivation behind Hailo

=back

=head1 AUTHORS

Hinrik E<Ouml>rn SigurE<eth>sson, hinrik.sig@gmail.com

E<AElig>var ArnfjE<ouml>rE<eth> Bjarmason <avar@cpan.org>

=head1 LICENSE AND COPYRIGHT

Copyright 2010 Hinrik E<Ouml>rn SigurE<eth>sson and
E<AElig>var ArnfjE<ouml>rE<eth> Bjarmason <avar@cpan.org>

This program is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
