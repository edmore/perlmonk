#! /usr/bin/perl

require LWP::UserAgent;
require HTTP::Cookies;
require HTTP::Request;

use SOAP::Lite;
use HTTP::Request::Common qw(PUT POST);
use Encode;
use Image::Size;
use URI::Escape;
use File::Copy;
use Date::Parse;
use Time::Format qw(%time %strftime %manip);
use Data::Validate::URI qw(is_http_uri is_https_uri);
use Data::Dumper;
use JIRA::Client;

require '/usr/local/sakaiconfig/vula_auth.pl';
require 'requestor_email.pl';

use strict;

my $MAX_FILESIZE = 102400;
my $DEBUG = "FALSE";
my $IMAGE_WIDTH = 600;
my @ACCEPTED_FORMATS = ( "jpeg", "jpg", "gif", "png" );
my $TARGET_FOLDER = $ARGV[0];

# JIRA details
my ($jira_user, $jira_pass) = getCETJiraAuth();
my ($svn_user, $svn_pass) = getSVNJiraAuth();
my $jira_host = "https://jira.cet.uct.ac.za";
my $jira_filterId = "10733";
my $jira_assignee = "vulahelp";

my $jira = initialize($jira_host, $jira_user, $jira_pass);

# Get issue list from JIRA filter
logger("Processing Request ....\n");
my @jiras = getIssuesForFilter($jira, $jira_filterId);

# Process a list of the issues
foreach (@jiras){
  my  $issue = $_;
  my $valid_url = 1;
  my ($category, $hyperlink, $until_date) = getCustomFieldsFor($issue);

  if( defined($hyperlink) ){
    my $valid_url = isValidURL($hyperlink);
  }

  if( defined($category) && defined($until_date) && $valid_url == 1){
    checkAttachmentFor($issue);
  }
}

## Initialize
sub initialize($$$){
  my ($host, $username, $password) = @_;
  JIRA::Client->new($host, $username, $password);
}

## Get a list of issue keys in the filter.
sub getIssuesForFilter($$) {
  my ($jira, $filter) = @_;
  my $issuelist = $jira->getIssuesFromFilter($filter);

  my @issues = ();
  for my $issue (@{$issuelist}) {
    push(@issues, $issue->{key});
  }
  return @issues;
}

# Resolve Issue
sub resolveIssue($$$) {
    my ($jira, $issuekey, $comment) = @_;

    $jira->addComment($issuekey, $comment);
    $jira->progressWorkflowAction($issuekey, 5,
       {
         resolution => 1
       }
     );
}

# Assign an issue
sub assignIssue($$$$) {
    my ($jira, $issuekey, $assignee, $comment) = @_;

    if ($comment ne "") {
    	$jira->addComment($issuekey, $comment);
    }

    $jira->updateIssue($issuekey,
       {
         assignee => $assignee
       }
     );

}

## Get Custom Fields
sub getCustomFieldsFor($){
  my $issue = shift;
  logger("Checking Custom fields for $issue ....\n");

  my ($custom_category, $category) = "customfield_10321", "";
  my ($custom_hyperlink, $hyperlink) = "customfield_10322", "";
  my ($custom_until_date, $until_date) = "customfield_10320", "";
  my $issue = $jira->getIssue($issue);

  for my $customfield (@{$issue->{customFieldValues}}) {
    $category = $customfield->{values}[0] if ($customfield->{customfieldId} eq $custom_category);
    $hyperlink = $customfield->{values}[0] if ($customfield->{customfieldId} eq $custom_hyperlink);
    $until_date = $customfield->{values}[0] if ($customfield->{customfieldId} eq $custom_until_date);
  }
  return ($category, $hyperlink, $until_date);
}

## Check the attachment
sub checkAttachmentFor($){
  my $issue = shift;
  logger("Checking Attachment for $issue ... \n");
  my $attachments = $jira->getAttachmentsFromIssue($issue);
  my $size_verify = "";
  my $format_verify = "";
  my $dimensions_verify = "";

  #get the number of the attachments
  my $size =  @{$attachments};

  if ( $size == 1 ){
    my $attachment_id = @{$attachments}[0]->{id};
    my $attachment_filesize = @{$attachments}[0]->{filesize};
    my $attachment_mimetype = @{$attachments}[0]->{mimetype};
    my $attachment_type = substr($attachment_mimetype, 6) if $attachment_mimetype =~ /image/;
    my $attachment_filename = $attachment_id.".".$attachment_type;

    my $image_url = $jira_host."/secure/attachment/".$attachment_id."/".$attachment_filename;

    #Get the image and store locally
    my $command = "wget --no-check-certificate ".$image_url."\?os_username\=$jira_user\\&os_password\=$jira_pass -O $attachment_filename";
    system($command);

    #Check the image dimensions
    my ($width, $height) = imgsize($attachment_filename);

    # Verify that the metadata is as per requirement
    $size_verify = check_filesize($attachment_filesize);
    $format_verify = check_format($attachment_type);
    $dimensions_verify = check_dimensions($width, $height);

    if( $size_verify && $format_verify && $dimensions_verify ){
      move($attachment_filename, "$TARGET_FOLDER//$attachment_filename") if -e $attachment_filename;
      chdir($TARGET_FOLDER);
      logger("svn add $attachment_filename \n") if -e $attachment_filename;
      system("svn add $attachment_filename") if -e $attachment_filename;

      my ($issue_category, $issue_hyperlink, $issue_until_date) = getCustomFieldsFor( $issue );
      $issue_until_date = str2time($issue_until_date);
      $issue_until_date = $time{ 'yyyy-mm-dd hh:mm', $issue_until_date };

      logger("Modifying Files file...\n");
      # Append to end of file
      open(my $files, ">>files") or die "Can't open files: $!";
      print $files "\n$issue_category,$attachment_filename,$issue_until_date,$issue_hyperlink";
      close $files or die "$files: $!";

      system("svn ci -m \"$issue : Adding $attachment_filename\" --username $svn_user --password $svn_pass") if -e $attachment_filename;
      logger("Email Requestor and Resolve");
      my ($emailbody, $recipient) = processEmailFor($issue);
      resolveIssue($jira, $issue, "Emailed to: $recipient\n\n---\n\n$emailbody");
      assignIssue($jira, $issue, $jira_assignee,"");
    }
    else
    {
      logger("Verification failed\n");
      logger("Re-assign\n");
      assignIssue($jira, $issue, $jira_assignee, "Image not uploaded. Please check size, format or dimensions.");
      fileCleanup( $attachment_filename );
    }
  }
  else
  {
    logger("There should only be one attached image for $issue.\n");
    logger("Re-assign\n");
    assignIssue($jira, $issue, $jira_assignee, "Image not uploaded. There should only be one attached image.");
  }
}

# Logger
sub logger($){
  my $msg = shift;
  print $msg if $DEBUG eq "TRUE";
}

# File Cleanup
sub fileCleanup($){
  my $file = shift;
  system("rm -f $file") if -e $file;
}

## Compare file size to the maximum of 100KB
sub check_filesize($){
  my $filesize = shift;
  return ( $filesize <= $MAX_FILESIZE )
}

## Check that the format is one of the accepted formats
sub check_format($){
  my $format = shift;

  foreach (@ACCEPTED_FORMATS){
    return 1 if $format eq $_;
  }
  return;
}

## Check that dimensions have a width of 600 and height between 400 and 450 px
sub check_dimensions($$){
  my ( $w, $h ) = @_;
  return ( $w == $IMAGE_WIDTH && ($h >= 400 && $h <= 450) );
}

## Check if a URL is valid
sub isValidURL($){
  my $uri = shift;
  return unless is_http_uri($uri) || is_https_uri($uri);
  return 1;
}

# Process the email request
sub processEmailFor($){
  my $issuekey = shift;
  my $email;
  my $recipient_name;
  my $to;
  my $cc = "\"The Vula Help Team\" <help\@vula.uct.ac.za>";
  my $from = $cc;
  my $subject;
  my $body;
  my $issue = $jira->getIssue($issuekey);

  if ($issue->{description} =~ /<(.*?)>/) {
    $email = $1;
  }

  if ($issue->{description} =~ /:\s*(.*?)\s*</) {
    $recipient_name = $1;
  }

  $subject = "RE: \[$issue->{key}\] $issue->{summary}\n";
  $body = getLandingPageTemplate( $recipient_name );
  $to = "\"$recipient_name\" <$email>" if $recipient_name && $email;

  if($to ne ""){
    mailRequestor($from, $to, $cc, $subject, $body);
  }
  return ($body, $email);
}

# Landing Page Template
sub getLandingPageTemplate($){
  my $name = shift;
my $content = <<END;
Good day $name,

Your image has been successfully uploaded to the Vula Landing page.

The Vula Help Team
Centre for Educational Technology, UCT
Email: help\@vula.uct.ac.za
Phone: 021-650-5500
END
return $content;
}

