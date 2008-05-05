use Data::Dumper;
use lib 'lib';
use Test::More tests => 2;
use Parse::BBCode;

my %tag_def_html = (

    '' => sub {
        my $text = Parse::BBCode::escape_html($_[1]);
        $text =~ s/\n/<br>\n/g;
        return $text;
    },
    code => {
#        class => 'block',
        parse => 0,
        code => sub {
            my $c = $_[2];
            $c = Parse::BBCode::escape_html($$c);
            "<code>$c</code>"
        },
    },
    perlmonks => '<a href="http://www.perlmonks.org/?node=%{uri|html}a">%{parse}s</a>',
    url => '<a href="%{URL}A">%{parse}s</a>',
    i => '<i>%{parse}s</i>',
    b => '<b>%{parse}s</b>',
    a => '<a>%s</a>',
);

my $bbc2html = Parse::BBCode->new({                                                              
        tag_def => {
            %tag_def_html,
        },
        tags => [qw/ i b perlmonks url code a /],
    }
);

my $text = <<'EOM';
[i=23]italic [b]bold italic <html>[/b][/i]
[A][code][a][c][/code][/a]
[perlmonks=123]foo <html>[i]italic[/i][/perlmonks]
[url=javascript:alert(123)]foo <html>[i]italic[/i][/url]
[code]foo[b][/code]
[code]foo[code]bar<html>[/code][/code]
[i]italic [b]bold italic <html>[/i][/b]
[B]bold? [test
EOM

my $exp = <<'EOM';
<i>italic <b>bold italic &lt;html&gt;</b></i><br>
<a><code>[a][c]</code></a><br>
<a href="http://www.perlmonks.org/?node=123">foo &lt;html&gt;<i>italic</i></a><br>
<a href="">foo &lt;html&gt;<i>italic</i></a><br>
<code>foo[b]</code><br>
<code>foo[code]bar&lt;html&gt;</code>[/code]<br>
<i>italic [b]bold italic &lt;html&gt;</i>[/b]<br>
[B]bold? [test<br>
EOM



eval {
    my $parsed = $bbc2html->render();
};
my $error = $@;
#warn __PACKAGE__.':'.__LINE__.": <<$@>>\n";
cmp_ok($error, '=~', 'Missing input', "Missing input for render()");

my $parsed = $bbc2html->render($text);
#warn __PACKAGE__.':'.__LINE__.": $parsed\n";
s/[\r\n]//g for ($exp, $parsed);
cmp_ok($parsed, 'eq', $exp, "parse");
