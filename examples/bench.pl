#!/usr/bin/perl
use strict;
use warnings;
use Carp qw(carp croak);
use Data::Dumper;

use BBCode::Parser;
use Parse::BBCode;
use HTML::BBCode;
use Benchmark;


my $code = <<'EOM';
[b]bold [i]italic[/i] test[/b]
[code]some [perl] code[/code]
[url=http://foo.example.org/]a link![/url]
EOM

sub create_pb {
    my $pb = Parse::BBCode->new({
        tag_def => {
            b => '<b>%s</b>',
            i => '<i>%s</i>',
            url => '<a href="%{URL}A">%s</a>',
            code =>'block:<div class="bbcode-code">
<div class="bbcode-code-head">Code:</div>
<pre class="bbcode-code-body">%{noparse}s
</pre>
</div>',
        },
    });
    return $pb;
}

sub create_hb {
    my $bbc  = HTML::BBCode->new();
    return $bbc;
}

sub create_bp {
    my $parser = BBCode::Parser->new(follow_links => 1);
    return $parser;
}

my $pb = create_pb();
my $bp = create_bp();
my $hb = create_hb();
my $rendered1 = $pb->render($code);
print "$rendered1\n";
my $tree = $bp->parse($code);
my $rendered2 = $tree->toHTML();
print "$rendered2\n";
my $rendered3 = $hb->parse($code);
print "$rendered3\n";


timethese($ARGV[0] || -1, {
    'P::B::new'  => \&create_pb,
    'H::B::new'  => \&create_hb,
    'B::P::new' => \&create_bp,
    'P::B'  => sub { my $out = $pb->render($code) },
    'H::B'  => sub { my $out = $hb->parse($code) },
    'B::P' => sub { my $tree = $bp->parse($code); my $out = $tree->toHTML(); },
});
