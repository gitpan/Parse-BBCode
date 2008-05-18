package Parse::BBCode::Tag;
use strict;
use warnings;
use Carp qw(croak carp);

our $VERSION = '0.02';
use base 'Class::Accessor::Fast';
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(qw/ name attr attr_raw content
    finished start end close class /);

sub add_content {
    my ($self, $new) = @_;
    my $content = $self->get_content;
    if (ref $new) {
        push @$content, $new;
        return;
    }
    if (@$content and not ref $content->[-1]) {
        $content->[-1] .= $new;
    }
    else {
        push @$content, $new;
    }
}

sub raw_text {
    my ($self) = @_;
    my ($start, $end) = ($self->get_start, $self->get_end);
    my $text = $start;
    $text .= $self->raw_content;
    no warnings;
    $text .= $end;
    return $text;
}

sub raw_content {
    my ($self) = @_;
    my $content = $self->get_content;
    my $text = '';
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$self], ['self']);
    for my $c (@$content) {
        if (ref $c eq ref $self) {
            $text .= $c->raw_text;
        }
        else {
            $text .= $c;
        }
    }
    return $text;
}

sub _reduce {
    my ($self) = @_;
    if ($self->get_finished) {
        return $self;
    }
    my @text = $self->get_start;
    my $content = $self->get_content;
    for my $c (@$content) {
        if (ref $c eq ref $self) {
            push @text, $c->_reduce;
        }
        else {
            push @text, $c;
        }
    }
    push @text, $self->get_end if defined $self->get_end;
    return @text;
}


1;

__END__

=pod

=head1 NAME

Parse::BBCode::Tag - Tag Class for Parse::BBCode

=head1 DESCRIPTION

If you parse a bbcode with L<Parse::BBCode> C<Parse::BBCode::parse> returns
a parse tree of Tag objects.

=head1 METHODS

=over 4

=item add_content

    $tag->add_content('string');

Adds 'string' to the end of the tag content.

    $tag->add_content($another_tag);

Adds C<$another_tag> to the end of the tag content.

=item raw_text

    my $bbcode = $tag->raw_text;

Returns the raw text of the parse tree, so all tags are converted
back to bbcode.

=item raw_content

    my $bbcode = $tag->raw_text;

Returns the raw content of the tag without the opening and closing tags.
So if you have tag that was parsed from

    [i]italic and [bold]test[/b][/i]

it will return

    italic and [bold]test[/b]

=back

=head1 ACCESSORS

The accessors of a tag are currently

    name attr attr_raw content finished start end close class

You can call each accessor with C<get_*> and C<set_*>

=over 4

=item name

The tag name. for C<[i]...[/i]> it is C<i>, the lowercase tag name.

=item attr

TODO

=item attr_raw

The raw text of the attribute

=item content

An arrayref of the content of the tag, each element either a string
or a tag itself.

=item finished

Used during parsing, true if the end of the tag was found.

=item start

The original start string, e.g. 'C<[size=7]>'

=item end

The original end string, e.g. 'C<[/size]>'

=item close

True if the tag needs a closing tag. A tag which doesn't need a closing
tag is C<[*]> for example, inside of C<[list]> tags.

=item class

'block' or 'inline'

=back

=cut


