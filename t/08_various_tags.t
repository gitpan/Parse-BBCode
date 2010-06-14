use Test::More tests => 28;
use Parse::BBCode;
use strict;
use warnings;

my $p = Parse::BBCode->new({
        tags => {
            '' => sub { Parse::BBCode::escape_html($_[2]) },
            i   => '<i>%s</i>',
            b   => '<b>%{parse}s</b>',
            size => '<font size="%a">%{parse}s</font>',
            url => '<a href="%{link}A">%{parse}s</a>',
            wikipedia => '<a href="http://wikipedia.../?search=%{uri}A">%{parse}s</a>',
            noparse => '<pre>%{html}s</pre>',
            code => {
                code => sub {
                    my ($parser, $attr, $content, $attribute_fallback) = @_;
                    if ($attr eq 'perl') {
                        # use some syntax highlighter
                        $content = "/usr/bin/perl -e '$$content'";
                    }
                    else {
                        $content = Parse::BBCode::escape_html($$content);
                    }
                    "<tt>$content</tt>"
                },
                parse => 0,
            },
            raw => {
                parse => 1,
                code => sub {
                    my ($parser, $attr, $content, $attribute_fallback, $tag) = @_;
                    my $text = $tag->raw_text . '|' . $tag->raw_content . '|' . $$content;
                },
            },
            html => {
                parse => 1,
                code => sub {
                    my ($parser, $attr, $content, $attribute_fallback, $tag) = @_;
                    $attr = $tag->get_attr;
                    my $text = "<font";
                    for my $at (@$attr[1..$#$attr]) {
                        $text .= qq{ $at->[0]="$at->[1]"};
                    }
                    $text .= ">$$content</font>";
                    return $text;
                },
            },
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
            'img' => '<img src="%{html}A" alt="%{html}s" title="%{html}s">',
            hr => {
                class => 'block',
                output => '<hr>',
                single => 1,
            },
            quote => 'block:<blockquote>%s</blockquote>',
        },
    }
);

my @tests = (
    [ q#[size=7]big [b]bold[/b] text[/size]#,
        q#<font size="7">big <b>bold</b> text</font># ],
    [ q#[url=http://foo/]interesting [b]bold[/b] link[/url]#,
        q#<a href="http://foo/">interesting <b>bold</b> link</a># ],
    [ q#[url="http://foo/"]interesting [b]bold[/b] link[/url]#,
        q#<a href="http://foo/">interesting <b>bold</b> link</a># ],
    [ q#[url=/foo]interesting [b]bold[/b] link[/url]#,
        q#<a href="/foo">interesting <b>bold</b> link</a># ],
    [ q#[wikipedia]Harold & Maude[/wikipedia]#,
        q#<a href="http://wikipedia.../?search=Harold%20%26%20Maude">Harold &amp; Maude</a># ],
    [ q#[wikipedia="Harold & Maude"]a movie[/wikipedia]#,
        q#<a href="http://wikipedia.../?search=Harold%20%26%20Maude">a movie</a># ],
    [ q#[noparse]bbcode [b]which[/i] should not be [/code]parsed[/noparse]#,
        q#<pre>bbcode [b]which[/i] should not be [/code]parsed</pre># ],
    [ q#[code=perl]say "foo";[/code]#,
        q#<tt>/usr/bin/perl -e 'say "foo";'</tt># ],
    [ q#[code=perl]say "foo";[/code]#,
        q#<tt>/usr/bin/perl -e 'say "foo";'</tt># ],
    [ q#[raw]some [b]bold[/b] text[/raw]#,
        q#[raw]some [b]bold[/b] text[/raw]|some [b]bold[/b] text|some <b>bold</b> text# ],
    [ q#[html=style color=red size="7"]big [b]bold[/b] text[/html]#,
        q#<font color="red" size="7">big <b>bold</b> text</font># ],
    [ qq#before\n[list=1]\n[*]first\n[*]second\n[*]third\n[/list]\nafter#,
        qq#before\n<ul><li>first</li><li>second</li><li>third</li></ul>\nafter# ],
    [ q#[list=1][*]first with [url]foo[/url][*]second[*]third[/list]#,
        q#<ul><li>first with <a href="foo">foo</a></li><li>second</li><li>third</li></ul># ],
    [ q#[list=1][*]first[*]second with [url]foo[/url][*]third[/list]#,
        q#<ul><li>first</li><li>second with <a href="foo">foo</a></li><li>third</li></ul># ],
    [ q#[list=1][*]first[*]second with [url]foo[*]third[/list]#,
        q#<ul><li>first</li><li>second with [url]foo</li><li>third</li></ul># ],
    [ q#[list=1][*]first[*]second with [url]foo and [b]bold[/b][*]third[/list]#,
        q#<ul><li>first</li><li>second with [url]foo and <b>bold</b></li><li>third</li></ul># ],
    [ q#[list][*]a[list][*]c1[/list][/list]#,
        q#<ul><li>a<ul><li>c1</li></ul></li></ul># ],
    [ q#[img]/path/to/image.png[/img]#,
        q#<img src="/path/to/image.png" alt="/path/to/image.png" title="/path/to/image.png"># ],
    [ q#[img=/path/to/image.png]description[/img]#,
        q#<img src="/path/to/image.png" alt="description" title="description"># ],
    [ q#[img=/path/to/image.png]description [b]with bold[/b][/img]#,
        q#<img src="/path/to/image.png" alt="description [b]with bold[/b]" title="description [b]with bold[/b]"># ],
    [ q#text [quote]with bold and [hr]line[/quote]#,
        q#text <blockquote>with bold and <hr>line</blockquote># ],
    [ qq#text [quote="foo"][quote="bar"]inner quote[/quote]outer quote[/quote]#,
        q#text <blockquote><blockquote>inner quote</blockquote>outer quote</blockquote># ],
    [ q#[quote="admin@2008-06-27 19:00:25"][quote="foo@2007-08-13 22:12:32"]test[/quote]test[/quote]#,
        q#<blockquote><blockquote>test</blockquote>test</blockquote># ],
    [ q#text [b]with bold and [hr]line[/b]#,
        q#text [b]with bold and <hr>line[/b]# ],
    [ q#text with bold and [hr]line#,
        q#text with bold and <hr>line# ],
);

for (@tests) {
    my ($in, $exp) = @$_;
    my $parsed = $p->render($in);
    #warn __PACKAGE__.':'.__LINE__.": $parsed\n";
    cmp_ok($parsed, 'eq', $exp, "$in");
}
{
    my $p = Parse::BBCode->new({
            tags => {
                '' => 'plain',
                i   => '<i>%s</i>',
            },
        }
    );

    my $parsed = $p->render(q#foo [i]latin[/i]#);
    #warn __PACKAGE__.':'.__LINE__.": $parsed\n";
    my $exp = 'foo <i>latin</i>';
    is($parsed, $exp, "empty plain text definition");
}

{
    my $p = Parse::BBCode->new({
            tags => {
                i   => '<i>%s</i>',
            },
        }
    );

    my $parsed = $p->render(q#foo [i]latin[/i]#);
    #warn __PACKAGE__.':'.__LINE__.": $parsed\n";
    my $exp = 'foo <i>latin</i>';
    is($parsed, $exp, "no plain text definition");
}

{
    my $p = Parse::BBCode->new({
            tags => {
                '' => sub { Parse::BBCode::escape_html(undef) },
                i   => '<i>%s</i>',
            },
        }
    );

    my $parsed = $p->render(q#foo [i]latin[/i]#);
    #warn __PACKAGE__.':'.__LINE__.": $parsed\n";
    my $exp = '<i></i>';
    is($parsed, $exp, "undef plain text definition");
}
