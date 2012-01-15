#! /bin/sh
eval '(exit $?0)' && eval 'PERL_BADLANG=x;PATH="$PATH:.";export PERL_BADLANG\
 PATH;exec perl -x -S -- "$0" ${1+"$@"};#'if 0;eval 'setenv PERL_BADLANG x\
;setenv PATH "$PATH":.;exec perl -x -S -- "$0" $argv:q;#'.q
#!perl -w
+push@INC,'.';$0=~/(.*)/s;do(index($1,"/")<0?"./$1":$1);die$@if$@__END__+if 0
;#Don't touch/remove lines 1--7: http://www.inf.bme.hu/~pts/Magic.Perl.Header
#
# gendap.pl -- generate dvdauthor XML project (etc.) from dvdmenuauthor XML
# by pts@fazekas.hu at Mon Feb  5 19:33:16 CET 2007
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
# Dat: we use a fault-tolerant and encoding-agnostic XML parser
# Imp: ($.) is useless, since we were counting `>' chars
# !! \begin{dvdmenupage}{a,bb}
# !! are we correct when we process empty tags (i.e. will empty tags
#    remain empty?)
#
use integer;
use strict;

select(STDERR); $|=1;
select(STDOUT); $|=1;

# --- Utilities
#
# Dat: the TeX is_* validation functions work with the default LaTeX \catcode
#      setup

my $tex_unsafe_token_re=qr{[^-a-zA-Z0-9\@\$&*()\[\]_+=|,<>/]};
sub is_safe_tex_tokens($) {
  my $S=$_[0];
  # Dat: these are \active with magyar.ldf and french.ldf: . ? ! ; :
  # Dat: caret (^) is not safe because of ^^M notation
  # Dat: space is not safe because TeX compresses multiple spaces to a single one
  return $S!~m{$tex_unsafe_token_re};
}

my $tex_unwritable_token_re=qr{[^-a-zA-Z0-9\@\$&*()\[\]_+=|,<>/.?!;:\^ ~]};
#** @return true if the specified string is safe to put to the bofy of \def
#**   alone (i.e. not surrounded by spaces) and it will be kept intact by TeX
#**   when writing its \meaning to a file.
#**   Contains some expandable constructs (such as `~' and `.' (\active in
#**   magyar.ldf and frenchb.ldf).
#**   Doesn't contain baclaslash because \meaning\foo inserts extra space
sub is_writable_tex_body($) {
  my $S=$_[0];
  # Dat: these are \active with magyar.ldf and french.ldf: . ? ! ; :
  # Dat: double caret (^^) is not safe because of ^^M notation
  # Dat: double space is not safe because TeX compresses multiple spaces to a
  #      single one
  return $S!~m{$tex_unwritable_token_re} and $S!~m@  |\^\^@;
}

#** @return '' if the specified string is safe to put to the bofy of \def
#**   alone (i.e. not surrounded by spaces) and it will be kept intact by TeX,
#**   an error message otherwise
sub bad_balanced_tex_string($) {
  my($S)=@_;
  my $depth=0;
  while ($S=~m@\G(?:
   [^{}\%\\]+ |
   ({) | # $1
   (}) | # $2
   \%(?:.*)\n\s* | # Dat: must contain the trailing \n
   (\%) |
   \\[^a-zA-Z\@] |
   \\[a-zA-Z\@]+\s* |
   (\\) |
   (.))@xgs) {
    if (defined $1) { # open brace
      $depth++
    } elsif (defined $2) { # close brace
      return 'too many braces closed' if 0==$depth--;
    } elsif (defined $3) {
      return 'incomplete comment'
    } elsif (defined $4) {
      return 'incomplete control sequence'
    } elsif (defined $5) {
      return 'syntax error' # Dat: should never happen
    }
  }
  return "braces left open: $depth" if 0!=$depth;
}

#** Suitable for unquoted control sequence name
sub is_safe_tex_csname($) {
  my($S)=@_;
  return length($S)>0 && $S!~m{[^a-zA-Z]};
}

#** Suitable for button name etc.
sub is_safe_tex_name($) {
  my($S)=@_;
  return length($S)>0 && $S!~m{[^-a-zA-Z0-9_/]};
}

#** Converts an encoding (charset) name to canonical form.
sub canonical_encoding($) {
  my $S=uc($_[0]);
  #$S=uc("latin8");
  $S=~s@\AUTF(?!-)@UTF-@;
  $S=~s@\A(?:ISO-?)?LATIN-?@ISO-8859-@;
  $S=~s@\A(?:ISO-?)?8859-?@ISO-8859-@;
  $S
}

# --- Dumb and permissive XML parser

#** @param $H :HashRef of XML attrs
#** @param $attrstr :String, must start with whitespace (or be empty)
sub add_xml_attrs($$) {
  my($H,$attrstr)=@_;
  pos($attrstr)=0;
  while (1) {
    die "error: bad attrs syntax: $attrstr\n" if
      $attrstr!~m@\G(?:\s+ ([a-zA-Z][-:\w]*) = (?: "([^"]*)" | \x27([^\x27]*)\x27 ) | \s*\Z(?!\n)  )@gxs;
    last if !defined $1;
    die "error: multiple attr\n" if exists $H->{$1};
    $H->{$1}=defined($2) ? $2 : $3; # Dat: do not unquote &quot; etc.
  }
}

#** This is a simplified, non-validating, permissive XML parsers, enough to
#** parse dvdauthor and dvdmenuauthor project files.
#** Dat: CDATA and PCDATA are not supported...
#** Dat: doesn't accept <foo bar="val>ue">
#** Dat: tag nesting etc. is checked by process_xml()
#** Dat: if there is a newline after a comment (with possibly spaces and
#**      tabs in between), these are available as $item->{after_comment},
#**      and these won't be parsed again as type eq 'text'
#** @param $process_one :CodeRef, will be called as
#**   $process_one->($stack,$item),
#**   where defined $item->{type} and defined $item->{src} (and possibly
#**   other keys, depending of the item type)
#**   Dat: concatenation of $item->{src}s should yield the input XML file
#** @param $io is an IO reference to be read
#** @example: process_xml(\*STDIN, sub {
#**   my($stack,$item)=@_;
#**   my $type=$item->{type};
#**   print $item->{src};
#**   if ($type eq 'open') { push @$stack, $item }
#**   elsif ($type eq 'close') { pop @$stack }
#** });
sub process_xml($$) {
  my($io,$process_one)=@_;
  binmode($io);
  #** Initial 'root' tag is a sentinel to avoid @$stack>0 checks.
  #** Contains only type=>'root' and type=>'open'.
  my $stack=[{type=>'root', src=>'', tag=>''}];
  my $orig=$_;
  my $oldisep=$/;
  local $/=">";
  my $src;
  my $need_end_p=0;
  while (1) {
    $/=">"; # Dat: all XML special constructs tags end by `>', so `>' will be our line terminator
    last if !defined($src=<$io>);
    $/=$oldisep;
   REDO_SRC:
    if ($src=~s@\A([^<]+)@@s) {
      my $text=$1;
      die "error: text after final close tag\n" if $need_end_p and $text=~/\S/;
      die "error: text before first open tag\n" if 1==@$stack and $text=~/\S/;
      $process_one->($stack, { type=>'text', src=>$text });
    }
    #print STDERR "[$src]\n";
    if ($src=~m@\A <!--(.*) @xs) {
      my $commentdata=$1;
      while (substr($commentdata,-3) ne '-->') {
        $/=">";
        if (!defined($src=<$io>)) {
          $/=$oldisep;
          my $S=$commentdata; $S=~s@[\r\n]@ @g;
          die "error: comment too short: <!--$S\n";
        }
        $/=$oldisep;
        $commentdata.=$src;
      }
      substr($commentdata,-3)=""; # Dat: remove -->
      #print STDERR "COMMENT($commentdata)\n";
      my $oldsrc=$src;
      # vvv Dat: scanning for \n after comment
      my $after_comment="";
      # vvv Dat: bed idea, doesn't kill indenting spaces before comment
      #$/=">";
      #last if !defined($src=<$io>);
      #$/=$oldisep;
      #$after_comment=$1 if $src=~s@\A ([\ \t]*\r?\n) @@sx;
      $process_one->($stack, { type=>'comment', src=>$oldsrc.$after_comment,
        commentdata=>$commentdata, after_comment=>$after_comment } );
      #goto REDO_SRC; # Imp: what if $need_end_p?
    } elsif ($src=~m@\A <[?](.*?)[?]> @xs) {
      # Imp: scan for ?>, not > in $/
      my $pidata=$1;
      my $item={ type=>'procinst', src=>$src, pidata=>$1 };
      if ($pidata=~m@\A(xml(?=\s))@) {
        $item->{subtype}='xml';
        my %H;  add_xml_attrs(\%H, substr($pidata,length($1)));
        $item->{attrs}=\%H;
      }
      $process_one->($stack, $item);
#    } elsif ($src=~m@\A <!(.*?)> @xs) { # Dat: XML processing instruction
#      my $badata=$1;
#      if (substr($badata,0,2)eq'--') {
#        my $S=$badata; $S=~s@[\r\n]@ @g;
#        die "error: bad comment syntax: <!$S>\n"
#      }
#      $process_one->($stack, { type=>'bang', src=>$src, badata=>$badata });
    } elsif ($src=~m@\A <(/?[a-zA-Z](?:[^>"\x27]+|"[^"]*"|\x27[^\x27]\x27)+)> @xs) {
      my $tagw=$1;
      #print STDERR "TAGW($tagw)\n";
      if (substr($tagw,0,1)eq"/") {
        $need_end_p=1 if 2==@$stack;
        my $tag=substr($tagw,1);
        die "error: bad nesting: wanted </$tag>, but no tags to close\n" if 2>@$stack;
        die "error: bad nesting: wanted </$tag>, have tag $stack->[-1]{tag} open\n" if $stack->[-1]{tag} ne $tag;
        $process_one->($stack, { type=>'close', src=>$src, tag=>$tag });
        # ^^^ Dat: should call pop(@$stack)
      } else {
        my $closer=$tagw=~s@/\Z(?!\n)@@ ? "/" : "";
        die "error: bad tag name syntax\n" if $tagw!~s@\A([a-zA-Z][-:\w]*)@@;
        my %H;
        my $tag=$1;
        my $item={ type=>'open', src=>$src,
          tag=>$tag, attrs=>\%H, xtra=>undef };
        add_xml_attrs(\%H, $tagw);
        $process_one->($stack, $item);
        # ^^^ Dat: should call push(@$stack, $item)
        if ($closer) {
          $need_end_p=1 if 2==@$stack;
          $process_one->($stack, { type=>'close', src=>'', tag=>$tag });
          # ^^^ Dat: should call pop(@$stack)
        }
      }
    } elsif ($src=~m@\A (<.*?>) @xs) {
      my $S=$1; $S=~s@[\r\n]@ @g;
      die "error: unexpected tag-like construct: $S\n";
    }
  }
  die "error: tags left open\n" if 1!=@$stack;
  die "error: no main tag in XML\n" if !$need_end_p;
}

#** :String or undef. XML encoding normalized. Default undef means UTF-8
#** (as interpreted by dvdauthor).
my $xml_encoding;
sub xml_chr($) {
  my $code;
  die if !defined $code or $code<0;
  # Imp: return pack("U",$code)
  return chr($code) if $code<128; # Dat: ASCII
  require Encode;
  return Encode::encode(($xml_encoding or 'UTF-8'), chr($code))
}

my %HENT=qw(lt < gt > amp & quot " apos '); # "
sub htmldecode($) {
  my $S=$_[0];
  die if !defined $S;
  $S=~s@&(lt|gt|amp|quot|apos);|&#[xX]([0-9a-fA-F]+);|&#(\d+);@
    defined $1 ? $HENT{$1} : defined $2 ? xml_chr(hex($2)) : xml_chr($3&255) @ge;
  $S
}


#** @return $_[1] with entities decoded, indentation removed
sub xml_strip_text_block($) {
  my $S=htmldecode($_[0]);
  die if !defined $S;
  $S=~s@\s*\Z(?!\n)@@; # Dat: remove newline at the end (needed my $minwslen)
  $S=~s@\A([\ \t]*\r?\n)+@@; # Dat: remove heading whitespace (terminated by newline)
  pos($S)=0;
  # vvv !! distinguish tabs and spaces (like Python strict indent)
  if ($S=~/\A([\ \t]+)/g) {
    my $minwslen=length($1);
    while ($S=~/\n(?:\r?\n)*([\ \t]*)/g) {
      $minwslen=length($1) if $minwslen>length($1);
    }
    if ($minwslen>0) { # Dat: remove $minwslen spaces from the beginning of all lines
      my $re=qr{^[\ \t]{$minwslen}}m;
      $S=~s@$re@@g; # Imp: faster?
    }
  }
  $S.="\n" if 0!=length($S);
  $S
}

my %HSCQ=qw{< lt > gt & amp " quot};
sub hscq($) { # Dat: like PHP htmlspecialchars()
  my $S=$_[0];
  $S=~s@([<>&"])@&$HSCQ{$1};@g;
  $S
}

#** @param $S :String. An XML full tag, example: `<foo bar="42"' or `<foo />'
#** @param $new_attrs contains the attributes already quoted (hscq())
sub xml_rebuild_tag($$$) {
  my($S,$new_tagname,$new_attrs)=@_;
  if (defined $new_tagname) {
    die if $S!~s@\A<[^>\s]+@<$new_tagname@;
  }
  if (defined $new_attrs) {
    die if 'HASH' ne ref $new_attrs;
    my $closer=substr($S,-2) eq "/>" ? "/>" : ">";
    die if $S!~s@\A(<[^>\s]+).*@$1@s;
    for my $K (sort keys %$new_attrs) { $S.=qq( $K="$new_attrs->{$K}") };
    $S.=$closer;
  }
  $S
}
# --- main()

die "Usage: $0 <project.dmp.xml>\n" if @ARGV!=1;
my $projectfn=$ARGV[0];
$projectfn=~s@\A(?:[.]/)+@@; # Dat: Unix-specific
my $jobname=$projectfn;
$jobname=~s@\A(.*[/\\])@@s; # Dat: Unix- and Win32-specific
#my $jobdir=$1; # Dat: latex(1) ignores $jobdir when writing files, so do we
$jobname=~s@(?:[.]dmp)[.][^/\\]+\Z(?!\n)@@;
#** XML file for dvdauthor
my $daxmlfn="$jobname.xml";
my $texoutfn="$jobname.tex";
die "error: input and output XML are the same: $daxmlfn\n" if
  $daxmlfn eq $projectfn;
print STDERR "info: reading dvdmenuauthor project XML: $projectfn\n";
my $infd;
die "error: cannot open: $projectfn: $!\n" if !open($infd, '<', $projectfn);
print STDERR "info: creating dvdauthor project XML: $daxmlfn\n";
my $daout;
die "error: cannot create: $projectfn: $!\n" if !open($daout, '>', $daxmlfn);
print STDERR "info: creating LaTeX menu source: $texoutfn\n";
my $texout;
{ my $oldsel=select($texout); $|=1; select($oldsel); }
die "error: cannot create: $projectfn: $!\n" if !open($texout, '>', $texoutfn);

#** :String or undef. XML encoding normalized. Default undef means UTF-8
#** (as interpreted by dvdauthor).
my $tex_header_default=
q(\documentclass{article}
\usepackage{dvdmenu}
\autodetectXinputenc
);
my $tex_header;
my $tex_footer_default=q(\end{document});
my $tex_footer;
my $tex_header_emitted_p=0;

#** The MPEG-2 menu video with subtitles (menu buttons) added.
#** Dat: change also in genspuxml.pl
my $spumpgfmt='%s.menu-%06d-spu.mpg';

my $ntexmenus=0;

my %encoding_to_tex_map=( # Imp: more, configurable
  'UTF-8'=>'utf8',
  'ISO-8859-1'=>'latin1',
  'ISO-8859-2'=>'latin2',
  'ISO-8859-3'=>'latin3',
  'ISO-8859-4'=>'latin4',
  'ISO-8859-5'=>'latin5',
  'ISO-8859-9'=>'latin9',
);

my %genmpeg_attrs;

sub emit_tex_header() {
  die "error: emitting tex header multiple times\n" if $tex_header_emitted_p;
  $tex_header_emitted_p=1;
  my $genheadstr="% This is a LaTeX dvd menu design document autogenerated by dvdmenuauthor\n%    from $projectfn at ".
        scalar(localtime)."\n";
  my $iencstr=q(\def\autoloadXinputenc{})."\n";
  if (defined $xml_encoding) {
    if (defined $encoding_to_tex_map{$xml_encoding}) {
      $iencstr=qq(\\def\\autoloadXinputenc{\\usepackage[$encoding_to_tex_map{$xml_encoding}]{inputenc}})."\n";
    } else {
      die "warning: cannot convert XML encoding to tex: $xml_encoding\n";
    }
    # Dat: ucs.sty is loaded by \usepackage[utf8]{inputenc}
    # Imp: try to convert to latin1 or latin2 in Perl as a fallback
  }
  my $genmpegattrsstr='';
  if (%genmpeg_attrs) {
    # vvv Dat: it is safe to write with \meaning, becase there are no
    #     backslashes, so `\foo+bar' won't be converted to `\foo +bar'
    $genmpegattrsstr=q(
\begingroup\catcode\string`@11
\global\def\write@genmpegattr#1{%
  \def\reserved@a{#1}%
  \immediate\write\@auxout{\expandafter\@gobble\string\%
    DVD genmpeg attr:\expandafter\strip@prefix\meaning\reserved@a}%
}%
);
    for my $key (sort keys%genmpeg_attrs) {
      my $S="--$key=$genmpeg_attrs{$key}";
      die "error: genmpeg attr not a writable TeX string: $S\n" if
        !is_writable_tex_body($S);
      $genmpegattrsstr.=q(\AtBeginDocument{\write@genmpegattr{).
        "$S\}\}%\n";
    }
    $genmpegattrsstr.=q(\endgroup
);
  }
  my $pre=$genheadstr.$iencstr.$genmpegattrsstr.
    (defined $tex_header ? $tex_header : $tex_header_default);
  $pre=~s@\\begin\s*\{document\}\s*\Z(?!\n)@@;
  $pre=~s@\A\s+@@;
  $pre=~s@\s+\Z(?!\n)@@;
  $pre.="\n\n\\begin{document}\n\n";
  die if !print($texout $pre);
}

sub emit_tex_footer() {
  my $post=defined $tex_footer ? $tex_footer : $tex_footer_default;
  $post=~s@\s+\Z(?!\n)@@;
  $post=~s@\A\s+@\n\n@;
  $post.="\n" if substr($post,-1) ne "\n";
  die if !print($texout $post);
}  


process_xml($infd, sub {
  my($stack,$item)=@_;
  my $type=$item->{type};
  my $attrs=$item->{attrs};
  my $dump_p=1;
  #print "($item->{type}:$item->{src})\n";
  if (@$stack==1) {
    if ($type eq 'procinst') {
      if (defined $attrs and defined $attrs->{encoding}) {
        $xml_encoding=canonical_encoding($attrs->{encoding});
      }
    } elsif ($type eq 'open') {
      die "error: main tag is not dvdmenuauthor, but: $item->{tag}\n" if
        $item->{tag} ne 'dvdmenuauthor';
      die if $item->{src}!~s@\A<[^>\s]+@<dvdauthor@;
      # vvv Imp: what if $projectfn is not proper UTF-8?
      die if !print($daout "<!-- This is a dvdauthor project XML file autogenerated by dvdmenuauthor\n     from $projectfn at ".
        scalar(localtime)." -->\n");
      my $need_rebuild_p=0;
      for my $key (sort keys %$attrs) { # Imp: keep original order, keep original multiplicity
        if ($key=~m@\Agenmpeg:(.+)@s) {
          $need_rebuild_p=1;
          $genmpeg_attrs{$1}=$attrs->{$key};
          delete $attrs->{$key};
        }
      }
      $item->{src}=xml_rebuild_tag($item->{src}, undef, $item->{attrs}) if
        $need_rebuild_p;
    } elsif ($type eq 'comment') {
      # Dat: remove initial comments
      $dump_p=0;
    }
  } elsif (@$stack==2 and $type eq 'close') {
    $item->{src}="</dvdauthor>"; # Dat: override </dvdmenuauthor>
  } elsif ($stack->[-1]{tag}=~/:/) {
    if ($type eq 'comment') {
      $dump_p=0;
    } elsif ($type eq 'close') { # Dat: since the XML is well formed, we are parsing the _right_ tag
      if ($item->{tag} eq 'tex:header') {
        # vvv Dat: upgrades !defined($tex_header) without a warning. Good.
        $tex_header.=xml_strip_text_block($stack->[-1]{xtra}{tex_header})."\n";
      } elsif ($item->{tag} eq 'tex:footer') {
        $tex_footer.=xml_strip_text_block($stack->[-1]{xtra}{tex_footer})."\n";
      } elsif ($item->{tag} eq 'tex:page') {
        $stack->[-2]{xtra}{tex_page_full}.=
          xml_strip_text_block($stack->[-1]{xtra}{tex_page})."\n";
      } elsif ($item->{tag} eq 'tex:prepage') {
        $stack->[-2]{xtra}{tex_prepage_full}.=
          xml_strip_text_block($stack->[-1]{xtra}{tex_prepage})."\n";
      }
      $dump_p=0;
    } elsif ($type ne 'text') {
      die "error: expected tag, got $type inside tag $stack->[-1]{tag}\n";
    } elsif ($stack->[-1]{tag} eq 'tex:page') {
      $stack->[-1]{xtra}{tex_page}.=$item->{src};
    } elsif ($stack->[-1]{tag} eq 'tex:prepage') {
      $stack->[-1]{xtra}{tex_prepage}.=$item->{src};
    } elsif ($stack->[-1]{tag} eq 'tex:header') {
      # Dat: don't strip, just append se far (because of XML comments in-between)
      $stack->[-1]{xtra}{tex_header}.=$item->{src};
    } elsif ($stack->[-1]{tag} eq 'tex:footer') {
      $stack->[-1]{xtra}{tex_footer}.=$item->{src};
    } else { die "error: unexpected text in tag: $stack->[-1]{tag}\n" }
    $dump_p=0;
  } elsif ($type eq 'open') {
    if ($item->{tag} eq 'tex:page' and $stack->[-1]{tag} eq 'pgc') {
      die "error: <$item->{tag} too late here (after <vob tex:file=)\n" if
        $stack->[-1]{xtra}{had_tex_file_p}; # Dat: brings {xtra} to existence. Never mind.
      $stack->[-1]{xtra}{tex_page}="";
      $dump_p=0;
    } elsif ($item->{tag} eq 'tex:prepage' and $stack->[-1]{tag} eq 'pgc') {
      die "error: <$item->{tag} too late here (after <vob tex:file=)\n" if
        $stack->[-1]{xtra}{had_tex_file_p}; # Dat: brings {xtra} to existence. Never mind.
      $stack->[-1]{xtra}{tex_prepage}="";
      $dump_p=0;
    } elsif ($item->{tag} eq 'tex:header' and @$stack==2) { # Dat: and $stack->[-1]{tag} eq 'dvdauthor'
      die "error: <$item->{tag} too late here\n" if $tex_header_emitted_p;
      $stack->[-1]{xtra}{tex_header}="";
      $dump_p=0;
    } elsif ($item->{tag} eq 'tex:footer' and @$stack==2) { # Dat: and $stack->[-1]{tag} eq 'dvdauthor'
      $stack->[-1]{xtra}{tex_footer}="";
      $dump_p=0;
    } elsif ($item->{tag} eq 'button' and $stack->[-1]{tag} eq 'pgc') {
      if (exists $item->{attrs}{name}) {
        # vvv Dat: magically brings arrayref to existence. Good.
        my $buttonname=$item->{attrs}{name};
        die "error: duplicate button in menu: $buttonname\n" if
          exists $stack->[-1]{xtra}{buttons}{$buttonname};
        die "error: TeX-unsafe characters in button name: $buttonname\n" if
          !is_safe_tex_name($buttonname);
        push @{$stack->[-1]{xtra}{button_names}}, $buttonname;
        $stack->[-1]{xtra}{buttons}{$buttonname}=1;
        my $S="";
        for my $key (sort keys %$attrs) { # Imp: keep original order, keep original multiplicity
          if ($key=~m@\Atex:(.+)@s) { # Imp: all, not only `tex:*' and `name' -- but others might not be balanced
            my $key1=$1;
            die "error: <button name=\"$buttonname\" $key= key is not token-safe for TeX: $S\n" if
              !is_safe_tex_tokens($key1);
            my $badb=bad_balanced_tex_string($attrs->{$key});
            die "error: <button name=\"$buttonname\" $key= value: $badb\n" if $badb;
            # vvv Dat: we are not calling xml_strip_text_block deliberately here
            if (is_safe_tex_csname($key1)) {
              $S.=q(  \def\dvdbuttonattrX).$key1.q({).$attrs->{$key}.qq(}\n);
            } else {
              $S.=q(  \csname @namedef\endcsname{dvdbuttonattrX).$key1.q(}{).$attrs->{$key}.qq(}\n);
            }
            delete $attrs->{$key};
          }
        }
        if (0!=length($S)) {
          $item->{src}=xml_rebuild_tag($item->{src}, undef, $item->{attrs});
          substr($S,0,0)=q(\begingroup\def\dvdbuttonattrXname{).$buttonname.qq(}\n);
          $S.=q(\dvdprocessbutton\endgroup)."\n\n";
          $stack->[-1]{xtra}{button_process_texsrc}.=$S; # Dat: silently brings it to existence
          #die $S;
        }
        #print STDERR "$item->{attrs}{name}\n";
      } else { print STDERR "warning: <button without name=\n" }
    } elsif ($item->{tag} eq 'vob' and $stack->[-1]{tag} eq 'pgc' and exists $item->{attrs}{'tex:file'}) {
      die "error: expected empty <$item->{tag} tex:file=\"\"\n" if
        0!=length($item->{attrs}{'tex:file'});
      die "error: <$item->{tag} tex:file= too early here (need <tex:page> first)\n" if
        !defined $stack->[-1]{xtra}{tex_page_full} and
        !defined $stack->[-1]{xtra}{tex_prepage_full};
      die "error: both <$item->{tag} tex:file= and file=\n" if
        exists $item->{attrs}{file};
      delete $item->{attrs}{'tex:file'};
      $item->{attrs}{file}=hscq(sprintf($spumpgfmt,$jobname,++$ntexmenus));
      $item->{src}=xml_rebuild_tag($item->{src}, undef, $item->{attrs});
      #die $item->{src};
      $stack->[-1]{xtra}{had_tex_file_p}=1;
    } elsif ($item->{tag}=~/:/) {
      die "error: bad tag with namespace here: $item->{tag}\n";
    }
  } elsif ($type eq 'close' and $item->{tag} eq 'pgc') {
    if (defined($stack->[-1]{xtra}{tex_page_full}) or
        defined($stack->[-1]{xtra}{button_process_texsrc}) or
        defined($stack->[-1]{xtra}{tex_prepage_full})) {
      die "error: tex page without corresponding <vob tex:file=\n" if
         !$stack->[-1]{xtra}{had_tex_file_p};
      my $S="";
      $S.=$stack->[-1]{xtra}{tex_prepage_full} if defined $stack->[-1]{xtra}{tex_prepage_full};
      $S.=$stack->[-1]{xtra}{button_process_texsrc} if defined $stack->[-1]{xtra}{button_process_texsrc};
      $S.=$stack->[-1]{xtra}{tex_page_full} if defined $stack->[-1]{xtra}{tex_page_full};
      emit_tex_header() if !$tex_header_emitted_p;
      my $buttons=join(',',
        defined $stack->[-1]{xtra}{button_names} ?
        @{$stack->[-1]{xtra}{button_names}} : ());
      substr($S,0,0)="\\begin{dvdmenupage}{$buttons}% LaTeX-generated menu $ntexmenus\n";
      substr($S,-1)="\\end{dvdmenupage}\n\n"; # Dat: remove trailing newline
      die if !print($texout $S);
      # Dat: debug: print STDERR $stack->[-1]{xtra}{tex_page_full};
    }
  }
  if ($type eq 'open') {
    for my $key (sort keys %{$item->{attrs}}) {
      die "error: unknown attr with namespace: <$item->{tag} $key=\n" if
        $key=~/:/;
    }
  }
  die if $dump_p and !print($daout $item->{src});
   
  if ($type eq 'open') { push @$stack, $item }
  elsif ($type eq 'close') { pop @$stack }
});

emit_tex_footer() if $tex_header_emitted_p;
die if !close($texout);
if (!$tex_header_emitted_p) {
  print STDERR "warning: no menus to typeset by LaTeX\n";
  unlink $texoutfn;
}
die if !close($daout);
die if !close($infd);

my $ntexmenuss=($ntexmenus==1) ? "" : "s";
print STDERR "info: project has $ntexmenus LaTeX menu$ntexmenuss\n";
print STDERR "info: dvdauthor project generated OK.\n";
