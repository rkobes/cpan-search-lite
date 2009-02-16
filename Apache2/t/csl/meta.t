#!/usr/bin/perl
use strict;
use warnings;
use Apache::Test;
use Apache::TestUtil qw(t_cmp);
use Apache::TestRequest qw(GET_BODY_ASSERT);
use FindBin;
use YAML qw(LoadFile Load);
require File::Spec;
use lib "$FindBin::Bin/../lib";
use TestCSL::parse_ppd qw(parse_ppd);

my ($tests, @types);
eval {require JSON; import JSON qw(from_json)};
if ($@) {
  $tests = 996;
  @types = qw(yml ppd);
}
else {
  $tests = 1524;
  @types = qw(yml json ppd);
}
plan tests => $tests;

my $config   = Apache::Test::config();
my $hostport = Apache::TestRequest::hostport($config) || '';
my $meta_dir = "$FindBin::Bin/../lib/meta";
my %mods = ('Net::FTP' => 'libnet',
	   'HTML::Form' => 'libwww-perl',
	   'Alias::' => 'Alias');

for my $dist( qw(Alias libwww-perl libnet )) {
  for my $type (@types) {
    my $test = "test_$type";
    my $test_sub = \&{$test};
    $test_sub->(dist => $dist);
  }
}

for my $mod( keys %mods) {
  for my $type ( @types) {
    my $test = "test_$type";
    my $test_sub = \&{$test};
    $test_sub->(mod => $mod);
  }
}

sub test_yml {
  my %args = @_;
  my $arg = defined $args{dist} ? $args{dist} : $args{mod};
  my $dist = defined $args{dist} ? $arg : $mods{$arg};
  $arg =~ s/:/%3A/g;
  my $content = GET_BODY_ASSERT "/meta/$arg/META.yml";
  my $response = Load($content);
  my $expected = LoadFile(File::Spec->catfile($meta_dir, "$dist.yml"));
  ok t_cmp(defined $response, 1);
  ok t_cmp(ref($response), 'HASH');
  foreach my $key(qw(generated_by distribution_type version name abstract)) {
    next unless defined $expected->{$key};
    ok t_cmp($response->{$key}, $expected->{$key});
  }
  foreach my $key( qw(author)) {
    next unless defined $expected->{$key};
    ok t_cmp(ref($response->{$key}), 'ARRAY');
    ok t_cmp($response->{$key}->[0], $expected->{$key}->[0]);
  }
  foreach my $key( qw(resources meta-spec)) {
    next unless defined $expected->{$key};
    ok t_cmp(ref($response->{$key}), 'HASH');
    foreach my $entry(keys %{$expected->{$key}}) {
      ok t_cmp($response->{$key}->{$entry}, $expected->{$key}->{$entry});
    }
  }
  foreach my $key( qw(provides)) {
    next unless defined $expected->{$key};
    ok t_cmp(ref($response->{$key}), 'HASH');
    foreach my $mod(keys %{$expected->{$key}}) {
      ok t_cmp(defined $response->{$key}->{$mod}, 1);
      ok t_cmp(ref($response->{$key}->{$mod}), 'HASH');
      ok t_cmp($response->{$key}->{$mod}->{version},
	       $expected->{$key}->{$mod}->{version});
    }
  }
}

sub test_json {
  my %args = @_;
  my $arg = defined $args{dist} ? $args{dist} : $args{mod};
  my $dist = defined $args{dist} ? $arg : $mods{$arg};
  open(my $fh, File::Spec->catfile($meta_dir, "$dist.json"))
    or die $!;
  my @lines = <$fh>;
  close $fh;
  my $json = join "", @lines;
  my $expected = from_json($json);
  my $content = GET_BODY_ASSERT "/meta/$arg/META.json";
  my $response = from_json($content);
  ok t_cmp(defined $response, 1);
  ok t_cmp(ref($response), 'HASH');
  foreach my $key(qw(generated_by distribution_type version name abstract)) {
    next unless defined $expected->{$key};
    ok t_cmp($response->{$key}, $expected->{$key});
  }
  foreach my $key( qw(author)) {
    next unless defined $expected->{$key};
    ok t_cmp(ref($response->{$key}), 'ARRAY');
    ok t_cmp($response->{$key}->[0], $expected->{$key}->[0]);
  }
  foreach my $key( qw(resources meta-spec)) {
    next unless defined $expected->{$key};
    ok t_cmp(ref($response->{$key}), 'HASH');
    foreach my $entry(keys %{$expected->{$key}}) {
      ok t_cmp($response->{$key}->{$entry}, $expected->{$key}->{$entry});
    }
  }
  foreach my $key( qw(provides)) {
    next unless defined $expected->{$key};
    ok t_cmp(ref($response->{$key}), 'HASH');
    foreach my $mod(keys %{$expected->{$key}}) {
      ok t_cmp(defined $response->{$key}->{$mod}, 1);
      ok t_cmp(ref($response->{$key}->{$mod}), 'HASH');
      ok t_cmp($response->{$key}->{$mod}->{version},
	       $expected->{$key}->{$mod}->{version});
    }
  }
}

sub test_ppd {
  my %args = @_;
  my $arg = defined $args{dist} ? $args{dist} : $args{mod};
  my $dist = defined $args{dist} ? $arg : $mods{$arg};
  open(my $fh, File::Spec->catfile($meta_dir, "$dist.ppd"))
    or die $!;
  my @lines = <$fh>;
  close $fh;
  my $string = join "", @lines;
  my $expected = parse_ppd($string);
  my $content = GET_BODY_ASSERT "/meta/$arg/META.ppd";
  my $response = parse_ppd($content);
  ok t_cmp(defined $response, 1);
  ok t_cmp(ref($response), 'HASH');
  foreach my $key(qw(TITLE ABSTRACT AUTHOR)) {
    next unless defined $expected->{$key};
    ok t_cmp($response->{$key}, $expected->{$key});
  }
  foreach my $key(qw(CODEBASE SOFTPKG)) {
    next unless defined $expected->{$key};
    my $expected_ref = $expected->{$key};
    my $response_ref = $response->{$key};
    ok t_cmp(ref($response_ref), 'HASH');
    foreach my $item (keys %$expected_ref) {
      next unless defined $expected_ref->{$item};
      ok t_cmp($response_ref->{$item}, $expected_ref->{$item});
    }
  }
  foreach my $key( qw(PROVIDE DEPENDENCY)) {
    next unless defined $expected->{$key};
    my $expected_ref = $expected->{$key};
    ok t_cmp(ref($expected_ref), 'ARRAY');
    my $response_ref = $response->{$key};
    my $number = scalar @$expected_ref;
    for (my $i=0; $i<$number; $i++) {
      next unless defined $expected_ref->[$i];
      my $expected_ref_i = $expected_ref->[$i];
      my $response_ref_i = $response_ref->[$i];
      ok t_cmp(ref($response_ref_i), 'HASH');
      foreach my $item (keys %$expected_ref_i) {
	next unless defined $expected_ref_i->{$item};
	ok t_cmp($response_ref_i->{$item}, $expected_ref_i->{$item});
      }
    }
  }
}
