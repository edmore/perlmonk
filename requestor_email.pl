#! /usr/bin/perl

## Generic email notification for service requestors

use strict;
use Email::Valid;

sub mailRequestor($$$$$)
{
  my ($from, $to, $cc, $subject, $body) = @_;
  my $sender = "bounces\@vula.uct.ac.za";

  if (Email::Valid->address($to)) {
    sendEmail($sender, $from, $to, $cc, $subject, $body);
  }
}

sub sendEmail($$$$$$)
{
  my $sender = shift;
  my $from = shift;
  my $to = shift;
  my $cc = shift;
  my $subject = shift;
  my $content = shift;
  $to = trim($to);
  $cc = trim($cc);
  $subject = trim($subject);

  my $sendmail = "/usr/sbin/sendmail -f $sender -t";

  open(SENDMAIL, "|$sendmail") or die "Cannot open $sendmail: $!";
  print SENDMAIL "From: $from\n";
  print SENDMAIL "Subject: $subject\n";
  print SENDMAIL "To: $to\n";
  print SENDMAIL "CC: $cc\n";
  print SENDMAIL "Content-type: text/plain\n\n";
  print SENDMAIL $content;
  close(SENDMAIL);
}

## Trim a string: http://www.somacon.com/p114.php
sub trim($)
{
  my $string = shift;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  return $string;
}

return 1;

