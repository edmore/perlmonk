#! /usr/bin/perl

use strict;
use JSON;
use Text::CSV;
use DateTime;
use Date::Parse;

my @groups;
my @files;
my @newsflash;
my $TARGET_FOLDER = $ARGV[0];
my $csv = Text::CSV->new ( { binary => 1 } ) or die "Cannot use CSV: ".Text::CSV->error_diag ();

# Get the contents of the "groups" file
open my $fh, "<:encoding(utf8)", "$TARGET_FOLDER/groups" or die "groups: $!";
while ( my $group = $csv->getline( $fh ) ) {
    my $size = @{$group};
    push (@groups, $group) if $size == 2;
}
$csv->eof or $csv->error_diag();
close $fh;

# Get the contents of the "files" file
open my $fh, "<:encoding(utf8)", "$TARGET_FOLDER/files" or die "files: $!";
while ( my $file = $csv->getline( $fh ) ) {
    my $file_location = "$TARGET_FOLDER/$file->[1]";
    my $expiry_date = str2time( $file->[2] );
    my $today = str2time( DateTime->now );
    push (@files, $file) if -e $file_location && ($expiry_date eq "" || $expiry_date >= $today);
}
$csv->eof or $csv->error_diag();
close $fh;

# Get the contents of the "newsflash" file
open my $fh, "<:encoding(utf8)", "$TARGET_FOLDER/newsflash" or die "news_flash: $!";
while ( my $news = $csv->getline( $fh ) ) {
    my $size = @{$news};
    my $date_open = str2time( $news->[0] );
    my $date_closed = str2time( $news->[1] );
    my $today = str2time( DateTime->now );
    push (@newsflash, $news) if $size == 3 && ($date_open eq "" || $date_open <= $today) && $date_closed >= $today;
}
$csv->eof or $csv->error_diag();
close $fh;

my $files_encoded = encode_json \@files;
my $groups_encoded = encode_json \@groups;
my $newsflash_encoded = encode_json \@newsflash;

# Create the html file
open(my $html_file, ">", "$TARGET_FOLDER/vula_rotate.html.new") or die "cannot open > vula_rotate.html: $!";

my $html = <<HTML;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<html>
<head>
<title>Welcome to Vula</title>
<link href="css/newsflash.css" rel="stylesheet" type="text/css">
<script type="text/javascript">
var groups = $groups_encoded;
var files = $files_encoded;
var newsflash = $newsflash_encoded;
</script>
<script src="/library/js/jquery.js" type="text/javascript"></script>
</head>
<body>
<div class="n-f"><div class="n-c"><div class="n-a"><div class="n-e">
</div></div></div></div>
<div class="vula_landing">
</div>
<script src="js/vula_rotate.js" type="text/javascript"></script>
</body>
</html>
HTML

print $html_file $html;
close $html_file or die "$html_file: $!";

# Rename file to vula_rotate.html.new to vula_rotate.html
rename "$TARGET_FOLDER/vula_rotate.html.new", "$TARGET_FOLDER/vula_rotate.html"

