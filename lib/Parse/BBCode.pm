package Parse::BBCode;
use strict;
use warnings;
use Parse::BBCode::Tag;
use base 'Class::Accessor::Fast';
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(qw/ tag_def tags compiled plain strict_attributes
    close_open_tags error tree /);
use URI::Escape;
use Data::Dumper;
use Carp;

our $VERSION = '0.03';

my %defaults = (
    strict_attributes => 1,
);
sub new {
    my ($class, $args) = @_;
    my $self = $class->SUPER::new({
        %defaults,
        %$args
    });
    return $self;
}

my $re_split = qr{ % (?:\{ (?:[a-zA-Z\|]+) \})? (?:[Aas]) }x;
my $re_cmp = qr{ % (?:\{ ([a-zA-Z\|]+) \})? ([Aas]) }x;

sub _compile_tags {
    my ($self) = @_;
    unless ($self->get_compiled) {
        my $defs = $self->get_tag_def;

        # get definition for how text should be rendered wwhich is not in tags
        my $plain;
        if (exists $defs->{""}) {
            $plain = delete $defs->{""};
            if (ref $plain eq 'CODE') {
                $self->set_plain($plain);
            }
        }
        else {
            $plain = sub {
                Parse::BBCode::escape_html($_[1]);
                $_[1] =~ s/\r?\n|\r/<br>\n/g;
                $_[1];
            };
            $self->set_plain($plain);
        }

        # now compile the rest of definitions
        for my $key (keys %$defs) {
            my $def = $defs->{$key};
            #warn __PACKAGE__.':'.__LINE__.": $key: $def\n";
            if (not ref $def) {
                my $new_def = $self->_compile_def($def);
                $defs->{$key} = $new_def;
            }
            elsif (not exists $def->{code} and exists $def->{output}) {
                my $new_def = $self->_compile_def($def);
                $defs->{$key} = $new_def;
            }
            $defs->{$key}->{class} ||= 'inline';
        }
        $self->set_compiled(1);
    }
}

sub _compile_def {
    my ($self, $def) = @_;
    my $parse = 0;
    my $new_def = {};
    my $output = $def;
    my $close = 1;
    if (ref $def eq 'HASH') {
        $new_def = { %$def };
        $output = delete $new_def->{output};
        $parse = $new_def->{parse};
        $close = $new_def->{close} if exists $new_def->{close};
    }
    else {
    }
    # we have a string, compile
    #warn __PACKAGE__.':'.__LINE__.": $key => $output\n";
    my $class = 'inline';
    if ($output =~ s/^(inline|block)://) {
        $class = $1;
    }
    my @parts = split m!($re_split)!, $output;
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@parts], ['parts']);
    my @compiled;
    for my $p (@parts) {
        if ($p =~ m/$re_cmp/) {
            my ($escape, $type) = ($1, $2);
            $escape ||= 'parse';
            my @escapes = split /\|/, $escape;
            if (grep { $_ eq 'parse' } @escapes) {
                $parse = 1;
            }
            push @compiled, [\@escapes, $type];
        }
        else {
            push @compiled, $p;
        }
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@compiled], ['compiled']);
    }
    my $code = sub {
        my ($self, $attr, $string, $fallback) = @_;
        my $out = '';
        for my $c (@compiled) {

            # just text
            unless (ref $c) {
                #$out .= $self->_render_text($c);
                $out .= $c;
            }
            # tag attribute or content
            else {
                my ($escapes, $type) = @$c;
                my $var;
                if ($type eq 'a') {
                    $var = $attr;
                }
                elsif ($type eq 'A') {
                    $var = $fallback;
                }
                elsif ($type eq 's') {
                    if (ref $string eq 'SCALAR') {
                        # this text is already finished and escaped
                        $string = $$string;
                    }
                    $var = $string;
                }
                for my $e (@$escapes) {
                    if ($e eq 'html') {
                        $var = escape_html($var);
                    }
                    elsif ($e eq 'uri') {
                        $var = uri_escape($var);
                    }
                    elsif ($e eq 'URL') {
                        if ($var =~ m{^[a-z]+://}i) {
                            $var = escape_html($var);
                        }
                        elsif ($var =~ m{^\s*[a-z]+\s*:}i) {
                            # invalid
                            $var = '';
                        }
                        else {
                            $var = escape_html($var);
                        }
                    }
                }
                $out .= $var;
            }
        }
        return $out;
    };
    $new_def->{parse} = $parse;
    $new_def->{code} = $code;
    $new_def->{close} = $close;
    $new_def->{class} = $class;
    return $new_def;
}

sub _render_text {
    my ($self, $text) = @_;
    defined (my $code = $self->get_plain) or return $text;
    return $code->($self, $text);
}

sub parse {
    my ($self, $text) = @_;
    $self->_compile_tags;
    my $defs = $self->get_tag_def;
    my $tags = $self->get_tags || [keys %$defs];
    my $re = join '|', map { quotemeta } sort {length $b <=> length $a } @$tags;
    $re = qr/$re/i;
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$re], ['re']);
    my @tags;
    my $out = '';
    my @opened;
    my $current_open_re = '';
    my $callback_found_text = sub {
        my ($text) = @_;
        if (@opened) {
            my $o = $opened[-1];
            $o->add_content($text);
        }
        else {
            push @tags, $text;
        }
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@opened], ['opened']);
    };
    my $callback_found_tag;
    $callback_found_tag = sub {
        my ($tag) = @_;
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$tag], ['tag']);
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@opened], ['opened']);
        if (@opened) {
            my $o = $opened[-1];
            my $class = $o->get_class;
            #warn __PACKAGE__.':'.__LINE__.": tag $tag\n";
            if (ref $tag and $class eq 'inline' and $tag->get_class eq 'block') {
                $self->_add_error('block_inline', $tag);
                #warn __PACKAGE__.':'.__LINE__.": !!!!!!!!!!! $o\n";
                pop @opened;
                #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$o], ['o']);
                if ($self->get_close_open_tags) {
                    # we close the tag for you
                    $self->_finish_tag($o, '[/' . $o->get_name . ']');
                    $callback_found_tag->($o);
                    $callback_found_tag->($tag);
                }
                else {
                    # nope, no automatic closing, invalidate all
                    # open inline tags before
                    my @red = $o->_reduce;
                    $callback_found_tag->($_) for @red;
                    $callback_found_tag->($tag);
                }
            }
            else {
                $o->add_content($tag);
            }
        }
        else {
            push @tags, $tag;
        }
        $current_open_re = join '|', map {
            quotemeta $_->get_name
        } @opened;

    };
    my @class = 'block';
    while ($text) {
        #warn __PACKAGE__.':'.__LINE__.": ============= match $text\n";
        my ($before, $tag, $after) = split m{ \[ ($re) (?=\b|\]|\=) }x, $text, 2;
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@opened], ['opened']);
        { no warnings;
        #warn __PACKAGE__.':'.__LINE__.": $before, $tag, $after)\n";
        #warn __PACKAGE__.':'.__LINE__.": RE: $current_open_re\n";
        }
        if (length $before) {
            # look if it contains a closing tag
            #warn __PACKAGE__.':'.__LINE__.": BEFORE $before\n";
            while (length $current_open_re and $before =~ s# (.*?) (\[ / ($current_open_re) \]) ##ixs) {
                # found closing tag
                my ($content, $end, $name) = ($1, $2, $3);
                #warn __PACKAGE__.':'.__LINE__.": found closing tag $name!\n";
                my $f;
                # try to find the matching opening tag
                my @not_close;
                while (@opened) {
                    my $try = pop @opened;
                    $current_open_re = join '|', map {
                        quotemeta $_->get_name
                    } @opened;
                    if ($try->get_name eq $name) {
                        $f = $try;
                        last;
                    }
                    elsif (!$try->get_close) {
                        $self->_finish_tag($try, '');
                        unshift @not_close, $try;
                    }
                    else {
                        # unbalanced, just add unparsed text
                        $callback_found_tag->($_) for $try->_reduce;
                    }
                }
                if (@not_close) {
                    $not_close[-1]->add_content($content);
                }
                for my $n (@not_close) {
                    $f->add_content($n);
                    #$callback_found_tag->($n);
                }
                # add text before closing tag as content to the current open tag
                if ($f) {
                    unless (@not_close) {
                        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$f], ['f']);
                        $f->add_content( $content );
                    }
                    # TODO
                    $self->_finish_tag($f, $end);
                    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$f], ['f']);
                    $callback_found_tag->($f);
                }
            }
            #warn __PACKAGE__." === before=$before ($tag)\n";
            $callback_found_text->($before);
        }
        if ($after) {
            #warn __PACKAGE__.':'.__LINE__.": find attribute for $tag\n";
            if ($after =~ s/^(=[^\]]*)?]//) {
                my $attr = $1;
                $attr = '' unless defined $attr;
                #warn __PACKAGE__.':'.__LINE__.": found attribute for $tag: $attr\n";
                my $open = Parse::BBCode::Tag->new({
                        name => lc $tag,
                        attr => [],
                        content => [],
                        start => "[$tag$attr]",
                        close => $defs->{lc $tag}->{close},
                        class => $defs->{lc $tag}->{class},
                    });
                my $success = $self->_validate_attr($open, $attr);
                if ($success) {
                    push @opened, $open;
                    my $def = $defs->{lc $tag};
                    #warn __PACKAGE__.':'.__LINE__.": $tag $def\n";
                    my $parse = $def->{parse};
                    if ($parse) {
                        $current_open_re = join '|', map {
                            quotemeta $_->get_name
                        } @opened;
                    }
                    else {
                        #warn __PACKAGE__.':'.__LINE__.": noparse, find content\n";
                        # just search for closing tag
                        if ($after =~ s# (.*?) (\[ / $tag \]) ##xs) {
                            my $content = $1;
                            my $end = $2;
                            #warn __PACKAGE__.':'.__LINE__.": CONTENT $content\n";
                            my $finished = pop @opened;
                            $finished->set_content([$content]);
                            # TODO
                            $self->_finish_tag($finished, $end);
                            $callback_found_tag->($finished);
                        }
                        else {
                            #warn __PACKAGE__.':'.__LINE__.": nope '$after'\n";
                        }
                    }
                }
                else {
                    $callback_found_text->($open->get_start);
                }

            }
            else {
                # unclosed tag
                $callback_found_text->("[$tag");
            }
        }
        elsif ($tag) {
            #warn __PACKAGE__.':'.__LINE__.": end\n";
            $callback_found_text->("[$tag");
        }
        $text = $after;
        #sleep 1;
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@tags], ['tags']);
    }
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@opened], ['opened']);
    if ($self->get_close_open_tags) {
        while (my $opened = pop @opened) {
            $self->_add_error('unclosed', $opened);
            $self->_finish_tag($opened, '[/' . $opened->get_name . ']');
            $callback_found_tag->($opened);
        }
    }
    else {
        while (my $opened = shift @opened) {
            #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$opened], ['opened']);
            my @text = $opened->_reduce;
            push @tags, @text;
        }
    }
    #warn __PACKAGE__.':'.__LINE__.": !!!!!!!!!!!! left text: '$text'\n";
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@tags], ['tags']);
    my $tree = Parse::BBCode::Tag->new({
        name => '',
        content => [@tags],
        start => '',
        class => 'block',
        attr => [[]],
    });
    return $tree;
}

sub _add_error {
    my ($self, $error, $tag) = @_;
    my $errors = $self->get_error || {};
    push @{ $errors->{$error} }, $tag;
    $self->set_error($errors);
}

sub error {
    my ($self, $type) = @_;
    my $errors = $self->get_error || {};
    if ($type and $errors->{$type}) {
        return $errors->{$type};
    }
    elsif ($errors) {
        return $errors;
    }
    return 0;
}

sub render {
    my ($self, $text) = @_;
    if (@_ < 2) {
        croak ("Missing input - Usage: \$parser->render(\$text)");
    }
    #warn __PACKAGE__.':'.__LINE__.": @_\n";
    #sleep 2;
    my $tree = $self->parse($text);
    my $out = $self->render_tree($tree);
    if ($self->get_error) {
        $self->set_tree($tree);
    }
    return $out;
}

sub render_tree {
    my ($self, $tree) = @_;
    my $out = '';
    my $defs = $self->get_tag_def;
    for my $el (ref $tree eq 'ARRAY' ? @$tree : $tree) {
        if (ref $el) {
            my $name = $el->get_name;
            my $code = $defs->{$name}->{code};
            my $parse = $defs->{$name}->{parse};
            my $attr = $el->get_attr->[0]->[0];
            my $content = $el->get_content;
            my $fallback = (defined $attr and length $attr) ? $attr : $content;
            if (ref $fallback) {
                # we have recursive content, we don't want that in
                # an attribute
                $fallback = join '', grep {
                    not ref $_
                } @$fallback;
            }
            if (not exists $defs->{$name}->{parse} or $parse) {
                $content = $self->render_tree($content);
            }
            else {
                $content = join '', @$content;
            }
            if ($code) {
                my $o = $code->($self, $attr, \$content, $fallback, $el);
                $out .= $o;
            }
            else {
                $out .= $content;
            }
        }
        else {
            #warn __PACKAGE__.':'.__LINE__.": ==== $el\n";
            my $test = $self->_render_text($el);
            #warn __PACKAGE__.':'.__LINE__.": ==== $test\n";
            $out .= $self->_render_text($el);
        }
    }
    return $out;
}


sub escape_html {                                                                                          
    my ($str) = @_;
    return '' unless defined $str;
    $str =~ s/&/&amp;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/'/&#39;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/</&lt;/g;
    return $str;
}

sub _validate_attr {
    my ($self, $tag, $attr) = @_;
    $tag->set_attr_raw($attr);
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$attr], ['attr']);
    my @array;
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$attr], ['attr']);
    unless (length $attr) {
        $tag->set_attr([]);
        return 1;
    }
    $attr =~ s/^=//;
    if ($self->get_strict_attributes and not length $attr) {
        return 0;
    }
    if ($attr =~ s/^(?:"([^"]+)"|(.*?)(?:\s+|$))//) {
        my $val = defined $1 ? $1 : $2;
        push @array, [$val];
    }
    while ($attr =~ s/^([a-zA-Z0-9]+)=(?:"([^"]+)"|(.*?)(?:\s+|$))//) {
        my $name = $1;
        my $val = defined $2 ? $2 : $3;
        push @array, [$name, $val];
    }
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@array], ['array']);
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$attr], ['attr']);
    if ($self->get_strict_attributes and length $attr) {
        return 0;
    }
    $tag->set_attr(\@array);
    return 1;
}

# TODO add callbacks
sub _finish_tag {
    my ($self, $tag, $end) = @_;
    #warn __PACKAGE__.':'.__LINE__.": _finish_tag(@_)\n";
    #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$tag], ['tag']);
    unless ($tag->get_finished) {
        $tag->set_end($end);
        $tag->set_finished(1);
    }
    return 1;
}

__END__

=pod

=head1 NAME

Parse::BBCode - Module to turn BBCode into HTML or plain text

=head1 SYNOPSIS

    my $p = Parse::BBCode->new({
            tag_def => {
                url => '<a href="%{URL}a">%{parse}s</a>',
                i   => '<i>%{parse}s</i>',
                b   => '<b>%{parse}s</b>',
                noparse => '<pre>%{html}s</pre>',
                code => sub {
                    my ($parser, $attr, $content, $attribute_fallback) = @_;
                    if ($attr eq 'perl') {
                        # use some syntax highlighter
                        $content = highlight_perl($content);
                    }
                    else {
                        $content = Parse::BBCode::escape_html($content);
                    }
                    "<tt>$content</tt>"
                },
            },
            tags => [qw/ i b noparse url code /],
        }
    );
    my $code = 'some [b]b code[/b]';
    my $parsed = $p->render($code);

=head1 DESCRIPTION

Note: This module is still experimental, the syntax is subject to
change. I'm open for any suggestions on how to improve the
syntax.

I wrote this module because L<HTML::BBCode> is not extendable (or
I didn't see how) and L<BBCode::Parser> seemed good at the first
glance but has some issues, for example it says that he following bbode

    [code] foo [b] [/code]

is invalid, while I think you should be able to write unbalanced code
in code tags. The approach of Parse::BBCode is lazy parsing, so it's
always parsing only one level, and depending on the definition of
the tag the inner content is parsed or - e.g. in code tags - not.
Also BBCode::Parser dies if you have invalid code or not-permitted tags,
but in a forum you'd rather show a party parsed text then an error
message.

What I also wanted is an easy syntax to define own tags, ideally - for
simple tags - as plain text, so you can put it in a configuration file.
This allows forum admins to add tags easily. Some forums might want
a tag for linking to perlmonks.org, other forums need other tags.

Another goal was to always output a result and don't die. I might add an
option which lets the parser die with unbalanced code.

=head2 METHODS

=over 4

=item new

Constructor. Takes a hash reference with options as an argument.

=over 4

=item tag_def

See L<"TAG DEFINITIONS">

=item tags

an array ref which lists the allowed tag names (this way you can define more
tags but allow only a part of them. If left undef it uses all tags listed
in the tag_def option).

=back

=item parse

Input: The text to parse.

Returns: the parsed tree.

    my $tree = $parser->parse($bbcode);

=item render

Input: The text to parse

Returns: the rendered text

    my $parsed = $parser->render($bbcode);

=item render_tree

Input: the parse tree

Returns: The rendered text

    my $parsed = $parser->parse_tree($tree);

=item escape_html

Utility to substitute

    <>&"'

with their HTML entities.

=item error

If the given bbcode is invalid (unbalanced or wrongly nested classes),
currently Parse::BBCode::render() will either leave the invalid tags
unparsed, or, if you set the option C<close_open_tags>, try to add closing
tags.
If this happened C<error()> will return the invalid tag(s), otherwise false.
To get the corrected bbcode (if you set C<close_open_tags>) you can get
the tree and return the raw text from it:

    if ($parser->error) {
        my $tree = $parser->get_tree;
        my $corrected = $tree->raw_text;
    }

=back


=head2 TAG DEFINITIONS

Here is an example of all the current definition possibilities:

    my $p = Parse::BBCode->new({
            tag_def => {
                '' => sub { Parse::BBCode::escape_html($_[1]) },
                i   => '<i>%s</i>',
                b   => '<b>%{parse}s</b>',
                size => '<font size="%a">%{parse}s</font>',
                url => '<a href="%{URL}A">%{parse}s</a>',
                wikipedia => '<a href="http://wikipedia.../?search=%{uri}A">%{parse}s</a>',
                noparse => '<pre>%{html}s</pre>',
                code => {
                    code => sub {
                        my ($parser, $attr, $content, $attribute_fallback) = @_;
                        if ($attr eq 'perl') {
                            # use some syntax highlighter
                            $content = highlight_perl($content);
                        }
                        else {
                            $content = Parse::BBCode::escape_html($content);
                        }
                        "<tt>$content</tt>"
                    },
                    parse => 0,
                },
            },
            tags => [qw/ i b size url wikipedia noparse code /],
        }
    );

The following list explains the above tag definitions:

=over 4

=item empty string

This defines how plain text should be rendered:

    '' => sub { Parse::BBCode::escape_html($_[1]) }

In the most cases, you would want HTML escaping like shown above.
This is the default, so you can leave it out. Only if you want
to render BBCode into plain text or something else, you need this
option.

=item i

    i => '<i>%s</i>'

    [i] italic <html> [/i]
    turns out as
    <i> italic &lt;html&gt; </i>

So C<%s> stands for the tag content. By default, it is parsed itself,
so that you can nest tags.

=item b

    b   => '<b>%{parse}s</b>'

    [b] bold <html> [/b]
    turns out as
    <b> bold &lt;html&gt; </b>

C<%{parse}s> is the same as C<%s> as 'parse' is the default.

=item size

    size => '<font size="%a">%{parse}s</font>'

    [size=7] some big text [/size]
    turns out as
    <font size="7"> some big text [/size]

So %a stands for the tag attribute. By default it will be HTML
escaped.

=item url

    url => '<a href="%{URL}a">%{parse}s</a>'

Here you can see how to apply a special escape. The attribute
defined with C<%{URL}a> is checked for a valid URL.
C<javascript:> will be filtered.

    [url=/foo.html]a link[/url]
    turns out as
    <a href="/foo.html">a link</a>

Note that a tag like

    [url]http://some.link.example[/url]

will turn out as

    <a href="">http://some.link.example</a>

In the cases where the attribute should be the same as the
content you should use C<%A> instead of C<%a> which takes
the content as the attribute as a fallback. You probably
need this in all url-like tags.

    url => '<a href="%{URL}A">%{parse}s</a>',

=item wikipedia

You might want to define your own urls, e.g. for wikipedia
references:

    wikipedia => '<a href="http://wikipedia.../?search=%{uri}A">%{parse}s</a>',

C<%{uri}A> will uri-encode the searched term:

    [wikipedia]Harold & Maude[/wikipedia]
    [wikipedia="Harold & Maude"]a movie[/wikipedia]
    turns out as
    <a href="http://wikipedia.../?search=Harold+%26+Maude">Harold &amp; Maude</a>
    <a href="http://wikipedia.../?search=Harold+%26+Maude">a movie</a>

=item noparse

Sometimes you need to display verbatim bbcode. The simplest
form would be a noparse tag:

    noparse => '<pre>%{html}s</pre>'

    [noparse] [some]unbalanced[/foo] [/noparse]

With this definition the output would be

    <pre>[some]unbalanced[/foo]</pre>

So inside a noparse tag you can write (almost) any invalid bbcode.
The only exception is the noparse tag itself:

    [noparse] [some]unbalanced[/foo] [/noparse] [b]really bold[/b] [/noparse]

Output:

    [some]unbalanced[/foo] <b>really bold</b> [/noparse]

Because the noparse tag ends at the first closing tag, even if you
have an additional opening noparse tag inside.

The C<%{html}s> defines that the content should be HTML escaped.
If you don't want any escaping you can't say C<%s> because the default
is 'parse'. In this case you have to write C<%{noescape}>.

=item code

All these definitions might not be enough if you want to define
your own code, for example to add a syntax highlighter.

Here's an example:

    code => {
        code => sub {
            my ($parser, $attr, $content, $attribute_fallback) = @_;
            if ($attr eq 'perl') {
                # use some syntax highlighter
                $content = highlight_perl($$content);
            }
            else {
                $content = Parse::BBCode::escape_html($$content);
            }
            "<tt>$content</tt>"
        },
        parse => 0,
    },

So instead of a string you define a hash reference with a 'code'
key and a sub reference.
The other key is C<parse> which is 0 by default. If it is 0 the
content in the tag won't be parsed, just as in the noparse tag above.
If it is set to 1 you will get the rendered content as an argument to
the subroutine.

The first argument to the subroutine is the Parse::BBCode object itself.
The second argument is the attribute, the third the tag content as a
scalar reference and the fourth argument is the attribute fallback which
is set to the content if the attribute is empty. The fourth argument
is just for convenience.

=back

=head1 TODO

Possibility to define which urls accepted, add some default tags.

=head1 REQUIREMENTS

perl >= 5.6.1, L<Class::Accessor::Fast>, L<URI::Escape>

=head1 AUTHOR

Tina Mueller

=head1 CREDITS

Thanks to Moritz Lenz for his suggestions about the implementation
and the test cases.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Tina Mueller

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself, either Perl version 5.6.1 or, at your option,
any later version of Perl 5 you may have available.

=cut
