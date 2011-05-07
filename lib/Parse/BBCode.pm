package Parse::BBCode;
use strict;
use warnings;
use Parse::BBCode::Tag;
use Parse::BBCode::HTML qw/ &defaults &default_escapes &optional /;
use base 'Class::Accessor::Fast';
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(qw/ tags allowed compiled plain strict_attributes
    close_open_tags error tree escapes direct_attribute /);
use Data::Dumper;
use Carp;
my $scalar_util = eval "require Scalar::Util; 1";

our $VERSION = '0.12';

my %defaults = (
    strict_attributes   => 1,
    direct_attribute    => 1,
);
sub new {
    my ($class, $args) = @_;
    $args ||= {};
    my %args = %$args;
    unless ($args{tags}) {
        $args{tags} = { $class->defaults };
    }
    else {
        $args{tags} = { %{ $args{tags} } };
    }
    unless ($args{escapes}) {
        $args{escapes} = {$class->default_escapes };
    }
    else {
        $args{escapes} = { %{ $args{escapes} } }
    }
    my $self = $class->SUPER::new({
        %defaults,
        %args
    });
    $self->set_allowed([ grep { length } keys %{ $self->get_tags } ]);
    return $self;
}

my $re_split = qr{ % (?:\{ (?:[a-zA-Z\|]+) \})? (?:attr|[Aas]) }x;
my $re_cmp = qr{ % (?:\{ ([a-zA-Z\|]+) \})? (attr|[Aas]) }x;

sub forbid {
    my ($self, @tags) = @_;
    my $allowed = $self->get_allowed;
    my $re = join '|', map { quotemeta } @tags;
    @$allowed = grep { ! m/^(?:$re)\z/ } @$allowed;
}

sub permit {
    my ($self, @tags) = @_;
    my $allowed = $self->get_allowed;
    my %seen;
    @$allowed = grep {
        !$seen{$_}++ && $self->get_tags->{$_};
    } (@$allowed, @tags);
}

sub _compile_tags {
    my ($self) = @_;
    unless ($self->get_compiled) {
        my $defs = $self->get_tags;

        # get definition for how text should be rendered which is not in tags
        my $plain;
        if (exists $defs->{""}) {
            $plain = delete $defs->{""};
            if (ref $plain eq 'CODE') {
                $self->set_plain($plain);
            }
        }
        else {
            $plain = sub {
                my $text = Parse::BBCode::escape_html($_[2]);
                $text =~ s/\r?\n|\r/<br>\n/g;
                $text;
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
    my $esc = $self->get_escapes;
    my $parse = 0;
    my $new_def = {};
    my $output = $def;
    my $close = 1;
    my $class = 'inline';
    if (ref $def eq 'HASH') {
        $new_def = { %$def };
        $output = delete $new_def->{output};
        $parse = $new_def->{parse};
        $close = $new_def->{close} if exists $new_def->{close};
        $class = $new_def->{class} if exists $new_def->{class};
    }
    else {
    }
    # we have a string, compile
    #warn __PACKAGE__.':'.__LINE__.": $key => $output\n";
    if ($output =~ s/^(inline|block|url)://) {
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
        my ($self, $attr, $string, $fallback, $tag) = @_;
        my $out = '';
        for my $c (@compiled) {

            # just text
            unless (ref $c) {
                $out .= $c;
            }
            # tag attribute or content
            else {
                my ($escapes, $type) = @$c;
                my $var = '';
                my $attributes = $tag->get_attr;
                if ($type eq 'attr' and @$attributes > 1) {
                    my $name = shift @$escapes;
                    for my $item (@$attributes[1 .. $#$attributes]) {
                        if ($item->[0] eq $name) {
                            $var = $item->[1];
                            last;
                        }
                    }
                }
                elsif ($type eq 'a') {
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
                    my $sub = $esc->{$e};
                    if ($sub) {
                        $var = $sub->($self, $c, $var);
                        unless (defined $var) {
                            # if escape returns undef, we return it unparsed
                            return $tag->get_start
                                . (join '', map {
                                    $self->render_tree($_);
                                } @{ $tag->get_content })
                                . $tag->get_end;
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
    my ($self, $tag, $text, $info) = @_;
    #warn __PACKAGE__.':'.__LINE__.": text '$text'\n";
    defined (my $code = $self->get_plain) or return $text;
    return $code->($self, $tag, $text, $info);
}

sub parse {
    my ($self, $text) = @_;
    $self->set_error({});
    $self->_compile_tags;
    my $defs = $self->get_tags;
    my $tags = $self->get_allowed || [keys %$defs];
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
            if (@tags and !ref $tags[-1]) {
                # text tag, concatenate
                $tags[-1] .= $text;
            }
            else {
                push @tags, $text;
            }
        }
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@opened], ['opened']);
    };
    my $callback_found_tag;
    my $in_url = 0;
    $callback_found_tag = sub {
        my ($tag) = @_;
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$tag], ['tag']);
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\@opened], ['opened']);
        if (@opened) {
            my $o = $opened[-1];
            my $class = $o->get_class;
            #warn __PACKAGE__.':'.__LINE__.": tag $tag\n";
            if (ref $tag and $class =~ m/inline|url/ and $tag->get_class eq 'block') {
                $self->_add_error('block_inline', $tag);
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
    while (defined $text and length $text) {
        $in_url = grep { $_->get_class eq 'url' } @opened;
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$in_url], ['in_url']);
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
                    if ($try->get_name eq lc $name) {
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
        $in_url = grep { $_->get_class eq 'url' } @opened;

        if ($after) {
            # found start of a tag
            #warn __PACKAGE__.':'.__LINE__.": find attribute for $tag\n";
            if (
                ($self->get_direct_attribute and $after =~ s/^(=[^\]]*)?]//)
                    or
                ($after =~ s/^( [^\]]*)?\]//)
            ) {
                my $attr = $1;
                $attr = '' unless defined $attr;
                #warn __PACKAGE__.':'.__LINE__.": found attribute for $tag: $attr\n";
                my $open = Parse::BBCode::Tag->new({
                        name    => lc $tag,
                        attr    => [],
                        content => [],
                        start   => "[$tag$attr]",
                        close   => $defs->{lc $tag}->{close},
                        class   => $defs->{lc $tag}->{class},
                        single  => $defs->{lc $tag}->{single},
                        in_url  => $in_url,
                    });
                my $success = $self->_validate_attr($open, $attr);
                my $nested_url = $in_url && $open->get_class eq 'url';
                if ($success && $open->get_single && !$nested_url) {
                    $self->_finish_tag($open, '');
                    $callback_found_tag->($open);
                }
                elsif ($success && !$nested_url) {
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
    if ($scalar_util) {
        Scalar::Util::weaken($callback_found_tag);
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
    # just to make sure no memleak if there's no Scalar::Util
    undef $callback_found_tag;
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
    elsif (keys %$errors) {
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
    my ($self, $tree, $outer, $info) = @_;
    my $out = '';
    $info ||= {
        stack   => [],
        tags    => {},
        classes => {},
    };
    my $defs = $self->get_tags;
    if (ref $tree) {
        my $name = $tree->get_name;
        my %tags = %{ $info->{tags} };
        $tags{$name}++;
        my @stack = @{ $info->{stack} };
        push @stack, $name;
        my %classes = %{ $info->{classes} };
        $classes{ $tree->get_class }++;
        my %info = (
            tags => \%tags,
            stack => [@stack],
            classes => \%classes,
        );
        my $code = $defs->{$name}->{code};
        my $parse = $defs->{$name}->{parse};
        my $attr = $tree->get_attr->[0]->[0];
        my $content = $tree->get_content;
        my $fallback = (defined $attr and length $attr) ? $attr : $content;
        my $string = '';
        if (ref $fallback) {
            # we have recursive content, we don't want that in
            # an attribute
            $fallback = join '', grep {
                not ref $_
            } @$fallback;
        }
        if ($tree->get_class eq 'block') {
            if (@$content == 1 and not ref $content->[0] and defined $content->[0]) {
                $content->[0] =~ s/^\r?\n//;
                $content->[0] =~ s/\r?\n\z//;
            }
            elsif (@$content > 1) {
                if (not ref $content->[0] and defined $content->[0]) {
                    $content->[0] =~ s/^\r?\n//;
                }
                if (not ref $content->[-1] and defined $content->[-1]) {
                    $content->[-1] =~ s/\r?\n\z//;
                }
            }
        }
        if (not exists $defs->{$name}->{parse} or $parse) {
            for my $c (@$content) {
                $string .= $self->render_tree($c, $tree, \%info);
            }
        }
        else {
            $string = join '', @$content;
        }
        if ($code) {
            my $o = $code->($self, $attr, \$string, $fallback, $tree, \%info);
            $out .= $o;
        }
        else {
            $out .= $string;
        }
    }
    else {
        #warn __PACKAGE__.':'.__LINE__.": ==== $tree\n";
        $out .= $self->_render_text($outer, $tree, $info);
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
    my @array;
    unless (length $attr) {
        $tag->set_attr([]);
        return 1;
    }
    if ($self->get_direct_attribute) {
        $attr =~ s/^=//;
    }
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

To parse a bbcode string, set up a parser with the default HTML defintions
of L<Parse::BBCode::HTML>:

    use Parse::BBCode;
    my $p = Parse::BBCode->new();
    my $code = 'some [b]b code[/b]';
    my $parsed = $p->render($code);

Or if you want to define your own tags:

    my $p = Parse::BBCode->new({
            tags => {
                # load the default tags
                Parse::BBCode::HTML->defaults,
                
                # add/override tags
                url => 'url:<a href="%{link}A">%{parse}s</a>',
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
                        $content = Parse::BBCode::escape_html($$content);
                    }
                    "<tt>$content</tt>"
                },
                test => 'this is klingon: %{klingon}s',
            },
            escapes => {
                klingon => sub {
                    my ($parser, $tag, $text) = @_;
                    return translate_into_klingon($text);
                },
            },
        }
    );
    my $code = 'some [b]b code[/b]';
    my $parsed = $p->render($code);

=head1 DESCRIPTION

Note: This module is still experimental, the syntax is subject to
change. I'm open for any suggestions on how to improve the
syntax.
See L<"TODO"> for what might change.


I wrote this module because L<HTML::BBCode> is not extendable (or
I didn't see how) and L<BBCode::Parser> seemed good at the first
glance but has some issues, for example it says that he following bbode

    [code] foo [b] [/code]

is invalid, while I think you should be able to write unbalanced code
in code tags.
Also BBCode::Parser dies if you have invalid code or not-permitted tags,
but in a forum you'd rather show a partly parsed text then an error
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

    my $parser = Parse::BBCode->new({
        tags => {
            url => ...,
            i   => ...,
        },
        escapes => {
            link => ...,
        },
        close_open_tags   => 1, # default 0
        strict_attributes => 0, # default 0
    );

=over 4

=item tags

See L<"TAG DEFINITIONS">

=item escapes

See L<"ESCAPES">

=item close_open_tags

If set to true (1), it will close open tags at the end or before block tags.

=item strict_attributes

If set to true (1), tags with invalid attributes are left unparsed. If set to
false (0), the attribute for this tags will be empty.

An invalid attribute:

    [foo=bar far boo]...[/foo]

I might add an option to define your own attribute validation. Contact me if
you'd like to have this.

=item direct_attributes

Default: true

Normal tag syntax is:

  [tag=val1 attr2=val2 ...]

If set to 0, tag syntax is

  [tag attr2=val2 ...]

=back

=item render

Input: The text to parse

Returns: the rendered text

    my $parsed = $parser->render($bbcode);

=item parse

Input: The text to parse.

Returns: the parsed tree (a L<Parse::BBCode::Tag> object)

    my $tree = $parser->parse($bbcode);

=item render_tree

Input: the parse tree

Returns: The rendered text

    my $parsed = $parser->render_tree($tree);

=item forbid

    $parser->forbid(qw/ img url /);

Disables the given tags.

=item permit

    $parser->permit(qw/ img url /);

Enables the given tags if they are in the tag definitions.

=item escape_html

Utility to substitute

    <>&"'

with their HTML entities.

    my $escaped = Parse::BBCode::escape_html($text);

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
            tags => {
                '' => sub {
                    my ($parser, $attr, $content, $info) = @_;
                    # for explanation of $info see below
                    # at "Define subroutine for tag"
                    my $e = Parse::BBCode::escape_html($content);
                    $e =~ s/\r?\n|\r/<br>\n/g;
                    $e
                },
                i   => '<i>%s</i>',
                b   => '<b>%{parse}s</b>',
                size => '<font size="%a">%{parse}s</font>',
                url => 'url:<a href="%{link}A">%{parse}s</a>',
                wikipedia => 'url:<a href="http://wikipedia.../?search=%{uri}A">%{parse}s</a>',
                noparse => '<pre>%{html}s</pre>',
                quote => 'block:<blockquote>%s</blockquote>',
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
                    class => 'block',
                },
                hr => {
                    class => 'block',
                    output => '<hr>',
                    single => 1,
                },
            },
        }
    );

The following list explains the above tag definitions:

=over 4

=item Plain text not in tags

This defines how plain text should be rendered:

    '' => sub {
        my $e = Parse::BBCode::escape_html($_[2]);
        $e =~ s/\r?\n|\r/<br>\n/g;
        $e
    },

In the most cases, you would want HTML escaping like shown above.
This is the default, so you can leave it out. Only if you want
to render BBCode into plain text or something else, you need this
option.

=item C<%s>

    i => '<i>%s</i>'

    [i] italic <html> [/i]
    turns out as
    <i> italic &lt;html&gt; </i>

So C<%s> stands for the tag content. By default, it is parsed itself,
so that you can nest tags.

=item C<%{parse}s>

    b   => '<b>%{parse}s</b>'

    [b] bold <html> [/b]
    turns out as
    <b> bold &lt;html&gt; </b>

C<%{parse}s> is the same as C<%s> because 'parse' is the default.

=item C<%a>

    size => '<font size="%a">%{parse}s</font>'

    [size=7] some big text [/size]
    turns out as
    <font size="7"> some big text </font>

So %a stands for the tag attribute. By default it will be HTML
escaped.

=item url tag, C<%A>, C<%{link}A>

    url => 'url:<a href="%{link}a">%{parse}s</a>'

the first thing you can see is the C<url:> at the beginning - this
defines the url tag as a tag with the class 'url', and urls must not
be nested. So this class definition is mainly there to prevent
generating wrong HTML. if you nest url tags only the outer one will
be parsed.

another thing you can see is how to apply a special escape. The attribute
defined with C<%{link}a> is checked for a valid URL.
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
need this in all url-like tags:

    url => 'url:<a href="%{link}A">%{parse}s</a>',

=item C<%{uri}A>

You might want to define your own urls, e.g. for wikipedia
references:

    wikipedia => 'url:<a href="http://wikipedia/?search=%{uri}A">%{parse}s</a>',

C<%{uri}A> will uri-encode the searched term:

    [wikipedia]Harold & Maude[/wikipedia]
    [wikipedia="Harold & Maude"]a movie[/wikipedia]
    turns out as
    <a href="http://wikipedia/?search=Harold+%26+Maude">Harold &amp; Maude</a>
    <a href="http://wikipedia/?search=Harold+%26+Maude">a movie</a>

=item Don't parse tag content

Sometimes you need to display verbatim bbcode. The simplest
form would be a noparse tag:

    noparse => '<pre>%{html}s</pre>'

    [noparse] [some]unbalanced[/foo] [/noparse]

With this definition the output would be

    <pre> [some]unbalanced[/foo] </pre>

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

=item Block tags

    quote => 'block:<blockquote>%s</blockquote>',

To force valid html you can add classes to tags. The default
class is 'inline'. To declare it as a block add C<'block:"> to the start
of the string.
Block tags inside of inline tags will either close the outer tag(s) or
leave the outer tag(s) unparsed, depending on the option C<close_open_tags>.

=item Define subroutine for tag

All these definitions might not be enough if you want to define
your own code, for example to add a syntax highlighter.

Here's an example:

    code => {
        code => sub {
            my ($parser, $attr, $content, $attribute_fallback, $tag, $info) = @_;
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
        class => 'block',
    },

So instead of a string you define a hash reference with a 'code'
key and a sub reference.
The other key is C<parse> which is 0 by default. If it is 0 the
content in the tag won't be parsed, just as in the noparse tag above.
If it is set to 1 you will get the rendered content as an argument to
the subroutine.

The first argument to the subroutine is the Parse::BBCode object itself.
The second argument is the attribute, the third is the already rendered tag
content as a scalar reference and the fourth argument is the attribute
fallback which is set to the content if the attribute is empty. The fourth
argument is just for convenience.
The fifth argument is the tag object (Parse::BBCode::Tag) itself, so if
necessary you can get the original tag content by using:

    my $original = $tag->raw_text;

The sixth argument is an info hash. It contains:

    my $info = {
        tags => $tags,
        stack => $stack,
        classes => $classes,
    };

The variable $tags is a hashref which contains all tag names which are
outside the current tag, with a count. This is convenient if you have
to check if the current processed tag is inside a certain tag and you
want to behave differently, like

    if ($info->{tags}->{special}) {
        # we are somewhere inside [special]...[/special]
    }

The variable $stack contains an array ref with all outer tag names.
So while processing the tag 'i' in

    [quote][quote][b]bold [i]italic[/i][/b][/quote][/quote]

it contains
    [qw/ quote quote b i /]

The variable $classes contains a hashref with all tag classes and their
counts outside of the current processed tag.
For example if you want to process URIs with URI::Find, and you are
already in a tag with the class 'url' then you don't want to use URI::Find
here.

    unless ($info->{classes}->{url}) {
        # not inside of a url class tag ([url], [wikipedia, etc.)
        # parse text for urls with URI::Find
    }

=item Single-Tags

Sometimes you might want single tags like for a horizontal line:

    hr => {
        class => 'block',
        output => '<hr>',
        single => 1,
    },

The hr-Tag is a block tag (should not be inside inline tags),
and it has no closing tag (option C<single>)

    [hr]
    Output:
    <hr>

=back

=head1 ESCAPES

    my $p = Parse::BBCode->new({
        ...
        escapes => {
            link => sub {
            },
        },
    });

You can define or override escapes. Default escapes are html, uri, link, email,
htmlcolor, num.
An escape functions as a validator and filter. For example, the 'link' escape
looks if it got a valid URI (starting with C</> or C<\w+://>) and html-escapes
it. It returns the empty string if the input is invalid.

See L<Parse::BBCode::HTML/default_escapes> for the detailed list of escapes.

=head1 TODO

=over 4

=item BBCode to Textile|Markdown

There is a L<Parse::BBCode::Markdown> module which is only
roughly tested.

=item API

The main syntax is likely to stay, only the API for callbacks
might change. At the moment it is not possible to add callbacks
to the parsing process, only for the rendering phase. It is
also not possible to declare your own attribute syntax, for
example

    [quote=nickname date]

Attributes always have to look like:

    [tag=main_attribute other=foo]...
    [tag="main_attribute" other="foo"]...

=item Redirects for url tags

In a forum you might want to prefix links and images with a redirect
script so that the actual referrer will be hidden from the target
url. This is extremely helpful if you are using session-ids in your
urls.
I plan to add an option for url tags which lets you define the
redirect-script url.

=back

=head1 REQUIREMENTS

perl >= 5.6.1, L<Class::Accessor::Fast>, L<URI::Escape>

=head1 SEE ALSO

L<BBCode::Parser>, L<HTML::BBCode>, L<HTML::BBReverse>

See C<examples/compare.html> for a feature comparison of the
modules and feel free to report mistakes.

See C<examples/bench.pl> for a benchmark of the modules.

=head1 BUGS

Please report bugs at http://rt.cpan.org/NoAuth/Bugs.html?Dist=Parse-BBCode

=head1 AUTHOR

Tina Mueller

=head1 CREDITS

Thanks to Moritz Lenz for his suggestions about the implementation
and the test cases.

Viacheslav Tikhanovskii

Sascha Kiefer

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Tina Mueller

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself, either Perl version 5.6.1 or, at your option,
any later version of Perl 5 you may have available.

=cut
