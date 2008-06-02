use Test::More tests => 8;
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
            quote => 'block:<quote>%{parse}s</quote>',
        },
        close_open_tags => 1,
    }
);

my @tests = (
    [ 1, q#[i]italic[b]bold [quote]this is invalid[/quote] bold[/b][/i]#,
         q#<i>italic<b>bold </b></i><quote>this is invalid</quote> bold[/b][/i]#,
         q#[i]italic[b]bold [/b][/i][quote]this is invalid[/quote] bold[/b][/i]#,
         ],
    [ 0, q#[i]italic[b]bold [quote]this is invalid[/quote] bold[/b][/i]#,
         q#[i]italic[b]bold <quote>this is invalid</quote> bold[/b][/i]#,
         q#[i]italic[b]bold [quote]this is invalid[/quote] bold[/b][/i]#,
         ],
    [ 0, q#[i]italic[b]bold[/b] [quote]this is invalid[/quote] [/i]#,
         q#[i]italic<b>bold</b> <quote>this is invalid</quote> [/i]#,
         q#[i]italic[b]bold[/b] [quote]this is invalid[/quote] [/i]#,
         ],
    [ 1, q#[i]italic[b]bold [url]foo[/url]#,
         q#<i>italic<b>bold <a href="foo">foo</a></b></i>#,
         q#[i]italic[b]bold [url]foo[/url][/b][/i]#,
         ],
);

for (@tests) {
    my ($close, $in, $exp, $exp_raw) = @$_;
    $p->set_close_open_tags($close);
    my $parsed = $p->render($in);
    #warn __PACKAGE__.':'.__LINE__.": $parsed\n";
    cmp_ok($parsed, 'eq', $exp, "invalid $in");
    my $err = $p->error('block_inline') || $p->error('unclosed');
    if ($err) {
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$err], ['err']);
        my $tree = $p->get_tree;
        #warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$tree], ['tree']);
        my $raw = $tree->raw_text;
        #warn __PACKAGE__.':'.__LINE__.": $raw\n";
        cmp_ok($raw, 'eq', $exp_raw, "raw text $in");
    }
}

