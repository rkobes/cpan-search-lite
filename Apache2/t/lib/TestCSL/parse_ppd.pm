package TestCSL::parse_ppd;
use strict;
use warnings;
use XML::SAX;
use base qw(Exporter);
our (@EXPORT_OK);
@EXPORT_OK = qw(parse_ppd);

sub parse_ppd {
  my $string = shift;
  XML::SAX->add_parser(q(XML::SAX::ExpatXS));
  my $factory = XML::SAX::ParserFactory->new();
  my $handler = PPMHandler->new();
  my $parser = $factory->parser( Handler => $handler);

  eval { $parser->parse_string($string); };
  if ($@) {
    print "Error in parsing string: $@\n";
    return;
  }
  return $handler->{ppd};
}

# begin the in-line package
package PPMHandler;
use strict;
use warnings;

my ($i, $j);
my %wantarray = map {$_ => 1} qw(REQUIRE PROVIDE DEPENDENCY);
my %count = ();
my $curr_el = '';

sub new {
  my $type = shift;
  return bless {text => '', ppd => {}}, $type;
}

sub start_document {
  for (keys %wantarray) {
    $count{$_} = 0;
  }
  my ($self) = @_;
   # print "Starting document\n";
  $self->{text} = '';
}

sub start_element {
  my ($self, $element) = @_;
  $curr_el = $element->{Name};
  # print "Starting $element->{Name}\n";
  my $ppd = $self->{ppd};
  $self->display_text();
  foreach my $ak (keys %{ $element->{Attributes} } ) {
    my $at = $element->{Attributes}->{$ak};
    my $name = $at->{Name};
    my $value = $at->{Value};
    if ($wantarray{$curr_el}) {
      $ppd->{$curr_el}->[$count{$curr_el}]->{$name} = $value;
    }
    else {
      $ppd->{$curr_el}->{$name} = $value;
    }
    # print qq(Attribute $curr_el: $at->{Name} = "$at->{Value}"\n);
  }
}

sub characters {
  my ($self, $characters) = @_;
  my $text = $characters->{Data};
  $text =~ s/^\s*//;
  $text =~ s/\s*$//;
  $self->{text} .= $text;
}

sub end_element {
  my ($self, $element) = @_;
  $curr_el = $element->{Name};
  $self->display_text();
  if ($wantarray{$curr_el}) {
    $count{$curr_el}++;
  }
  # print "Ending $element->{Name}\n";
}

sub display_text {
  my $self = shift;
  my $ppd = $self->{ppd};
  if ( defined( $self->{text} ) && $self->{text} ne "" ) {
    $ppd->{$curr_el} = $self->{text};
    # print " text: $curr_el: [$self->{text}]\n";
    $self->{text} = '';
  }
}

sub end_document {
  my ($self) = @_;
  # print "Document finished\n";
}

1;
