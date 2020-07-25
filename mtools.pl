#!/usr/bin/env perl

use v5.32;
use strict;
use warnings;

use Path::Tiny qw(path);
use POSIX qw(floor ceil);
$| = 1;

sub parse_opts {
    my %options;
    my $options_left = 1;
    while ($options_left) {
        if ($_[0] eq "-c") {
            shift;
            $options{'container'} = shift;
        } elsif ($_[0] eq "-v") {
            shift;
            $options{'video'} = shift;
        } elsif ($_[0] eq "-a") {
            shift;
            $options{'audio'} = shift;
        } elsif ($_[0] eq "-b") {
            $options{'blank-detect'} = 1;
            shift;
        } elsif ($_[0] eq "-d") {
            shift;
            $options{'duration'} = shift;
        } elsif ($_[0] eq "-t") {
            shift;
            $options{'threshold'} = shift;
        } else {
            undef $options_left;
            $options{'video'}="libx265 -x265-params" if ! defined($options{'video'});
            $options{'audio'}="aac" if ! defined($options{'audio'});
            $options{'container'}="mp4" if ! defined($options{'container'});
            $options{'duration'}=0.5 if ! defined($options{'duration'});
            $options{'threshold'}=0.10 if ! defined($options{'threshold'});
        }
    }
    $options{'rest'} = \@_;
    return (%options);
}

sub mrec {
    # use simplescreenrecorder for this
    my $out = shift // "~/default.mkv";
    print "Start simplescreenrecorder writing to " . $out . "\n";
    my $conf = path("~/.ssr/settings.conf");
    my $data = $conf->slurp_utf8;
    $data =~ s|\bfile=.*|file=$out|;
    $conf->spew_utf8($data);
    system("/usr/bin/simplescreenrecorder --start-recording");
}

sub mjoin {
    print "Joining files @_\n";
    my $conf = path("concat.txt");
    $conf->spew_utf8(map { "file " . $_ . "\n" } @_);
    my @f = (split /\./, $_[0]); # assume only two parts
    my $ext = pop @f;
    my $out = (join '.', @f) . "_out." . $ext;
    print "Joining into file " . $out . "\n";
    system("ffmpeg -f concat -safe 0 -i concat.txt -c copy " . $out);
    unlink "concat.txt";
}

# accepts -c -a -v
sub mconv {
    my %opts = %{$_[0]};
    print "Converting file to container using $opts{'video'} $opts{'audio'} in container " .
        $opts{'container'} . "\n";
    foreach my $file (@{$opts{'rest'}}) {
        my @f = split /\./, $file;
        my $cmd = "ffmpeg -i " . $file .
            " -c:v $opts{'video'} crf=25 -c:a $opts{'audio'} " . $f[0] . "." . $opts{'container'};
        print "Calling ". $cmd . "\n";
        system($cmd);
    }
}

sub blanks {
    my $file = shift;
    my $duration = shift;
    my $threshold = shift;

    my $length = `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file"`;
    my @points = `ffmpeg -i '$file' -vf blackdetect=d=$duration:pix_th=$threshold -an -f null - 2>&1 | grep -o blackdetect.*`;
    my @chunks = (0);
    if ($#points > 0) {
        foreach my $point (@points) {
            print "Found blank: " . (chomp $point) . "\n";
            my ($start, $end) = map {(split / /, $_)[0]} (split /:/, $point)[1..2];
            #print $start . " ## " . $end . "\n";
            push @chunks, (($start + $end) / 2);
        }
    }
    push @chunks, floor ($length);
    return @chunks;
}

# timestamps are
# 10 means 10 seconds
# 1:10 means 1 minute and 10 seconds
# 1:0:0 means 1 hour
sub timestamps {
    my @chunk;
    foreach my $timestamp (@_) {
        my @stamp = split /:/, $timestamp;
        my $seconds += $stamp[-1];
        if ($stamp[-2]) {$seconds += $stamp[-2] * 60}
        if ($stamp[-3]) {$seconds += $stamp[-3] * 3600}
        push @chunk, $seconds;
    }
    return @chunk;
}

sub msplit {
    print "Split video file...\n";
    my @chunks;
    my %opts = %{$_[0]};
    my $file = shift @{$opts{'rest'}};

    if ($opts{'blank-detect'}) {
        print "Detecting blanks with the configuration d=$opts{'duration'}".
            ":pix_th=$opts{'threshold'}\n";
        @chunks = blanks ($file, $opts{'duration'}, $opts{'threshold'});
        print "Splitting video file " . $file . " into " . $#chunks . " chunks\n";
    } else {
        @chunks = timestamps (@{$opts{'rest'}});
        print "Splitting video file " . $file . " into " . $#chunks . " chunks\n";
    }

    my @parts = split /\./, $file;
    foreach my $i (0 .. $#chunks) {
        if ($i + 1 <= $#chunks) {
            my $out = (join '.', @parts[0 .. $#parts - 1])  . "_" . $i . "." . $parts[-1];
            my $cmd ="ffmpeg -i '" . $file .
                           "' -ss " . $chunks[$i] . " -t " . ($chunks[$i+1] - $chunks[$i]) .
                           " -c:v copy -c:a aac '" . $out . "'";
            print "Chunking from: " . $chunks[$i] . " to " . $chunks[$i+1];
            print " resulting file " . $out . "\n";
            #print "Calling " . $cmd . "\n";
            system($cmd);
        }
    }
}

sub mcut {
    print "cut"
}

sub help {
    print "mtools.pl - Small scripts to help working with video files quickly.\n\n";
    print "Usage mtools.pl [command] [options] [files]\n";
    print "Commands:\n";
    print " join\tJoin multiple video files.\n  Mandatory: <files>\n\n";
    print " rec\tScreenrecord to file.\n  Optional: <file>\t[Default: ~/default.mkv]\n\n";
    print " conv\tDecode input into x265 video codec.\n  Mandatory: <file>\n  Options:\n";
    print "\t-c <container format>  Name of the container format.\n";
    print "\t-a <audio codec>       Name of the audio codec, see ffmpeg.\n";
    print "\t-v <video codec>       Name of the video codec, see ffmpeg.\n";
    print " split\tSplit video into chunks.\n  Mandatory: <file> <list of hh:mm:ss>\n  Options:\n";
    print "\t-b\tAutomagically search for blanks, see ffmeg. Ommit timestamps.\n";
    print "\t-d <blank duration>\tSet duration for blank screens. [Default: 0.5]\n";
    print "\t-t <blank threshold>\tSet threshold for blankness. [Default: 0.1]\n";
}

if ($#ARGV + 1 > 0) {
    my $prog = $ARGV[0]; shift;
    my %opts = parse_opts (@ARGV);

    if    ($prog eq "rec")   { mrec (@{$opts{'rest'}})   }
    elsif ($prog eq "join")  { mjoin (@{$opts{'rest'}})  }
    elsif ($prog eq "conv")  { mconv (\%opts)  }
    elsif ($prog eq "split") { msplit (\%opts) }
    elsif ($prog eq "cut")   { mcut ($opts{'rest'})   }
    elsif ($prog eq "help")  { help () } else { help () }

} else {
    print "Not enough arguments. At least provide \$prog or help as argument.";
}
