package Parse::BBCode::Tag;
use strict;
use warnings;
use Carp qw(croak carp);

our $VERSION = '0.01';
use base 'Class::Accessor::Fast';
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(qw/ name attr attr_raw content children
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
