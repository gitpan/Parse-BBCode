use Data::Dumper;
use Test::More tests => 6;
use Parse::BBCode;
use strict;
use warnings;

eval {
    require
        URI::Find;
};
my $uri_find = $@ ? 0 : 1;

SKIP: {
    skip "no URI::Find", 1 unless $uri_find;
    my $finder = URI::Find->new(sub {
        my ($url) = @_;
        my $title = $url;
        my $escaped = Parse::BBCode::escape_html($url);
        my $escaped_title = Parse::BBCode::escape_html($title);
        my $href = qq{<a href="$escaped" rel="nofollow">$escaped_title</a>};
        return $href;
    });
    my $escape = sub {
        my ($e) = @_;
        $e = Parse::BBCode::escape_html($e);
        return $e;
    };

    my $p = Parse::BBCode->new({                                                              
            tags => {
                'url'   => 'url:<a href="%{link}A" rel="nofollow">%s</a>',
                '' => sub {
                    my ($parser, $attr, $content, $info) = @_;
                    unless ($info->{classes}->{url}) {
                        my $count = $finder->find(\$content, $escape);
                    }
                    $content =~ s/\r?\n|\r/<br>\n/g;
                    $content
                },

            },
        }
    );

    my @tests = (
        [ q#[url]http://foo/[/url]#,
            q#<a href="http://foo/" rel="nofollow">http://foo/</a># ],
    );
    for my $test (@tests) {
        my ($text, $exp, $forbid, $parser) = @$test;
        $parser ||= $p;
        if ($forbid) {
            $parser->forbid($forbid);
        }
        my $parsed = $parser->render($text);
        #warn __PACKAGE__.':'.__LINE__.": $parsed\n";
        s/[\r\n]//g for ($exp, $parsed);
        $text =~ s/[\r\n]//g;
        cmp_ok($parsed, 'eq', $exp, "parse '$text'");
    }

}

my $p = Parse::BBCode->new({                                                              
        tags => {
            'list'  => {
                parse => 1,
                class => 'block',
                code => sub {
                    my ($parser, $attr, $content, $attribute_fallback, $tag, $info) = @_;
                    $$content =~ s/^\n+//;
                    $$content =~ s/\n+\z//;
                    return "<ul>$$content</ul>";
                },
            },
            '*' => {
                parse => 1,
                code => sub {
                    my ($parser, $attr, $content, $attribute_fallback, $tag, $info) = @_;
                    $$content =~ s/\n+\z//;
                    $$content = "<li>$$content</li>";
                    unless ($info->{stack}->[-2] eq 'list') {
                        return $tag->raw_text;
                    }
                    return $$content;
                },
                close => 0,
                class => 'block',
            },
            'quote' => 'block:<blockquote>%{html}a:%s</blockquote>',

        },
    }
);
my @tests = (
    [ qq#[list]\n[*]1\n[*]2\n[/list]#,
        q#<ul><li>1</li><li>2</li></ul># ],
    [ q#[quote][*]1[*]2[/quote]#,
        q#<blockquote>:[*]1[*]2</blockquote># ],
);
for my $test (@tests) {
    my ($text, $exp, $forbid, $parser) = @$test;
    $parser ||= $p;
    if ($forbid) {
        $parser->forbid($forbid);
    }
    my $parsed = $parser->render($text);
    #warn __PACKAGE__.':'.__LINE__.": $parsed\n";
    s/[\r\n]//g for ($exp, $parsed);
    $text =~ s/[\r\n]//g;
    cmp_ok($parsed, 'eq', $exp, "parse '$text'");
}

$p = Parse::BBCode->new();
my $bbcode = q#start [b]1[/b][b]2[b]3[/b][b]4[/b] [b]5 [b]6[/b] [/b] [/b]#;
my $tree = $p->parse($bbcode);
my $tag = $tree->get_content->[3]->get_content->[1];
my $num = $tag->get_num;
my $level = $tag->get_level;
cmp_ok($num, '==', 3, "get_num");
cmp_ok($level, '==', 2, "get_level");

$p = Parse::BBCode->new({
    tags => {
        code => {
            code => sub {
                my ($parser, $attr, $content, $attribute_fallback, $tag, $info) = @_;
                my $title = Parse::BBCode::escape_html($attr);
                my $code = Parse::BBCode::escape_html($$content);
                my $aid = $parser->get_params->{article_id};
                my $cid = $tag->get_num;
                return <<"EOM";
<code_header><a href="code?article_id=$aid;code_id=$cid">Download</a></code_header>
<code_body>$code</code_body>

EOM
            },
        },
    },
});
$bbcode = "[code=1]test[/code]";
my $rendered = $p->render($bbcode, { article_id => 23 });
cmp_ok($rendered, '=~', 'code\?article_id=23;code_id=1', "params");
