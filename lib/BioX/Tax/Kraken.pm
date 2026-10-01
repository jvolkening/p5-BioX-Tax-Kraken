package BioX::Tax::Kraken 0.001;

use strict;
use warnings;
use 5.016;
use autodie;

use IPC::Cmd qw/can_run/;
use Memoize;

use constant N_VALID_COLUMNS => 4;
use constant PARENT => 0;
use constant NAME => 1;
use constant RANK => 2;

memoize('BioX::Tax::Kraken::is_ancestor');
memoize('BioX::Tax::Kraken::parent');
memoize('BioX::Tax::Kraken::name');
memoize('BioX::Tax::Kraken::rank');

sub new {

    my ($class, $fn_in) = @_;

    my $self = bless {fn => $fn_in}, $class;

    $self->_set_handle();
    $self->_load();

    return $self;

}

sub _set_handle {

    my ($self) = @_;

    my $fh_in;
    if ( _is_xz($self->{fn}) ) {
        my $XZCAT = can_run('xzcat')
            // die "Require 'xzcat' for XZ-compressed inputs";
        open $fh_in, '-|', $XZCAT, $self->{fn};
    }
    else {
        open $fh_in, '<', $self->{fn};
    }
    $self->{fh} = $fh_in;

}

sub parent {

    my ($self, $tid) = @_;
    return if (! defined $self->{tax}->{$tid});
    return (split "\0", $self->{tax}->{$tid})[PARENT];

}

sub name {

    my ($self, $tid) = @_;
    return if (! defined $self->{tax}->{$tid});
    return (split "\0", $self->{tax}->{$tid})[NAME];

}

sub rank {

    my ($self, $tid) = @_;
    return if (! defined $self->{tax}->{$tid});
    return (split "\0", $self->{tax}->{$tid})[RANK];

}

sub children {

    my ($self, $tid) = @_;

    return grep {
        $self->is_ancestor($_, $tid)
    } keys %{ $self->{tax} };

}

sub is_ancestor {

    my ($self, $child, $parent) = @_;
    return if (! defined $self->{tax}->{$child});
    my $p = $self->parent($child);
    return 1 if ($p eq $parent);
    return 0 if ($p eq $child); # reached root
    return $self->is_ancestor( $p, $parent );

}

sub _is_xz {

    my ($fn) = @_;

    use constant XZ_MAGIC => "\xFD7zXZ\x00";
    open my $in, '<:raw', $fn;
    my $n = read $in, my $buf, 6;
    close $in;

    return 0 if ($n != 6);
    return $buf eq XZ_MAGIC

}

sub _load {

    my ($self) = @_;

    my $fh = $self->{fh};
    while (my $line = <$fh>) {
        chomp $line;
        my @f = split "\t", $line;
        if (scalar @f != N_VALID_COLUMNS) {
            die sprintf(
                "Invalid taxDB format: expected %s columns, found %s",
                N_VALID_COLUMNS,
                scalar @f,
            );
        }
        if ($f[0] =~ /\D/ || $f[1] =~ /\D/) {
            die "Invalid taxDB format: expected integers in first two columns";
        }
        # uses < 50% memory to store data as null-padded strings instead of
        # Perl nested arrays or hashes. Can be significantly slower to extract
        # data on millions of calls, though.
        $self->{tax}->{$f[0]} = join "\0", @f[1..3];
    };
    close $fh;
    $self->{fh} = undef;

}

1;


__END__

=head1 NAME

BioX::Tax::Kraken - simple access to Kraken-style taxDB taxonomy database

=head1 SYNOPSIS

    use BioX::Tax::Kraken;

    my $seq = BioX::Seq->new();

    for (qw/AATG TAGG CCAT TTGA/) {
        $seq .= $_;
    }

    $seq->id( 'test_seq' );

    my $rc = $seq->rev_com(); # original untouched
    print $seq->as_fasta();

    # >test_seq
    # AATGTAGGCCATTTGA

    $seq->rev_com(); # original modified in-place
    print $seq->as_fastq(22);

    # @test_seq
    # TCAAATGGCCTACATT
    # +
    # 7777777777777777

    print $seq->range(3,6)->as_fasta();

    # >test_seq
    # AAAT

=head1 DESCRIPTION

C<BioX::Seq> is a simple sequence class that can be used to represent
biological sequences. It was designed as a compromise between using simple
strings and hashes to hold sequences and using the rather bloated objects of
Bioperl. Features (or, depending on your viewpoint, bugs) include
auto-stringification and context-dependent transformations. It is meant be
used primarily as the return object of the C<BioX::Seq::Stream> and
C<BioX::Seq::Fetch> parsers, but there may be occasions where it is useful in
its own right.

C<BioX::Seq> current implements a small subset of the transformations most
commonly used by the author (reverse complement, translate, subrange) - more
methods may be added in the future as use suggests and time permits, but the
core object will be kept as simple as possible and should be limited to the
four current properties - sequence, ID, description, and quality - that
satisfy 99% of the author's needs.

Some design decisions have been made for the sake of speed over ease of use.
For instance, there is no sanity-checking of the object properties upon
creation of a new object or use of the accessor methods. Parameters to the
constructor are positional rather than named (testing indicates that this
reduces execution times by ~ 40%). 

=head1 METHODS

=over 4

=item B<new>

=item B<new> I<SEQUENCE>

=item B<new> I<SEQUENCE> I<ID>

=item B<new> I<SEQUENCE> I<ID> I<DESCRIPTION>

=item B<new> I<SEQUENCE> I<ID> I<DESCRIPTION> I<QUALITY>

Create a new C<BioX::Seq> object (empty by default). All arguments are optional
but are positional and, if provided, must be given in order.

    $seq = BioX::Seq->new( SEQ, ID, DESC, QUALITY );

Returns a new C<BioX::Seq> object.

=item B<seq>, B<id>, B<desc>, B<qual>

Accessors to the object properties named accordingly. Properties can also be
accessed directly as hash keys. This is probably frowned upon by some, but can be
useful at times e.g. to perform substution on a property in-place.

    $seq->{id} =~ s/^Unnecessary_prefix//;

Takes zero or one arguments. If an argument is given, assigns that value to the
property in question. Returns the current value of the property.

=item B<range> I<START> I<END>

Extract a subsequence from I<START> to I<END>. Coordinates are 1-based.

Returns a new BioX::Seq object, or I<undef> if the coordinates are outside the
limits of the parent sequence.

=item B<rev_com>

Reverse complement the sequence.

Behavior is context-dependent. In scalar or list context, returns a new
BioX::Seq object containing the reverse-complemented sequence, leaving the
original sequence untouched. In void context, updates the original sequence
in-place and returns TRUE if successful.

=item B<translate>

=item B<translate> I<FRAME>

Translate a nucleic acid sequence to a peptide sequence.

I<FRAME> specifies the starting point of the translation. The default is zero.
A I<FRAME> value of 0-2 will return the translation of each of the three
forward reading frames, respectively, while a value of 3-5 will return the
translation of each of the three reverse reading frames, respectively.

=item B<as_fasta>

=item B<as_fasta> I<LINE_LENGTH>

Returns a string representation of the sequence in FASTA format. Requires
that, at a minimum, the <seq> and <id> properties be defined. I<LINE_LENGTH>,
if given, specifies the line length for wrapping purposes (default: 60).

=item B<as_fastq>

=item B<as_fastq> I<DEFAULT_QUALITY>

Returns a string representation of the sequence in FASTQ format. Requires
that, at a minimum, the <seq> and <id> properties be defined.
I<DEFAULT_QUALITY>, if given, specifies the default Phred quality score to be
assigned to each base if missing - for instance, if converting from FASTA to
FASTQ (default: 20).

=item B<as_input>

=item B<as_input> I<ARGUMENT>

If the sequence object comes from a C<BioX::Seq::Stream> instance, this method
will format the sequence to match the input format, calling either
C<BioX::Seq::as_fasta> or C<BioX::Seq::as_fastq> as appropriate. The optional
argument, if given, will be passed on to the appropriate method and evaluated
in that context. Throws an error if the input format cannot be deduced
(probably because the object was not created by a C<BioX::Seq::Stream> parser).

=back

=head1 CAVEATS AND BUGS

No input validation is performed during construction or modification of the
object properties.

Performing certain operations (for instance, s///) on a BioX::Seq object
relying on auto-stringification may convert the object into a simple unblessed
scalar containing the sequence string. You will likely know if this happens
(you are using strict and using warnings, right?) because your script will
throw an error if you try to perform a class method on the (now) unblessed
scalar.

Please reports bugs or feature requests through the issue tracker at
L<https://github.com/jvolkening/p5-BioX-Seq/issues>.

=head1 AUTHOR

Jeremy Volkening <jeremy.volkening *at* base2bio.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2014-2022 Jeremy Volkening

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program.  If not, see <http://www.gnu.org/licenses/>.

=cut

