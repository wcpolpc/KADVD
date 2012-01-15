#! /bin/sh
eval '(exit $?0)' && eval 'PERL_BADLANG=x;PATH="$PATH:.";export PERL_BADLANG\
 PATH;exec perl -x -S -- "$0" ${1+"$@"};#'if 0;eval 'setenv PERL_BADLANG x\
;setenv PATH "$PATH":.;exec perl -x -S -- "$0" $argv:q;#'.q
#!perl -w
+push@INC,'.';$0=~/(.*)/s;do(index($1,"/")<0?"./$1":$1);die$@if$@__END__+if 0
;#Don't touch/remove lines 1--7: http://www.inf.bme.hu/~pts/Magic.Perl.Header
#
# genspuxml.pl -- generate .mpeg and .xml files for spumux from LaTeX .aux
# by pts@fazekas.hu at Sat Feb  3 23:17:20 CET 2007
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
# Dat: see the Makefile for an example of running $0
# Dat: reads LaTeX's .aux output file as input
#
use integer;
use strict;

#** .tex job name and tempfile prefix
my $jobname;

select(STDERR); $|=1;
select(STDOUT); $|=1;

# --- Utilities

my %HSCQ=qw{< lt > gt & amp " quot};
sub hscq($) { # Dat: like PHP htmlspecialchars()
  my $S=$_[0];
  $S=~s@([<>&"])@&$HSCQ{$1};@g;
  $S
}

sub fnq($) {
  #return $_[0] if substr($_[0],0,1)ne'-'
  return $_[0] if $_[0]!~m@[^-_/.0-9a-zA-Z]@;
  my $S=$_[0];
  $S=~s@'@'\\''@g;
  "'$S'"
}

# --- read_image()

#** Can only parse simple PPM (`P6') uncompressed images
#** @param $_[0] filename
#** @return :HashRef image:
#**   { type=>'image', width=>..., height=>... data=>... }
sub read_image($) {
  my($fn)=@_;
  my $F;
  die "error: input image not found: $fn: $!\n" if !open $F, '<', $fn;
  my $head;
  read($F,$head,3);
  die "error: cannot read image header\n" if 3!=length($head);
  die "error: not a P6 PPM image\n" if $head!~/\AP6\s\Z(?!\n)/;
  # vvv Dat: start interpreting it as P6 PNM
  my @L;
  my $line; my $linepos;
  HEADLOOP: while (@L<3) {
    $line=<$F>;
    die "error: image header too short\n" if !defined $line;
    while ((@L==3 and $line=~m@\G(\s)|\#.*@gs) or
           (@L<3  and $line=~m@\G\s*(\d+)|\s*\#.*@gs)) {
      if (defined $1) {
        if (@L==3) { $linepos=pos($line); last HEADLOOP }
        push @L, $1;
      }
    }
  }
  die "error: 8-bit PPM expected\n" if $L[2] ne '255';
  my $img={
    type=>'image',
    format=>'RGB',
    ncomps=>3, # samples per pixel
    width=>$L[0]+0,
    height=>$L[1]+0,
    datasize=>undef,
    data=>substr($line,$linepos),
    fn=>$fn,
  };
  #die length($img->{data});
  $img->{datasize}=$img->{width}*$img->{height}*$img->{ncomps};
  die "error: image data too long\n"  if length($img->{data})>$img->{datasize};
  my $got=read($F, $img->{data}, $img->{datasize}+1-length($img->{data}), length($img->{data}));
  die "error: cannot read image data: $!\n" if !defined $got or $got<0;
  die if !close($F);
  die "error: image data too short\n" if length($img->{data})<$img->{datasize};
  die "error: image data too long\n"  if length($img->{data})>$img->{datasize};
  $img
}

#** @param $img :HashRef image
#** @return $img with $img->{norm} set to 'PAL', 'NTSC' or '?'
sub image_detect_norm($) {
  my($img)=@_;
  if ($img->{width}==720 and $img->{height}==576) { $img->{norm}='PAL' }
  elsif ($img->{width}==720 and $img->{height}==480) { $img->{nrm}='NTSC' }
  else { $img->{norm}='?' }
  $img
}

#** Autocrops a rectangular region from the image.
#** @param $img :HashRef image
#** @param $C3 :String of length 3, RGB color triplet to take as background
#** @return ($x0,$y0,$x1,$y1), where ($x0,$y0) is the upper left hand cornder
#**   inclusively, and ($x1,$y1) is the lower right hand cornder exclusively.
#**   See also `man 1 spumux'.
sub image_autocrop_detect($$) {
  my($img,$C3)=@_;
  my $x0=0;  my $y0=0;
  my $y1=$img->{height}; my $x1=$img->{width};
  die "error: bad C3 length\n" if 3!=length($C3);
  die "error: RGB image expected\n" if $img->{format} ne 'RGB';
  my $ht=$img->{height}; my $wd=$img->{width};
  my $wd3=$wd*3;
  my $bgline=$C3 x$wd;
  $y0++ while $y0<$y1 and substr($img->{data}, $y0    *$wd3, $wd3) eq $bgline;
  return (0,0,0,0) if $y0==$y1; # Dat: only background on image
  $y1-- while $y0<$y1 and substr($img->{data}, ($y1-1)*$wd3, $wd3) eq $bgline;
  while ($x0<$x1) {
    my $yi=$y0; my $ofs=$x0*3+$y0*$wd3;
    $yi++, $ofs+=$wd3 while $yi<$y1 and substr($img->{data}, $ofs, 3) eq $C3;
    last if $yi!=$y1; # break if found first non-autocroppable column on the left
    $x0++;
  }
  while ($x0<$x1) {
    my $yi=$y0; my $ofs=($x1-1)*3+$y0*$wd3;
    $yi++, $ofs+=$wd3 while $yi<$y1 and substr($img->{data}, $ofs, 3) eq $C3;
    last if $yi!=$y1; # break if found first non-autocroppable column on the left
    $x1--;
  }
  ($x0,$y0,$x1,$y1)
}

#** @param $imga :HashRef image to be modified in place
#** @param $imbg :HashRef image to be added to $imga
#** @param $C :String of length 3, RGB color triplet to take as background
#** @return $imga
sub image_addblit($$$) {
  my($imga,$imgb,$C3)=@_;
  die "error: bad C3 length\n" if 3!=length($C3);
  die "error: RGB target image expected\n" if $imga->{format} ne 'RGB';
  die "error: RGB image expected\n" if $imgb->{format} ne 'RGB';
  my $ht=$imga->{height}; my $wd=$imga->{width};
  die "error: image size mismatch for add\n" if
    $ht!=$imgb->{height} or $wd!=$imgb->{width};
  my $ds=$imga->{datasize};
  # vvv Imp: is there a faster operation in Perl? I don't think so.
  for (my $ofs=0; $ofs<$ds; $ofs+=3) {
    my $B3=substr($imgb->{data}, $ofs, 3);
    substr($imga->{data}, $ofs, 3)=$B3 if $B3 ne $C3;
  }
  $imga
}

sub image_create_rgb($$$) {
  my($width,$height,$C3)=@_;
  die "error: bad C3 length\n" if 3!=length($C3);
  return {
    type=>'image',
    format=>'RGB',
    ncomps=>3, # samples per pixel
    width=>$width,
    height=>$height,
    datasize=>$width*$height*3,
    data=>$C3 x($width*$height),
    fn=>undef,
  }
}

#** Writes the image as PPM P6, exactly the same way as pdftoppm(1) does.
#** @return $img
sub image_write_ppm_p6($$) {
  my($img,$fn)=@_;
  die if !defined $fn;
  my $D;
  die "error: cannot write image: $fn: $!\n" if !open($D, '>', $fn);
  $img->{writefn}=$fn;
  die if !open $D, '>', $fn;
  die if !print $D "P6\n$img->{width} $img->{height}\n255\n";
  die if !print $D $img->{data};
  die if !close $D;
  $img
}

#** @param $transparent_rgb :String (or undef), RGB color triplet e.g. "abcdef"
sub image_write_png($$;$) {
  my($img,$fn,$transparentrgb)=@_;
  die if !defined $fn;
  # Imp: clean up on signal etc.
  # Imp: better temporary file name
  my $tmpfn="$jobname.genspuxml_tmp.ppm";
  image_write_ppm_p6($img, $tmpfn);
  $img->{writefn}=$fn;
  # vvv Dat: optional dependency: sam2p (faster than convert)
  my @cmd=('sam2p','PNG:',
    (defined $transparentrgb ? ('-transparent', "#$transparentrgb") : ()),
    '--',$tmpfn,$fn);
  my $cmdq=join('  ', map { fnq$_ } @cmd);
  print STDERR "info: running converter: $cmdq\n";
  if (0!=system(@cmd)) {
    print STDERR "warning: sam2p failed (".sprintf("0x%x",$?)."), trying convert\n";
    @cmd=('convert','-depth',8,
      (defined $transparentrgb ? ('-transparent', "#$transparentrgb") : ()),
      "PPM:$tmpfn","PNG:$fn");
    $cmdq=join('  ', map { fnq$_ } @cmd);
    print STDERR "info: running converter: $cmdq\n";
    if (0!=system(@cmd)) { 
      unlink($tmpfn);
      die "error: image conversion failed (".sprintf("0x%x",$?).")\n"
    }
  }
  unlink($tmpfn);
  $img
}

# --- main()

$jobname=@ARGV ? $ARGV[-1] : 'dvdmenu';

#** Antialiased input PPM filename pattern.
my $antiappmfmt='%s.tantia-%06d.ppm';
my $sharpppmfmt='%s.tsharp-%06d.ppm';
my $spumenufmt='%s.menu-%06d-spu.xml';
my $highlightedfmt='%s.menu-%06d-hig.png';
my $selectedfmt='%s.menu-%06d-sel.png';
#** MPEG-2 menu video consisting of still pictures.
my $inpmpgfmt='%s.menu-%06d-inp.mpg';
#** The MPEG-2 menu video with subtitles (menu buttons) added.
#** Dat: change also in gendap.pl
my $spumpgfmt='%s.menu-%06d-spu.mpg';

my $AUX;
print STDERR "info: reading DVD menu .aux file: $jobname.aux\n";
die unless open $AUX, '<', "$jobname.aux";
my @menus;
my $nnmenus;
my $nnpages=0;
my @genmpeg_attrs;

sub buttons_add_selectedppms($) {
  my($buttons)=@_;
  my $nbuttons=@$buttons;
  for my $button (@$buttons) {
    my $pagenr=$button->{pagenr}+$nbuttons;
    $nnpages=$pagenr if $nnpages<$pagenr;
    $button->{selectedppm}=sprintf($sharpppmfmt,$jobname,$pagenr);
  }
}

while (<$AUX>) {
  if (/^% DVD starting menu (\d+); r=(\d+(?:[.]\d*)?|[.]\d+); g=(\d+(?:[.]\d*)?|[.]\d+); b=(\d+(?:[.]\d*)?|[.]\d+)\s*$/) {
    # Dat: example: % starting menu 1; r=0; g=0; b=.996
    no integer;
    buttons_add_selectedppms($menus[-1]{buttons}) if @menus;
    $nnpages++;
    push @menus, {
      type => 'menu',
      menunr => $1+0,
      pagenr => $nnpages,
      # vvv Imp: die if >1
      fakepagecolor => pack("C*", 255&(int(.5+255*$2)), 255&(int(.5+255*$3)), 255&(int(.5+255*$4))),
      buttons => [],
      backgroundppm => undef, # .ppm
      spumenufn => undef, # .xml, to be generated by us
      highlightedfn => undef, # .png, to be generated by us
      selectedfn => undef, # .png, to be generated by us
      inpmpgfn => undef, # .mpg, generated from backgroundppm repeated
      spumpgfn => undef, # .mpg, button masks added to spumpgfn
    };
    die "error: bad menu start number\n" if @menus!=$menus[-1]{menunr};
    # vvv Dat: must not prepend '#', spumux transparent=... doesn't like it
    $menus[-1]{fakepagergb}=unpack("H*", $menus[-1]{fakepagecolor});
    $menus[-1]{backgroundppm}=sprintf($antiappmfmt,$jobname,$menus[-1]{pagenr});
    $menus[-1]{spumenufn}=sprintf($spumenufmt,$jobname,$menus[-1]{menunr});
    $menus[-1]{highlightedfn}=sprintf($highlightedfmt,$jobname,$menus[-1]{menunr});
    $menus[-1]{selectedfn}=sprintf($selectedfmt,$jobname,$menus[-1]{menunr});
    $menus[-1]{inpmpgfn}=sprintf($inpmpgfmt,$jobname,$menus[-1]{menunr});
    $menus[-1]{spumpgfn}=sprintf($spumpgfmt,$jobname,$menus[-1]{menunr});
  } elsif (/^% DVD ((?:undeclared|missing) button in menu (\d+):\s*(?=\S)(.*\S))\s*?$/) {
    # Imp: command-line option to turn this into a warning (for debugging)
    # Dat: an undeclared button will not be typeset
    # Dat: a missing button will trigger an error later in genspuxml.pl
    #      (because of the empty autocrop result)
    die "error: $1\n";
  } elsif (/^% DVD button in menu (\d+):\s*(?=\S)(.*\S)\s*?$/) {
    # Dat: example: DVD button in menu 2: ccc
    die "error: button before menu\n" if !@menus;
    $nnpages++;
    my $button={
      type => 'button',
      buttonnr => 1+@{$menus[-1]{buttons}},
      menunr => $1+0,
      pagenr => $nnpages,
      name => $2,
      highlightedppm => undef,
      selectedppm => undef,
    };
    die "error: bad button menu number\n" if $button->{menunr}!=@menus;
    push @{$menus[-1]{buttons}}, $button;
    $button->{highlightedppm}=sprintf($sharpppmfmt,$jobname,$button->{pagenr});
    $button->{nameq}=hscq($button->{name});
  } elsif (/^% DVD number of menus: (\d+)\s*$/) {
    # Dat: example: % number of menus: 4
    die "error: multiple number of menus\n" if defined $nnmenus;
    $nnmenus=$1+0;
  } elsif (/^% DVD genmpeg attr:(.*)$/) {
    push @genmpeg_attrs, $1; # Dat: space at end is intentional
  }
}
die if !close($AUX);
buttons_add_selectedppms($menus[-1]{buttons}) if @menus;
die "error: no menus\n" if !@menus;
die "error: no menu count\n" if !defined $nnmenus;
die "error: bad menu count\n" if $nnmenus!=@menus;
print STDERR "info: $nnmenus menu(s)\n";
print STDERR "info: $nnpages page(s)\n";
die "error: too many (>$nnpages) tsharp pages generated\n" if stat(sprintf($sharpppmfmt,$jobname,$nnpages+1));
die "error: too many (>$nnpages) tantia pages generated\n" if stat(sprintf($antiappmfmt,$jobname,$nnpages+1));

my $norm;
for my $menu (@menus) {
  my $img=image_detect_norm(read_image($menu->{backgroundppm}));
  my $imgwd=$img->{width}; my $imght=$img->{height};
  print STDERR "info: menu nr=$menu->{menunr} backgroundppm=$menu->{backgroundppm} width=$img->{width} height=$img->{height} norm=$img->{norm}\n";
  die "error: bad norm\n" if $img->{norm} ne 'PAL' and $img->{norm} ne 'NTSC';
  if (!defined $norm) { $norm=$img->{norm} }
  elsif ($norm ne $img->{norm}) { die "error: norm changed\n" }
  my $hhimg;
  my $ssimg;
  for my $button (@{$menu->{buttons}}) {
    print STDERR "info:   button nrr=$button->{pagenr} name=$button->{name} highlightedppm=$button->{highlightedppm}\n";
    my $himg=image_detect_norm(read_image($button->{highlightedppm}));
    #if ($button->{highlightedppm} eq 'tsharp-000014.ppm') {
    #  die image_write_ppm6($img,'d.ppm');
    #}
    die "error: bad size for highlighted mask\n" if $himg->{width}!=$imgwd
      or $himg->{height}!=$imght;
    ($button->{x0},$button->{y0},$button->{x1},$button->{y1})=image_autocrop_detect($himg, $menu->{fakepagecolor});
    die "error: empty button highlighted mask (empty \\dvd...button{$button->{name}} in LaTeX?): $button->{name}\n" if
      $button->{y0}==$button->{y1};
    print STDERR "info:     highlighted x0=$button->{x0} y0=$button->{y0} x1=$button->{x1} y1=$button->{y1}\n";
    $hhimg=defined($hhimg) ?
       image_addblit($hhimg, $himg, $menu->{fakepagecolor}) : $himg;
    # ^^^ Dat: Perl reference counting is just good memory management here
    # Dat: now: generate the selected mask similarly as the highlighted mask
    my $simg=image_detect_norm(read_image($button->{selectedppm}));
    die "error: bad size for selected mask\n" if $himg->{width}!=$imgwd
      or $himg->{height}!=$imght;
    my ($sx0,$sy0,$sx1,$sy1)=image_autocrop_detect($simg, $menu->{fakepagecolor});
    die "error: empty button selected mask (empty \\dvd...button{$button->{name}} in LaTeX?): $button->{name}\n" if
      $button->{y0}==$button->{y1};
    print STDERR "info:     selected    x0=$sx0 y0=$sy0 x1=$sx1 y1=$sy1\n";
    $ssimg=defined($ssimg) ?
       image_addblit($ssimg, $simg, $menu->{fakepagecolor}) : $simg;
  }
  # vvv Dat: generate empty $hhimg for a menu without buttons
  $hhimg=image_create_rgb($imgwd, $imght, $menu->{fakepagecolor}) if !defined $hhimg;
  image_write_png($hhimg, $menu->{highlightedfn}); # Dat: doesn't seem to be needed:, $menu->{fakepagergb});
  $ssimg=image_create_rgb($imgwd, $imght, $menu->{fakepagecolor}) if !defined $ssimg;
  image_write_png($ssimg, $menu->{selectedfn}); # Dat: $menu->{fakepagergb} doesn't seem to be needed
}

die if !defined $norm;
#** Number of frames a menu consists of.
#** Does the standard want it to be at least 2 seconds?
#** Dat: NTSC is 30000/1001 frames per second
my $nmenuframes=($norm eq 'PAL' ? 50 : $norm eq 'NTSC' ? 60 : 60);

for my $menu (@menus) {
  my $SPUMENU;
  print STDERR "info: creating XML for spumux: $menu->{spumenufn}\n";
  die unless open $SPUMENU, '>', $menu->{spumenufn};
  die unless print $SPUMENU
qq(<subpictures>
 <stream>
  <spu transparent="$menu->{fakepagergb}" start="00:00:00.0" end="00:00:00.0" highlight=").hscq($menu->{highlightedfn}).qq(" select=").hscq($menu->{selectedfn}).qq(" force="yes" >\n);
  for my $button (@{$menu->{buttons}}) {
    die unless print $SPUMENU
qq(   <button name="$button->{nameq}" x0="$button->{x0}" y0="$button->{y0}" x1="$button->{x1}" y1="$button->{y1}" />\n);
  }
  die unless print $SPUMENU
qq(  </spu>
 </stream>
</subpictures>\n);
  die if !close($SPUMENU);
  my @cmd=('./genmpeg.pl',"--nframes=$nmenuframes","--mute",
    "--from-image=$menu->{backgroundppm}", "--outfile=$menu->{inpmpgfn}",
    @genmpeg_attrs); # Imp: make it possible to override all
  my $cmdq=join('  ', map { fnq$_ } @cmd);
  print STDERR "info: running MPEG-2 generator: $cmdq\n";
  if (0!=system(@cmd)) {
    unlink($menu->{inpmpgfn});
    die "error: MPEG-2 generation failed (".sprintf("0x%x",$?).")\n";
  }
  @cmd=('spumux',$menu->{spumenufn});
  $cmdq=join('  ', map { fnq$_ } @cmd).'  < '.fnq($menu->{inpmpgfn}).
    '  > '.fnq($menu->{spumpgfn});
  print STDERR "info: running SPU multiplexer: $cmdq\n";
  my $INP;
  die "error: cannot open source $menu->{inpmpgfn}\n" if
    !open($INP, '<', $menu->{inpmpgfn});
  my $SPU;
  die "error: cannot open target $menu->{spumpgfn}\n" if
    !open($SPU, '>', $menu->{spumpgfn});
  my $pid=fork();
  die "error: fork() failed: $!\n" if !defined $pid;
  if (!$pid) { # child
    die if !open STDIN,  '<&='.fileno($INP);
    die if !open STDOUT, '>&='.fileno($SPU);
    close($INP);
    close($SPU);
    die if !exec @cmd;
  }
  my $wgot=waitpid($pid,0);
  die "error: waitpid() failed (got $wgot): $!\n" if
     !defined $wgot or $wgot!=$pid;
  die "error: SPU multiplexer failed (".sprintf("0x%x",$?).")\n" if $?!=0;
  unlink($menu->{inpmpgfn});
}

print STDERR "info: all OK\n";

# genmpeg.pl --norm=pal --nframes=30 --solid=red --solid=green --outfile=menu.mpeg
# spumux menu.xml <menu.mpg >menuspu.mpg
