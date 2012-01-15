#! /bin/bash --
#
# dvdmenutest.sh -- generate and preview DVD menus (with dummy titles)
# by pts@fazekas.hu at Sun Jul 16 17:23:16 CEST 2006
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
# Dat: genmenutest.sh creates a video DVD from a dvdauthor .xml file, but
#      replacing all titles with a dummy short (4 seconds long) title, and
#      keeping the menus
# Dat: doesn't replace intro (<dvdauthor/vmgm/menus/pgc/vob)
#

if [ "$#" = 0 ] || [ "$1" = --help ]; then
  echo "Usage: $0 {--preview|--dvddir|--iso|...} [dvdauthor.xml]"
  exit 1
fi

if [ "$1" == --preview ]; then
  GOAL=preview
elif [ "$1" == --iso-preview ]; then
  GOAL=iso-preview
elif [ "$1" == --dvddir ]; then
  GOAL=dvddir
elif [ "$1" == --iso ]; then
  GOAL=iso
else
  echo "$0: please specify a goal in \$1" >&2
  exit 2
fi

# vvv .xml file for dvdauthor
DXML="${2:-dvdauthor.xml}"
#export PATH=".:$PATH"

#** Static frame colors for the titles
#** Dat: no black and white
SOLIDCOLORS='red green blue yellow cyan purple'
SOLIDFRAMES=200

xinehelp() {
  echo 'Press Alt-<E> in xine to get the DVD navigation menu window.'
  echo 'Also use the numpad with numlock is off for DVD navigation.'
  echo 'Running xine to preview the DVD...'
}

set -ex

test -d genmenutest.viddvd || mkdir genmenutest.viddvd
test -d genmenutest.viddvd

# vvv Imp: don't generate more thant the title count
for COLOR in $SOLIDCOLORS; do
  if test -f genmenutest.viddvd/solidtitle."$COLOR".mpeg; then :; else
    MPEGZ="`gendvdauthorproject.pl --find-resource=design/solidtitle."$COLOR".mpeg.gz || true`"
    if test -f "$MPEGZ"; then
      gzip -cd <"$MPEGZ" >genmenutest.viddvd/solidtitle."$COLOR".mpeg
    else
      `perl genmpeg.pl --nframes="$SOLIDFRAMES" --solid="$COLOR" --outfile=genmenutest.viddvd/solidtitle."$COLOR".mpeg`
    fi
  fi
  test -f genmenutest.viddvd/solidtitle."$COLOR".mpeg
done

export SOLIDCOLORS
<"$DXML" >genmenutest.viddvd/genmenutest.xml perl -0777 -w -pe'
  use integer; use strict;
  my $inmenus_p=0;
  my @SOLIDCOLORS=split" ",$ENV{SOLIDCOLORS};
  my $solidcolor=0;
  sub get_next_solidcolor() {
    $SOLIDCOLORS[($solidcolor=$solidcolor+1)%@SOLIDCOLORS]
  }
  s`(<(/?)menus(?=[>\s])|<dvdauthor(?=[>\s])([^>]+)>|<vob\s+file="([^"]*)")`
    if (defined $2) { $inmenus_p+=(length($2)==0 ? 1 : -1); $1 }
    elsif (defined $3) { my $attrs=$3; $attrs=~s@\sdest="[^"]*"@@g;
       "<dvdauthor dest=\"genmenutest.viddvd\" $attrs>"
    } elsif (!$inmenus_p) { "<vob file=\"genmenutest.viddvd/solidtitle.".
      get_next_solidcolor().".mpeg\"" } # Imp: quote?
    else { $1 }
  `ge;
'

rm -rf genmenutest.viddvd/VIDEO_TS genmenutest.viddvd/AUDIO_TS
dvdauthor -x genmenutest.viddvd/genmenutest.xml

if [ "$GOAL" = dvddir ]; then
  :
elif [ "$GOAL" = preview ]; then
  set +x; echo ''; xinehelp; echo ''; set -x
  xine dvd:"`pwd`"/genmenutest.viddvd
elif [ "$GOAL" = closed ]; then
  :
  # dvdauthor -T                 -o genmenutest.viddvd  # Dat: this makes it _not_ work in xine...
elif [ "$GOAL" = iso ]; then
  mkisofs -dvd-video -v -o genmenutest.iso genmenutest.viddvd
elif [ "$GOAL" = iso-preview ]; then
  mkisofs -dvd-video -v -o genmenutest.iso genmenutest.viddvd
  set +x; echo ''; xinehelp; echo ''; set -x
  xine dvd:"`pwd`"/genmenutest.iso
else
  echo "$0: bad goal: $GOAL" >&2
  exit 3
fi
