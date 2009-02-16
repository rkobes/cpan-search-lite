#!perl
package CPAN::Search::Lite::HTML;
use CPAN::Search::Lite::DBI::Index;
use CPAN::Search::Lite::DBI qw($dbh);
use strict;
use warnings;
use File::Temp qw(tempfile);
use File::Basename;
use File::Path;
use File::Spec::Functions qw(splitdir catfile catdir 
			     tmpdir splitpath canonpath);
use File::Copy;
use Pod::Html;
use Pod::Select;
use Perl::Tidy;
use HTML::TextToHTML;
use File::Find;
use Pod::Xhtml;
use CPAN::Search::Lite::Util qw(has_data);

our $VERSION = 0.77;
my $DEBUG = 1;
my %global_opts;
our $dbh = $CPAN::Search::Lite::DBI::dbh;
our $docs;
my $tmpfile = catfile(tmpdir(), 'csl_tmp_podfile.pod');
my $date = scalar localtime();
my $xhtml_version = $Pod::Xhtml::VERSION;

# replace the Pod::Xhtml package's seqL method
# so as to return jus the link if it contains [<>] tags
package MyPodXhtml;
use base qw(Pod::Xhtml);

$Pod::Xhtml::SEQ{L} = \&myseqL;

sub myseqL {
  my ($self, $link) = @_;
  if ($link =~ /[<>]/) {
    return $link;
  }
  else {
    return $self->SUPER::seqL($link);
  }
}

# use MyLinkParser to make references to links
# to modules we have
package MyLinkParser;
use Pod::ParseUtils;
use base qw(Pod::Hyperlink);

sub parse {
  my $self = shift;
  my $link = shift;
  $self->SUPER::parse($link);
  my $htmlroot = $self->{htmlroot};
  my $dist = $self->{dist};

  my $page = $self->page;
  my $kind = $self->type;
  my $node = $self->node;
  my $text = $self->text;
  my $markup = $self->markup;
  if ($node and not $page) {
    (my $section = $node) =~ s{ }{_}g;
    $section =~ s{\(|\)|\"|&quot;}{}g;
    $self->alttext($text);
    if ($link =~ m{^(http|ftp)://}) {
      $self->node($link);
    }
    else {
      $self->node("#$section");
    }
    $self->type('hyperlink');
  }
  elsif (my $d = $docs->{$page}) {
    if ($d ne $dist) {
      $htmlroot =~ s/$dist/$d/;
    }
    (my $ref = $page) =~ s{::}{/}g;
    $self->alttext($text);
    my $rv = "$htmlroot/$ref.html";
    if ($node) {
      (my $section = $node) =~ s{ }{_}g;
      $section =~ s{\(|\)|\"|&quot;}{}g;
      $rv .= "#$section";
    }
    $self->node($rv);
    $self->type('hyperlink');
  }
}

package CPAN::Search::Lite::HTML;

{
  no warnings qw(redefine);
  *Pod::Html::pod2html = \&mypod2html;
}

sub new {
    my ($class, %args) = @_;
    foreach (qw(pod_root html_root dist_docs db user 
		passwd dist_obj) ) {
        die "Must supply a '$_' argument" unless defined $args{$_};
    }
    my $cdbi = CPAN::Search::Lite::DBI::Index->new(%args);

    %global_opts = map {$_ => $args{$_}} qw(setup split_pod dist_info);
    if ($args{pod_only} and $args{split_pod}) {
        die qq{Please specify only one of "split_pod" or "pod_only"};
    }

    my $self = {pod_root => $args{pod_root},
                html_root => $args{html_root},
                css => $args{css},
                up_img => $args{up_img},
                pod_only => $args{pod_only},
                split_pod => $args{split_pod},
		dist_docs => $args{dist_docs},
		dist_obj => $args{dist_obj},
		dist_info => $args{dist_info},
            };
    bless $self, $class;
}

sub mypod2html {
  my @opts = @_;
  my %opts;
  foreach my $opt(@opts) {
    $opt =~ s/^--?//;
    my @a = split /=/, $opt, 2;
    $opts{$a[0]} = defined $a[1] ? $a[1] : 1;
  }
  my $infile = $opts{infile};
  my $outfile = $opts{outfile};
  my ($package, $filename, $line) = caller;
  my $is_perltidy = ($package eq 'Perl::Tidy::HtmlWriter');
  my $source = $infile;
  if ($is_perltidy) {
    $source = $tmpfile;
    unlink($source) if (-e $source);
    copy($infile, $source) or do {
      warn "Cannot copy $infile to $source: $!";
      return;
    };
  }
  my $title = $opts{title};
  my ($pack, $desc) = split / - /, $title;
  $desc = '' unless $desc;

  my $htmlroot = $opts{htmlroot};
  (my $dist = $htmlroot) =~ s{.*/([^/]+)$}{$1};
  (my $root_dir = $htmlroot) =~ s{/$dist$}{}; 
  my $top;
  my $backlink = $opts{backlink};
  if ($backlink =~ /\.(gif|png|jpe?g)$/) {
    $top = <<"END";
<p><a href="#TOP" class="toplink"> 
<img src="$root_dir/$backlink" alt="Top" border="0" /></a></p>
END
  }
  else {
    $top = <<"END";
<p><a href="#TOP" class="toplink">Top</a></p>
END
  }
  my $headtext = <<"END";
<meta name="description" content="$desc" />
<meta name="created" content="$date" />
<meta name="generator" content="Pod::Xhtml $xhtml_version" />
END
  if ($opts{css}) {
    $headtext .= <<"END";
<link rel="stylesheet" href="$opts{css}" type="text/css" />
END
  }

  my $doc_text = <<"END";
<table width="100%"><tr>
<td align="left"><a href="$htmlroot/">$dist documentation</a>
END
  if ($global_opts{split_pod} and not $is_perltidy) {
    (my $src = $outfile) =~ s{.*(/|\\)(.*)(\.html)}{$2.pm$3};
    $doc_text .= <<"END";
&nbsp;|&nbsp;<a href="$src">view source</a>
END
  }
  $doc_text .= qq{</td>};
  if (my $dist_info = $global_opts{dist_info}) {
    $dist_info =~ s@/$@@;
    $doc_text .= <<"END";
<td align="right">
Contained in the <a href="$dist_info/$dist">$dist</a> distribution.</td>
END
  }
  else {
   $doc_text = <<"END";
<td align="right">
Contained in the <b>$dist</b> distribution.</td>
END
  }
  $doc_text .= qq{</tr></table>\n};

  my $dist_text = '';
  unless ($is_perltidy) {
    $dist_text = qq{<h1>$title</h1>\n};
  }

  my $linkparser = MyLinkParser->new();
  $linkparser->{htmlroot} = $htmlroot;
  $linkparser->{dist} = $dist;
  my $xhtml = MyPodXhtml->new(TopLinks => $top, MakeMeta => 0,
			     LinkParser => $linkparser,
			     MakeIndex => 2);
  $xhtml->addHeadText("$headtext\n");
  $xhtml->addBodyOpenText("\n$dist_text\n<hr />$doc_text<hr />\n");
  $xhtml->addBodyCloseText("\n<hr />$doc_text\n");
  $xhtml->parse_from_file($source, $outfile);
  return 1;
}

sub make_html {
  my $self = shift;
  $self->make_docs();
  my $dist_docs = $self->{dist_docs};
  die qq{dist_docs contains no data} unless has_data($dist_docs);
  foreach my $dist(keys %$dist_docs) {
    my $docs = $dist_docs->{$dist};
    my $in_root = $docs->{dist_root};
    my $out_root = catdir $self->{html_root}, $dist;
    my $css_file = $self->{css};
    my $pod_only = $self->{pod_only};
    my $split_pod = $self->{split_pod};
    my $back_link = $self->{up_img} ? $self->{up_img} : '__top';
    if (-d $out_root) {
        rmtree($out_root, $DEBUG, 1) or do {
            warn "Cannot rmtree $out_root: $!";
            return;
        };
    }
    mkpath($out_root, $DEBUG, 0755) or do {
        warn "Cannot mkdir $out_root: $!";
        return;
    };

    my $toc_files = {};
    foreach my $file (sort keys %{$docs->{files}}) {
      my $infile = catfile $in_root, $file;
      next unless (-e $infile);
      my $is_text = ($file eq 'README' or $file eq 'Changes'
		     or $file eq 'INSTALL' or $file eq 'META.yml');
      my ($outfile, $html_file);
      if ($is_text) {
	$html_file = $file eq 'META.yml' ? 'META.html' : $file . '.html';
      }
      else {
	($html_file = $file) =~ s!\.(pod|pm|PL)$!.html!; 
      }
      $outfile = catfile $out_root, $html_file;
      my $abs_dir = dirname($outfile);
      unless (-d $abs_dir){
	mkpath($abs_dir, 1, 0755) or do {
	  warn "Couldn't mkdir $abs_dir: $!";
	  return;
	};
      }
      my $rel_dir = dirname($file);
      my $root = $rel_dir eq '.' ? '../' :
	('../' x (1 + scalar splitdir($rel_dir)));
      my $css = $css_file ? $root . $css_file : '';
      print "Creating $outfile\n";
      my $title;
      $html_file = unix_path($html_file);
      my $pod_ext = '';
      if ($file =~ /(\.pm|\.pod)/) {
	$pod_ext = $1;
      }
      if ($is_text) {
	my $c = HTML::TextToHTML->new();
	my %args = ();
	$title = "$dist - $file";
	$args{infile} = [$infile];
	$args{outfile} = $outfile;
	$args{title} = $title;
	$args{style_url} = $css if $css;
	$args{preformat_trigger_lines} = 0 if ($file eq 'META.yml');
	eval{ $c->txt2html(%args); };
	warn $@ if $@;
	$toc_files->{$title} = {href => $html_file};
      }
      else {
	my $html_root = $root . $dist;
	my $name = $docs->{files}->{$file}->{name};
	my $desc = $docs->{files}->{$file}->{desc};
	$title = $desc ? "$name - $desc" : $name;
	if ($pod_only) {
	  my @opts = (
		      "--header", "--flush",
		      "--backlink=$back_link",
		      "--title=$title",
		      "--infile=$infile",
		      "--outfile=$outfile",
		      "--podroot=$in_root",
		      "--htmlroot=$html_root",
		      "--quiet",
		     );
	  push @opts, "--css=$css" if $css;
	  eval{ Pod::Html::pod2html(@opts); };
	  if ($@) {
	    warn $@;
	    next;
	  }
	  $toc_files->{$title} = {href => $html_file};
	}
	else {
	  my $contains_pod = '';
	  if ($split_pod) {
	    my ($tmpfh, $tmpfn) = tempfile(UNLINK => 1) or do {
	      warn "Cannot create tempfile: $!";
	      next;
	    };
	    my $parser = Pod::Select->new();
	    $parser->parse_from_file($infile, $tmpfn);
	    while (<$tmpfh>) {
	      if (/^=head1/) {
		$contains_pod = 1;
		last;
	      }
	    }
	    if ($contains_pod) {
	      my @opts = (
			  "--header", "--flush",
			  "--backlink=$back_link",
			  "--title=$title",
			  "--infile=$tmpfn",
			  "--outfile=$outfile",
			  "--podroot=$in_root",
			  "--htmlroot=$html_root",
			  "--quiet",
			 );
	      push @opts, "--css=$css" if $css;
	      eval{ Pod::Html::pod2html(@opts); };
	      if ($@) {
		warn $@;
		next;
	      }
	    }
	    close($tmpfh);
	    unlink($tmpfn) if (-e $tmpfn);
	  }
	  unless ($contains_pod) {
	    $title = $name;
	  }
	  my @opts = (
		      "--backlink=$back_link",
		      "--title=$title",
		      "--podroot=$in_root",
		      "--htmlroot=$html_root",
		      "--quiet", "--html", "--podflush",
		     );
	  push @opts, "--css=$css" if $css;
	  my $dest = $outfile;
	  if ($file =~ /(Build|Makefile).PL/) {
	    $dest =~ s{\.html$}{.PL.html};
	  }
	  else {
	    if ($file =~ /(\.pm|\.pod)/) {
	      $dest =~ s{\.html$}{$pod_ext.html} if $split_pod;
	    }
	  }
	  my %args = (source => $infile, destination => $dest,
		      argv => \@opts);
	  chdir($abs_dir) or do {
	    print STDERR "Could not chdir to $abs_dir: $!";
	    next;
	  };
	  eval{ Perl::Tidy::perltidy(%args); };
	  if ($@) {
	    warn $@;
	    next;
	  }
	  if ($split_pod) {
	    my $src_file;
	    if ($file =~ /(\.pm|\.pod)/) {
	      ($src_file = $html_file) =~ s{\.html$}{$pod_ext.html}
	    }
	    if ($contains_pod) {
	      $toc_files->{$title} = {href => $html_file,
				      src => $src_file};
	    }
	    else {
	      if ($file =~ /(Build|Makefile).PL/) {
		$html_file =~ s{\.html$}{.PL.html};
		$toc_files->{$name} = {href => $html_file};
	      }
	      else {
		$toc_files->{$name} = {src => $src_file};
	      }
	    }
	  }
	  else {
	    $toc_files->{$title} = {href => $html_file};
	  }
	}
      }
    }
    $self->generate_toc(out_root => $out_root,
			dist => $dist,
			toc_files => $toc_files);
    chdir $out_root;
    clean_pod($out_root);
  }
  unless ($global_opts{setup}) {
    $self->remove_stale() or do {
      warn "remove_stale() failed";
      return;
    };
  }
  unlink($tmpfile) if (-e $tmpfile);
  return 1;
}

sub generate_toc {
  my ($self, %args) = @_;

  my $css_file = $self->{css};
  my $out_root = $args{out_root};
  my $dist = $args{dist};
  my $toc_files = $args{toc_files};

  my $index = catfile($out_root, 'index.html');
  open(my $fh, '>', $index) or do {
    warn "Could not open $index: $!";
    return;
  };
  
  my $css_link = $css_file ? 
    qq{<link rel="stylesheet" type="text/css" href="../$css_file" />} : '';
  
  print $fh <<"END";
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
<head>
<title>$dist documentation</title>
$css_link
</head>
<body>
<h2>$dist documentation</h2>
<ul>
END

  my %keys = map {$_ => 1} keys %$toc_files;
  my @files = ();

  foreach my $f(qw(README Changes INSTALL META.yml)) {
    my $key = "$dist - $f";
    if ($keys{$key}) {
      push @files, $key;
      delete $keys{$key};
    }
  }
  foreach my $f(qw(Build.PL Makefile.PL )) {
    foreach my $key(keys %keys) {
      if ($key =~ /$f/) {
	push @files, $key;
	delete $keys{$key};
      }
    }
  }

  my %trim;
  my @keys = keys %keys;
  foreach my $n_pod ( @keys) {
    my $src_pod = $toc_files->{$n_pod}->{src};
    next unless $src_pod;
    if ($src_pod =~ /\.pod\./) {
      (my $try_src = $src_pod) =~ s/\.pod\./.pm./;
      foreach my $n_pm( @keys) {
	next if $n_pm eq $n_pod;
	my $src_pm = $toc_files->{$n_pm}->{src};
	my $href_pm = $toc_files->{$n_pm}->{href};
	if (not $href_pm and $src_pm eq $try_src) {
	  $trim{$n_pm} = $n_pod;
	  last;
	}
      }
    }
  }
  foreach my $n_pm (keys %trim) {
    my $n_pod = $trim{$n_pm};
    $toc_files->{$n_pod}->{src} = $toc_files->{$n_pm}->{src};
    delete $keys{$n_pm};
  }

  push @files, (sort {lc $a cmp lc $b} keys %keys);

  foreach my $name( @files ) {
    my $href = $toc_files->{$name}->{href};
    my $src = $toc_files->{$name}->{src};
    my $string = (defined $href) ?
      qq{<a href="$href">$name</a>} : qq{$name};
    $string .= qq{&nbsp; [<a href="$src">view source</a>]} if defined $src;
    print $fh qq{<li>$string</li>\n};
  }

  print $fh <<"END";
</ul><hr />
<table width="100%"><tr><td align="left">
Back to <a href="../">home</a>.</td>
END
  if (my $dist_info = $global_opts{dist_info}) {
    $dist_info =~ s@/$@@;
    print $fh <<"END";
<td align="right">
Contained in the <a href="$dist_info/$dist">$dist</a> distribution.</td>
END
  }
  print $fh qq{</body></html>\n};
  close $fh;
}

sub clean_pod {
    my $dir = shift;
    return unless ($dir and -d $dir);
    my @goners;
    finddepth(sub { push @goners, $File::Find::name
                      if $File::Find::name =~ /(pod2h|perltidy).*\.tmp$/i;},
              $dir);
    if (@goners) {
        foreach my $f(@goners) {
            $f = canonpath($f);
            next unless -e $f;
            unlink $f;
        }
    }
}


sub unix_path {
    my $file = shift;
    return $file unless $^O =~ /Win32/;
    my @d = splitpath($file);
    return File::Spec::Unix->catfile( splitdir($d[1]), $d[2]);
}

sub make_docs {
  my $self = shift;
  unless ($dbh) {
    $self->{error_msg} = q{No db handle available};
    return;
  }
  my $sql = q{ SELECT mod_name,dist_name,doc } .
    q { FROM mods,dists WHERE mods.dist_id = dists.dist_id };
  my $sth = $dbh->prepare($sql);
  $sth->execute() or do {
    $self->db_error($sth);
    return;
  };
  while (my ($mod_name, $dist_name, $doc) = $sth->fetchrow_array) {
    next unless $doc;
    $docs->{$mod_name} = $dist_name;
  }
  $sth->finish;
}

sub remove_stale {
  return if $global_opts{setup};
  my $self = shift;
  my $html_root = $self->{html_root};
  my $pod_root = $self->{pod_root};

  my $dist_obj;
  unless ($dist_obj = $self->{dist_obj}) {
    warn "No dist object available";
    return;
  }
  my @goners = ();
  my $data = $dist_obj->{delete};
  if (has_data($data)) {
    push @goners, keys %$data;
  }
  if (@goners) {
    foreach my $dist_root (@goners) {
      my $html_path = catdir $html_root, $dist_root;
      if (-d $html_path) {
	print "Removing $html_path\n";
	rmtree($html_path, $DEBUG, 1)
	  or warn "Cannot rmtree $html_path: $!";
      }
      my $pod_path = catdir $pod_root, $dist_root;
      if (-d $pod_path) {
	print "Removing $pod_path\n";
	rmtree($pod_path, $DEBUG, 1)
	  or warn "Cannot rmtree $pod_path: $!";
      }
    }
  }
  return 1;
}


sub db_error {
  my ($obj, $sth) = @_;
  return unless $dbh;
  $sth->finish if $sth;
  $obj->{error_msg} = q{Database error: } . $dbh->errstr;
}

1;

__END__

=head1 NAME

CPAN::Search::Lite::HTML - convert CPAN documentation to HTML

=head1 DESCRIPTION

This module converts the extracted pod to html_format,
placing the results underneath C<html_root>.

It is assumed here that a local CPAN mirror exists; the C<no_mirror>
configuration option will cause this extraction to be skipped.

=head1 SEE ALSO

L<CPAN::Search::Lite::Index>

=cut

