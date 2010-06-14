package Parse::BBCode::HTML;
use strict;
use warnings;
use Data::Dumper;
use Carp qw(croak carp);
use URI::Escape;
use base 'Exporter';
our @EXPORT_OK = qw/ &defaults &default_escapes &optional /;

our $VERSION = '0.03';
my $email_valid = 0;
eval {
    require
        Email::Valid;
};
$email_valid = 1 unless $@;

my %default_tags = (
    'b'     => '<b>%s</b>',
    'i'     => '<i>%s</i>',
    'u'     => '<u>%s</u>',
    'img'   => '<img src="%{html}A" alt="[%{html}s]" title="%{html}s">',
    'url'   => 'url:<a href="%{link}A" rel="nofollow">%s</a>',
    'email' => 'url:<a href="mailto:%{email}A">%s</a>',
    'size'  => '<span style="font-size: %{num}a">%s</span>',
    'color' => '<span style="color: %{htmlcolor}a">%s</span>',
    'list'  => {
        parse => 1,
        class => 'block',
        code => sub {
            my ($parser, $attr, $content, $attribute_fallback, $tag) = @_;
            $$content =~ s/^\n+//;
            $$content =~ s/\n+\z//;
            return "<ul>$$content</ul>";
        },
    },
    '*' => {
        parse => 1,
        code => sub {
            my ($parser, $attr, $content, $attribute_fallback, $tag) = @_;
            $$content =~ s/\n+\z//;
            return "<li>$$content</li>",
        },
        close => 0,
        class => 'block',
    },
    'quote' => 'block:<div class="bbcode_quote_header">%{html}a:
<div class="bbcode_quote_body">%s</div></div>',
    'code'  => 'block:<div class="bbcode_code_header">%{html}a:
<div class="bbcode_code_body">%{html}s</div></div>',
    'noparse' => '%{html}s',
);
my %optional_tags = (
    'html' => '%{noescape}s',
);

my %default_escapes = (
    html => sub {
        Parse::BBCode::escape_html($_[2]),
    },
    uri => sub {
        uri_escape($_[2]),
    },
    link => sub {
        my ($p, $tag, $var) = @_;
        if ($var =~ m{^[a-z]+://}i) {
        }
        elsif ($var =~ m{^\s*[a-z]+\s*:}i) {
            # invalid
            return;
        }
        $var = Parse::BBCode::escape_html($var);
        return $var;
    },
    email => $email_valid ? sub {
        my ($p, $tag, $var) = @_;
        # extracts the address part of the email or undef
        my $valid = Email::Valid->address($var);
        return $valid ? Parse::BBCode::escape_html($valid) : '';
    } : sub {
        my ($p, $tag, $var) = @_;
        $var = Parse::BBCode::escape_html($var);
    },
    htmlcolor => sub {
        $_[2] =~ m/^(?:[a-z]+|#[0-9a-f]{6})\z/ ? $_[2] : 'inherit'
    },
    num => sub {
        $_[2] =~ m/^[0-9]+\z/ ? $_[2] : 0;
    },
);


sub defaults {
    my ($class, @keys) = @_;
    return @keys
        ? (map { $_ => $default_tags{$_} } grep { defined $default_tags{$_} } @keys)
        : %default_tags;
}

sub default_escapes {
    my ($class, @keys) = @_;
    return @keys
        ? (map { $_ => $default_escapes{$_} } grep  { defined $default_escapes{$_} } @keys)
        : %default_escapes;
}

sub optional {
    my ($class, @keys) = @_;
    return @keys ? (grep defined, @optional_tags{@keys}) : %optional_tags;
}



1;

__END__

=pod

=head1 NAME

Parse::BBCode::HTML - Provides HTML defaults for Parse::BBCode

=head1 SYNOPSIS

    use Parse::BBCode;
    # my $p = Parse::BBCode->new();
    my $p = Parse::BBCode->new({
        tags => {
            Parse::BBCode::HTML->defaults,
            # add your own tags here if needed
        },
        escapes => {
            Parse::BBCode::HTML->default_escapes,
            # add your own escapes here if needed
        },
    });
    my $code = 'some [b]b code[/b]';
    my $parsed = $p->render($code);

=head1 METHODS

=over 4

=item defaults

Returns a hash with default tags.

    b, i, u, img, url, email, size, color, list, *, quote, code

=item default_escapes

Returns a hash with escaping functions. These are:

    html, uri, link, email, htmlcolor, num

=item optional

Returns a hash of optional tags. These are:

    html

=back

=cut

