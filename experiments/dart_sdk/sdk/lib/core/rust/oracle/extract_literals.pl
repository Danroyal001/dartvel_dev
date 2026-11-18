#!/usr/bin/perl
# Prints every single-line Dart string literal without interpolation from the
# files given, Dart escapes decoded, in the oracle's line escape format.
use strict; use warnings;
sub esc { my @cp = @_; my $o = '';
  for my $c (@cp) {
    my @units = $c > 0xFFFF ? (0xD800 + (($c - 0x10000) >> 10), 0xDC00 + (($c - 0x10000) & 0x3FF)) : ($c);
    for my $u (@units) { if ($u >= 0x20 && $u < 0x7F && $u != 0x5C) { $o .= chr($u) } else { $o .= sprintf("\\%04x", $u) } }
  } $o }
my %esc = (n => 10, r => 13, t => 9, b => 8, f => 12, v => 11);
for my $file (@ARGV) {
  open my $fh, '<:encoding(UTF-8)', $file or die;
  while (my $line = <$fh>) {
    next if $line =~ m{^\s*//};
    while ($line =~ /(r?)(["'])((?:\\.|(?!\2).)*)\2/g) {
      my ($raw, $body) = ($1, $3);
      if ($raw) { print esc(map { ord } split //, $body), "\n"; next }
      next if $body =~ /(?<!\\)\$/;
      my @cp; my $ok = 1;
      while (length $body) {
        if ($body =~ s/^\\u\{([0-9a-fA-F]+)\}//) { push @cp, hex $1 }
        elsif ($body =~ s/^\\u([0-9a-fA-F]{4})//) { push @cp, hex $1 }
        elsif ($body =~ s/^\\x([0-9a-fA-F]{2})//) { push @cp, hex $1 }
        elsif ($body =~ s/^\\(.)//s) { push @cp, exists $esc{$1} ? $esc{$1} : ord $1 }
        else { $body =~ s/^(.)//s; push @cp, ord $1 }
      }
      print esc(@cp), "\n";
    }
  }
}
