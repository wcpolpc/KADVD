#
# sample Makefile (Makefile.ex) for dvdmenuathor
# by pts@fazekas.hu at Mon Feb  5 21:09:57 CET 2007
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

VERSION=0.02
PRODUCT=dvdmenuauthor-$(VERSION)

DFF_PL=$(shell type -p dff.pl >/dev/null && echo dff.pl)

.PHONY: all productstring

.PHONY: all generate-latex compile-pdflatex generate-ppm generate-spuxml author-dvd play
all: generate-latex compile-pdflatex generate-ppm generate-spuxml author-dvd;

productstring:
	@echo '$(PRODUCT)'

generate-latex:
	./gendap.pl ex.dmp.xml

compile-pdflatex:
	$(DFF_PL) pdflatex ex </dev/null
	$(DFF_PL) pdflatex ex </dev/null

generate-ppm:
	rm -f tantia-*.ppm
	rm -f tsharp-*.ppm
	pdftoppm -aa no  -t1lib no -freetype yes -r 72 ex.pdf ex.tsharp
	if grep -qa '^/Subtype */TrueType$$' ex.pdf; then \
	  pdftoppm -aa yes -t1lib no -freetype yes -r 72 ex.pdf ex.tantia; \
	else \
	  pdftoppm -aa yes -t1lib yes -freetype no -r 72 ex.pdf ex.tantia; \
	fi

generate-spuxml:
	./genspuxml.pl ex

author-dvd:
	rm -rf exdvd
	dvdauthor -x ex.xml
	@echo "Play DVD with:  xine 'dvd:/$$PWD/exdvd'"

play:
	xine 'dvd:/$(shell pwd)/exdvd'
