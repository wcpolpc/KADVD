#! /bin/sh
eval '(exit $?0)' && eval 'PERL_BADLANG=x;PATH="$PATH:.";export PERL_BADLANG\
 PATH;exec perl -x -S -- "$0" ${1+"$@"};#'if 0;eval 'setenv PERL_BADLANG x\
;setenv PATH "$PATH":.;exec perl -x -S -- "$0" $argv:q;#'.q
#!perl -w
+push@INC,'.';$0=~/(.*)/s;do(index($1,"/")<0?"./$1":$1);die$@if$@__END__+if 0
;#Don't touch/remove lines 1--7: http://www.inf.bme.hu/~pts/Magic.Perl.Header
#
# genmpeg.pl -- generate DVD-ready MPEG2 with simple sound
# by pts@fazekas.hu at Sun Jul 16 16:42:27 CEST 2006
#
# genmpeg.pl is a Perl script that generates a simple MPEG2 program stream
# file from a series of input images and/or solid colors. The file will
# also have two audio channels with simple sine waves.
# Both PAL and NTSC and many aspect ratios are supported. The generated
# MPEG2 file is suitable for direct DVD title and menu authoring with
# dvdauthor, without
# the need for reencoding. ffmpeg is requred.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# Dat: see gen256mpegs.sh for an example of genmpeg.pl in action
# Dat: dependencies:
#      -- convert (only if the image is not a single color solid)
#      -- ffmpeg
# Dat: mplayer doesn't show total time when playing generated MPEG --
#      but shows it when playing DVD generated from it by dvdauthor
# Dat: the raw (.yuv) image format piped to ffmpeg is YUV 4:2:0 Planar.
#      It uses the YUV color space, emits the Y plane first, then emits the
#      U plane (with both width and height scaled down by a factor of 2),
#      and then the V plane (ditto, scaled down by 2).
# Imp: why does dvdauthor show PTS starting from 0.5 instead of 0?
# Imp: pipe VIDEO to ffmpeg (and thus use less disk space)
#

use integer;
use strict;

BEGIN { $main::VERSION='0.04' }

sub fnq($) {
  #return $_[0] if substr($_[0],0,1)ne'-'
  return $_[0] if $_[0]!~m@[^-_/.0-9a-zA-Z]@;
  my $S=$_[0];
  $S=~s@'@'\\''@g;
  "'$S'"
}

my $ffmpeg_cmd='ffmpeg';

#** Number of video frames to generate
my $nframes=100;

#my @yuvcolor=(0,0,0); # Dat: green
#my $out_fn='green.mpeg';
my $out_fn;

#** sampling rate in Hz (samples per second). Must be 44100 or 48000.
#** For DVD, it must be 48000.
my $audio_rate=48000;

#** Video bitrate when loading an image as frame (in kbit/s).
#** Dat: 7500 by default for mpeg2enc
my $nice_video_bitrate=5000;

#** (in kbit/s)
my $audio_bitrate=128;

#** Video bitr
my $still_video_bitrate=300;

#** 'ffmpeg' or 'mpeg2enc'
#** Dat: ffmpeg and mpeg2enc are equally good. Using only ffmpeg is faster.
#**      If you are experiencing bad colors, that might be due to ImageMagick
#**      `YUV' being brighter than what ffmpeg and mpeg2enc expect -- but
#**      genmpeg.pl doesn't use ImageMagick YUV by default anymore, but it
#        uses ppmtoy4m
my $video_with='ffmpeg';

#** Affected by set_defaults_*().
my $norm;
#** Affected by set_defaults_*().
my $ffmpeg_target;
#** Affected by set_defaults_*().
#** Before aspect ratio correction
my $framew;
#** Affected by set_defaults_*().
#** Before aspect ratio correction
my $frameh;
#** Affected by set_defaults_*().
my $fps_num;
my $fps_den;
#** Affected by set_defaults_*().
#** String.
my $ffmpeg_fps='25'; # Imp: '29.97' for NTSC?
#** 'mp2' (for PAL DVDs) or 'ac3' (for PAL and NTSC DVDs).
my $ffmpeg_acodec;

sub set_defaults_pal() {
  $norm='PAL';
  $ffmpeg_target='pal-dvd';
  $framew=720; $frameh=576;
  $fps_num=25;
  $fps_den=1;
  $ffmpeg_fps='25';
  $ffmpeg_acodec='mp2';
}

sub set_defaults_ntsc() {
  $norm='NTSC';
  $ffmpeg_target='ntsc-dvd';
  $framew=720; $frameh=480;
  $fps_num=30000;
  $fps_den=1001;
  $ffmpeg_fps='30000/1001'; # verified at Mon Jan 29 15:02:27 CET 2007
  # Imp: is NTSC 16:9 854x480 ??
  $ffmpeg_acodec='ac3'; # Dat: NTSC DVDs must have AC3
}

#set_defaults_pal();

#** 'left' or 'right' or 'mute';
my $high_pitch_channel='right';
my $aspect='4:3';

# --- subs

sub clip255($) {
  no integer;
  my $V=int($_[0]+.5); $V<0 ? 0 : $V>255 ? 255 : $V
}

#** @param ($_[0],$_[1],$_[2]) Y,U,V value in 0..255
#** @return ($R,$G,$B)
sub yuv_to_rgb($$$) {
  my($Y,$U,$V)=@_;
  no integer;
  clip255(1.164*($Y - 16) + 1.596*($V - 128)), # R
  clip255(1.164*($Y - 16) - 0.813*($V - 128) - 0.391*($U - 128)), # G
  clip255(1.164*($Y - 16)                    + 2.018*($U - 128)), # B
}

#** @param ($_[0],$_[1],$_[2]) R,G,B value in 0..255
#** @return ($Y,$U,$V)
sub rgb_to_yuv($$$) {
  my($R,$G,$B)=@_;
  no integer;
  clip255( (0.257 * $R) + (0.504 * $G) + (0.098 * $B) + 16 ), # Y
  clip255(-(0.148 * $R) - (0.291 * $G) + (0.439 * $B) + 128), # U
  clip255( (0.439 * $R) - (0.368 * $G) - (0.071 * $B) + 128), # V
}

#** Dat: it is also ok to use '#abcd42' RGB triplet form
my %named_colors=(
  black   => '#000',
  white   => '#fff',
  red     => '#f00',
  green   => '#0f0', 
  blue    => '#00f', 
  yellow  => '#ff0',
  cyan    => '#0ff', 
  purple  => '#f0f',
  lightblue => '#add8e6', 
);

#** @param $_[0] string, e.g. RGB color spec "#abcd42"
#** @return ($Y,$U,$V), all values in 0..255
sub get_yuv_color($) {
  my $spec=$_[0];
  $spec=$named_colors{$spec} if defined $named_colors{$spec};
  if ($spec=~/\A#([A-Fa-f0-9])([A-Fa-f0-9])([A-Fa-f0-9])\Z(?!\n)/) {
    rgb_to_yuv(hex($1)*17,hex($2)*17,hex($3)*17)
  } elsif ($spec=~/\A#([A-Fa-f0-9]{2})([A-Fa-f0-9]{2})([A-Fa-f0-9]{2})\Z(?!\n)/) {
    rgb_to_yuv(hex($1),hex($2),hex($3))
  } else { die "$0: unknown color spec: $spec\n" }
}
  

# --- main() @ARGV

select(STDERR); $|=1;
select(STDOUT); $|=1;

my %defaults=(
  #** 'no-scale', 'stretch' or 'keep-aspect';
  image_scale_mode => 'stretch',
  #** Accepted by ImageMagick's xc:
  image_scale_background => 'blue',
);
#** :Array(Hashref), where has is like %defaults
my @framespecs;
my $has_nice_frame=0;
my $has_solid;

if (!@ARGV or (@ARGV==1 and ($ARGV[0] eq '--help' or $ARGV[0] eq '-h'))) {
  print "This is genmpeg.pl, version $main::VERSION, by <pts\@fazekas.hu>\n";
  print "The license is GNU GPL >=2.0. It comes without warranty. USE AT YOUR OWN RISK!\n\n";
  print "Usage: $0 [<option> ...] [--mute] [--norm={pal|ntsc|detect-from-bg}] [--nframes=...] [--outfile=...] { --from-image=<image.file> | --solid=<color> } ...\n";
  print "Example: $0 --solid=red\n";
  print "There are some undocumented options. Look for \@ARGV in the source.\n";
  exit(0);
}


{ my $I=0;
  while ($I<@ARGV) {
    if ($ARGV[$I]eq'--') { $I++; last }
    elsif (substr($ARGV[$I],0,1)ne'-') { last }
    elsif ($ARGV[$I]eq'--help') { die "$0: please specify --help first\n" }
    #** Each item in @framespecs is repeated this many times.
    elsif ($ARGV[$I]=~/^--nframes=(\d+)\Z(?!\n)/) { $nframes=$1+0 }
    elsif ($ARGV[$I]=~/^--outfile=(.*)\Z(?!\n)/s) { $out_fn=$1 }
    #** Add an image (from external file).
    elsif ($ARGV[$I]=~/^--from-image=(.*)\Z(?!\n)/s) {
      push @framespecs, { %defaults, in_image_fn=>$1 };
      $has_nice_frame=1;
    }
    #** Add a solid image (consisting of a single color)
    #** Colors are processed by get_yuv_color()
    elsif ($ARGV[$I]=~/^--solid=(.*)\Z(?!\n)/s) {
      push @framespecs, { %defaults, solid_yuv_color=>[get_yuv_color($1)] };
      $has_solid=$1 if !defined $has_solid;
    }
    elsif ($ARGV[$I]=~/^--image-scale-mode=(keep-aspect|stretch|no-scale)\Z(?!\n)/s) { $defaults{image_scale_mode}=$1 }
    elsif ($ARGV[$I]=~/^--image-scale-background=(.*)\Z(?!\n)/s) { $defaults{image_scale_background}=$1 }
    elsif ($ARGV[$I]=~/^--high-pitch-channel=(left|right|mute)\Z(?!\n)/s) { $high_pitch_channel=$1 }
    #** Produce silent audio stream.
    elsif ($ARGV[$I] eq '--mute') { $high_pitch_channel='mute' }
    elsif ($ARGV[$I]=~/^--aspect=(16:9|16:10|4:3|1:1|221:100|5:4)\Z(?!\n)/s) { $aspect=$1 }
    #** In kbit/s.
    #** Video bitrate to use if there are non-solid images.
    elsif ($ARGV[$I]=~/^--nice-video-bitrate=([1-9]\d*)\Z(?!\n)/s) { $nice_video_bitrate=$1+0 }
    #** In kbit/s.
    #** Video bitrate to use if only --solid (one-color) images are present.
    elsif ($ARGV[$I]=~/^--still-video-bitrate=([1-9]\d*)\Z(?!\n)/s) { $still_video_bitrate=$1+0 }
    elsif ($ARGV[$I]=~/^--audio-codec=(mp2|ac3|MP2|AC3)\Z(?!\n)/s) { $ffmpeg_acodec=lc($1) }
    elsif ($ARGV[$I]=~/^--video-with=(ffmpeg|mpeg2enc)\Z(?!\n)/s) { $video_with=$1 }
    elsif ($ARGV[$I]=~/^--norm=(.*)\Z(?!\n)/s) {
      my $norm0=$1; my $norm1=uc($norm0);
      if ($norm1 eq 'PAL') { set_defaults_pal() }
      elsif ($norm1 eq 'NTSC') { set_defaults_ntsc() }
      elsif ($norm0 eq 'detect-from-bg') { $norm=$norm0 }
      else { die "$0: unknown norm: $norm0\n" }
    }
    elsif ($ARGV[$I] eq '--version') { print "genmpeg.pl v$main::VERSION\n"; exit 0 }
    else { die "$0: unknown option: $ARGV[$I]\n" }
    $I++;
  }
  splice(@ARGV,0,$I);
}
die "$0: too many args\n" if @ARGV;

die "$0: please use --from-image=... and/or --solid=... to specify video\n" if
  !@framespecs;

if (!defined $norm) { # Try to detect norm from an image file (w/o aspect ratio correction; not to be scaled)
  my $imgfn;
  for my $framespec0 (@framespecs) {
    next if !exists $framespec0->{in_image_fn};
    $imgfn=$framespec0->{in_image_fn};
    my $imgf;
    next if !open($imgf,'<',$imgfn);
    my $head;
    read($imgf,$head,4096);
    close($imgf);
    next if !defined($head) or 4>length($head);
    my($width,$height);
    if ($head=~/\AP[1-6]\s+(?:#.*\n\s*)*(\d+)\s+(?:#.*\n\s*)*(\d+)\s/) { # PNM
      $width=$1+0; $height=$2+0;
    #} elsif (...) { # Imp: detect image size in other file formats
    }
    if (!defined $width or !defined $height) {
    } elsif ($width==720 and $height==576) {
      set_defaults_pal(); last
    } elsif ($width==720 and $height==480) {
      set_defaults_ntsc(); last
    } else {
      die "$0: 720x576 PAL or 720x480 NTSC expected, got ${width}x$height in image $imgfn\n";
    }
  }
}
die "$0: missing --norm= (and cannot autodetect)\n" if !defined $norm;

die "$0: solid or image?!\n" if $has_nice_frame and $has_solid;
$out_fn="solid_$has_solid.mpeg" if !defined $out_fn and $has_solid and !$has_nice_frame and 1==@framespecs;
die "$0: please specify --outfile=....mpeg\n" if !defined $out_fn;
die "$0: --norm=NTSC implies --audio-codec=AC3\n" if
  $norm eq 'NTSC' and $ffmpeg_acodec ne 'ac3';
die "$0: frame width is odd: $framew\n" if 0!=$framew%2;
die "$0: frame height is odd: $frameh\n" if 0!=$frameh%2;
#die "$0: bad audio codec: $ffmpeg_acodec\n";

# ---

#** Example: $genyuvfns{"in.jpg"}="generated.yuv";
my %genyuvfns;
my $totalframes=0;
my $framesize=$framew*$frameh+(($framew+1)>>1)*(($frameh+1)>>1)*2;
my $create_y4m_p=($video_with eq 'mpeg2enc') ? 1 : 0;

{ # Dat: ffmpeg assumes RAW YUV420P (planar) input for .yuv extension
  # vvv Imp: work without this temp file
  die if !open VIDEO, "> genmpeg_tmp.yuv";
  if ($create_y4m_p) {
    my $fpsdiv="$fps_num:$fps_den";
    die if !print VIDEO "YUV4MPEG2 W$framew H$frameh F$fps_num:$fps_den Ip A1:1 C420jpeg\n";
  }
  #** In bytes;
  my $framedata;

  for my $framespec (@framespecs) {
    my $skip_y4m_header_p=0;
    if (defined $framespec->{in_image_fn}) {
      my $fsize=(-s $framespec->{in_image_fn});
      die "$0: cannot get file size for: $framespec->{in_image_fn}\n" if !defined $fsize;
      my $imgfn;
      if ($framespec->{in_image_fn}=~/[.]yuv\Z(?!\n)/i and $fsize==$framesize) {
        # !! handle .y4m
        $imgfn=$framespec->{in_image_fn};
      } elsif (defined $genyuvfns{$framespec->{in_image_fn}}) {
        # Dat: image already processed by convert(1)
        $imgfn=$genyuvfns{$framespec->{in_image_fn}};
      } else {
        # vvv Imp: spec, `-' filename
        my $ppmfn='genmpeg_tmp'.(scalar(keys %genyuvfns)+1).'.ppm'; # Dat: multipurpose
        $imgfn='genmpeg_tmp'.(scalar(keys %genyuvfns)+1).'.yuv'; # Dat: multipurpose
        $genyuvfns{$framespec->{in_image_fn}}=$imgfn;
        # Dat: -scale is faster than -resize, see ImageMagick's docs
        # vvv Imp: ability to specify aspect ratio
        my @convert_cmd=('convert',$framespec->{in_image_fn},
          ($framespec->{image_scale_mode} eq 'no-scale' ?
            ('-size', "${framew}x${frameh}", "xc:$framespec->{image_scale_background}",
              '+swap','-gravity','center','-composite') :
            $framespec->{image_scale_mode} eq 'stretch' ?
            ('-resize',"${framew}x${frameh}!") :
            # vvv Dat: from http://www.cit.gu.edu.au/~anthony/graphics/imagick6/resize/
            # vvv Imp: calculate aspect ratio
            ('-resize',"${framew}x${frameh}", # Dat: keeps aspect while resizing
              '-size', "${framew}x${frameh}", "xc:$framespec->{image_scale_background}",
              '+swap','-gravity','center','-composite')
          ),
          # Dat: -resize -extent adds padding, -extends just does scaling
          #'-scale',"${framew}x${frameh}!",
          # Imp: add padding so image is centered (`-gravity Center' has no effect)
          #'-format','yuv',
          '-depth', 8, '-format', 'ppm',
          '-interlace','Plane', # Dat: ImageMagick 6.2.8 ignores `-interlace None' for YUV etc.
          $ppmfn, #$imgfn
          );
        print STDERR "info: converting to YUV with: ".join('  ',@convert_cmd)."\n";
        die "error: convert failed\n" if 0!=system @convert_cmd;
        #DEBUG: system('display','-size',"${framew}x$frameh!",$imgfn);
        # Dat: ImageMagick's '-format','yuv' (or YUV:) is almost perfect, but
        #      it creates brighter YUV than necessary.

        my @ppmtoy4m_cmd=('ppmtoy4m','-S','420mpeg2');
        { #local *STDIN; # SUXX: doesn't work
          die unless open STDIN,  '<', $ppmfn;
          die unless open SAVEOUT, '>&STDOUT';
          die unless open STDOUT, '>', $imgfn;
          print STDERR "info: running: ".join('  ',map {fnq$_} @ppmtoy4m_cmd)."\n";
          die "error: ppmtoy4m failed\n" if 0!=system @ppmtoy4m_cmd;
          die unless open STDOUT, '>&SAVEOUT';
          die unless close SAVEOUT;
        }
        $skip_y4m_header_p=1;
        unlink $ppmfn;
      }
      
      die if !open YUVIN, '<', $imgfn;
      if ($skip_y4m_header_p) {
        my $line=<YUVIN>; $line="" if !defined $line;
        die "error: YUV4MPEG2 line 1 has bad header\n" if $line!~m@\AYUV4MPEG2 @;
        $line=<YUVIN>; $line="" if !defined $line;
        die "error: YUV4MPEG2 line 2 has bad header\n" if $line ne "FRAME\n";
      }
      die "error: input image is shorter than $framesize bytes\n" if
        $framesize!=read(YUVIN, $framedata, $framesize);
      die "error: input image is longer than $framesize bytes\n" if
        0!=read(YUVIN, $framedata, 1, length($framedata));
      die if !close YUVIN;
    } else {
      # Dat: YUV 4:2:0 Planar
      my $yuvcolor=$framespec->{solid_yuv_color};
      die if 'ARRAY' ne ref $yuvcolor;
      my $yrow=chr($yuvcolor->[0])x$framew;
      my $yplane=$yrow x$frameh;
      my $urow=chr($yuvcolor->[1])x(($framew+1)>>1);
      my $uplane=$urow x(($frameh+1)>>1);
      my $vrow=chr($yuvcolor->[2])x(($framew+1)>>1);
      my $vplane=$vrow x(($frameh+1)>>1);
      $framedata=$yplane.$uplane.$vplane;
    }
    die if length($framedata)!=$framesize;
    
    for (my $I=0;$I<$nframes;$I++) {
      die if $create_y4m_p and !print(VIDEO "FRAME\n");
      die if !print VIDEO $framedata;
      $totalframes++;
    }
  }
  die if !close VIDEO;
}

{ die if !open AUDIO, "> genmpeg_tmp.wav";
  # Imp: remove few extra samples
  # Dat: header for RIFF (little-endian) data, WAVE audio, Microsoft PCM, 16 bit, stereo 44100 Hz
  my $wavheader="RIFF\$\220\232\002WAVEfmt \020\000\000\000\001\000\002\000D\254\000\000\000\356\002\000\004\000\020\000data\000\220\232\002\000\000\000\000"; # Dat: 48 bytes
  substr($wavheader,24,2)=pack("v",$audio_rate);
  die if !print AUDIO $wavheader;
  my $audio_size;
  { no integer;
    $audio_size=int($audio_rate*4*$fps_den/$fps_num*$totalframes);
    # Imp: round up
  }
  my $C=$audio_size>>12;
  # Into the left audio channel,
  # we emit a 375 Hz sine wave, thus (with $audio_rate==48000) we need
  # 48000/375 == 128 samples in each full period, which is 512 bytes in each
  # full period.
  # Into the right audio channel, we emit an 1500 Hz (high-pitch) sine wave,
  # thus we need 48000/1500 == 32 samples in each full period. We combine 4
  # full periods together, thus we have 128 samples in each combined full
  # period.
  #** It will be the the 512-byte sample data for a full periad
  my $S="";
  if ($high_pitch_channel eq 'mute') {
    $S="\0"x512;
  } else {
    no integer;
    my $pi=4*atan2(1,0);
    my $leftfactor=2*$pi/128;
    my $rightfactor=2*$pi/32;
    ($leftfactor,$rightfactor)=($rightfactor,$leftfactor) if
      $high_pitch_channel eq 'left';
    for (my $I=0;$I<128;$I++) {
      $S.=pack("v*",sin($I*$leftfactor)*32767,sin($I*$rightfactor)*32767);
    }
  }
  die if length($S)!=512;
  $S x=8; # Dat: 512 -> 4096 bytes
  while ($C>0) { print AUDIO $S; $C-- }
  print AUDIO substr($S, 0, $audio_size&4095);
  die if !close AUDIO;
}

if ($video_with eq 'mpeg2enc') {
  die if !$create_y4m_p;
  # Dat: jpeg2yuv(1) produces .y4m
  # Dat: example: jpeg2yuv -n "$nframes" -I p -f 25 -j background.jpg | mpeg2enc -n p -f 8 -o t.m2v
  # Dat: png2yuv(1) also works
  my @mpeg2enc_cmd=('mpeg2enc',
    '-n',($norm eq 'NTSC' ? 'n' : 'p'),
    '-f', 8, # DVD MPEG-2  for dvdauthor. Bitrate 7500kbps
    '-o','genmpeg_tmp.m2v');
  unlink 'genmpeg_tmp.m2v';
  { #local *STDIN; # Imp: verify....
    die unless open STDIN, '<', 'genmpeg_tmp.yuv';
    print STDERR "info: running: ".join('  ',map {fnq$_} @mpeg2enc_cmd)."\n";
    die "error: mpeg2enc failed\n" if 0!=system @mpeg2enc_cmd;
    die "error: mpeg2enc didn't create genmpeg_tmp.m2v\n" if
      !(-s 'genmpeg_tmp.m2v');
  }
}

#sleep 5;

my $video_bitrate=($has_nice_frame ? $nice_video_bitrate :
  $still_video_bitrate);

my $audio_bitrate_factor=1;
#** Newer (SVN Sat Mar 24 13:10:27 CET 2007) ffmpeg's need $video_bitrate
#** in bits/s, older (e.g. 0.4.8) need it in kbits/s.
my $video_bitrate_factor=1024;

# Get $audio_bitrate_factor and $video_bitrate_factor from ffmpeg's help
{ my($ffmpeg_pipe);
  die if !open($ffmpeg_pipe," ".fnq($ffmpeg_cmd)." 2>&1|");
  $audio_bitrate_factor=undef;
  $video_bitrate_factor=undef;
  my $line;
  while (defined($line=<$ffmpeg_pipe>)) {
    if ($line=~/^-b\s/) {
      # Dat: example: -b                 <int>   E.VA. set video bitrate (in bits/s)
      # Dat: example: -b bitrate          set video bitrate (in kbit/s)
      $video_bitrate_factor=($line=~m@\bin bits?/s@) ? 1024 : 1; # Imp: 1000 or 1024?
    } elsif ($line=~/^-ab\s/) {
      # Dat: example: -ab bitrate         set audio bitrate (in kbit/s)
      $audio_bitrate_factor=($line=~m@\bin bits?/s@) ? 1024 : 1; # Imp: 1000 or 1024?
    }
  }
  die "error: ffmpeg's help doesn't report video bitrate factor\n" if
    !defined $video_bitrate_factor;
  die "error: ffmpeg's help doesn't report audio bitrate factor\n" if
    !defined $audio_bitrate_factor;
}
print STDERR "info; ffmpeg video_bitrate_factor=$video_bitrate_factor audio_bitrate_factor=$audio_bitrate_factor\n";

my @ffmpeg_cmd=($ffmpeg_cmd,'-r',$ffmpeg_fps,'-s',"${framew}x${frameh}",
  #'-t',100, # Dat: .yuv file length is a natural boundary
  #'-i', 'ffmpeg_tmp.yuv',
  #'-aspect', '4:3', # Dat: no effect up here -- has to be applied later
  ($video_with eq 'mpeg2enc' ?
    ('-i', 'genmpeg_tmp.m2v') :
    ('-i', 'genmpeg_tmp.yuv') ),
  '-i', 'genmpeg_tmp.wav', # Dat: no need to -map
  '-target',$ffmpeg_target,
  ($video_with eq 'mpeg2enc' ? ('-vcodec', 'copy') : () ), # Dat: must be this late
  '-acodec',$ffmpeg_acodec,
  '-ab',$audio_bitrate*$audio_bitrate_factor,
  '-aspect', $aspect,
  # vvv SUXX: no effect on blue vanishing...
  '-b', $video_bitrate*$video_bitrate_factor,
  #'-qscale', '.1', # Doesn't increase quality
  #'-qmin', '.1',
  #'-qcomp', 1,
  # '-r', $ffmpeg_fps, # Dat: no need to specify again -- but would override input settings
  # Dat: doesn't help any more: '-qmin',30,'-qmax',30,
  '-y',$out_fn);

print STDERR "info: running: ".join('  ',map {fnq$_} @ffmpeg_cmd)."\n";
die "error: ffmpeg failed\n" if 0!=system @ffmpeg_cmd;
#DEBUG: system('mplayer',$out_fn);

# vvv Imp: option to remove, even on failure
unlink values(%genyuvfns), 'genmpeg_tmp.yuv', 'genmpeg_tmp.wav',
  'genmpeg_tmp.m2v';
print "info: created: $out_fn\n";
