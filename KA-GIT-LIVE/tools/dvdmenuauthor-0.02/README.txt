README for dvdmenuathor
by pts@fazekas.hu at Mon Feb  5 18:58:39 CET 2007

dvdmenuauthor makes it easy and efficient to author a DVD with menus in an
indirect (non-WYSIWYG) way. An XML project file drives the DVD authoring,
from which both menus and a dvdauthor XML file are generated, and dvdauthor
(and spumux) are used to author the DVD filesystem. Menu items (buttons and
static items such as images and text) can be specified conscisely in the
project XML file with LaTeX markup (to be processed by pdfLaTeX and rendered 
by xpdf).

See Makefile for the version of the software.

Software requirements:

-- a Unix system (should be easy to port to Win32)
-- Perl v5.8
-- ffmpeg
-- ImageMagick
-- LaTeX (optional, needed by the LaTeX menu backend)
-- pdftoppm with Freetype support (part of xpdf 3.01, optional, needed by the
   LaTeX menu backend)
-- sam2p (optional, makes temporary PNG generation faster)
-- The GIMP (optional, recommended for the GIMP menu backend)
-- dvdauthor (optional, recommended for DVD filesystem, image and disc
   authoring)
-- mkisofs (optional, recommended for DVD image and disc authoring)
-- growisofs (optional, recommended on Linux for DVD disc authoring)

Software status:

-- architecture design: beta
-- LaTeX menu backend: beta
-- Perl menu backend: not implemented yet (should be easy)
-- GIMP menu backend: not implemented yet (might be hard)
-- Unix port: stable, tested on Linux
-- Win32 port: not implemented (should be easy)

Copyright and license
~~~~~~~~~~~~~~~~~~~~~
dvdmenuauthor is written by Péter Szabó <pts@fazekas.hu>.

dvdmenuauthor is free software. You can use it under the GNU General Public
License (GNU GPL) version 2 or, at your choice, any later version.

TODO and quick comments for developers
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Dat: dvdmenuauthor project extension: .dmp.xml or .dmpxml
Dat: default project XML file charset: UTF-8
     <?xml version="1.0" encoding="UTF-8"?><dvdmenuauthor>
Dat: good: rectangular rules (\hrule and \vrule) are never antialiased (not even with pdftoppm -aa yes)
Dat: good quality, nice half-gray: \includegraphics[width=.5\paperwidth,height=.5\paperheight]{pal_bg_stripe2}
     however, -aa yes is a little different with its horizontal lines
Dat: good image not-scaling in: pdftoppm -r 72 dvdmenu.pdf troot
Dat: good \pagecolor-sensitive antialiasing in: pdftoppm -r 72 dvdmenu.pdf troot
Dat: good render: a 4bp wide rule is exactly 4 pixels high, no antialiasing
     in pdftoppm
Dat: xpdf -z 100 ex.pdf
Dat: \pagecolor{...} works (pdftex.df \gdef\shipout), and has effect on all
     subsequent pages
Dat: added \thispagecolor
Dat: all DVD menus (by definition) are single-page
Dat: good: pdftoppm saves color #0000fe properly
Dat: direct (uncompressed) PNG output is hard from Perl, because we have
     to calculate CRCs
Dat: recommended size for video preview images: make it same size as the
     movie and the menu (e.g. 720x576 for PAL), and then eithor not scale
     them (to get a full-screen \thispagebgimage{...}) or scale them down
     [width=.5\paperwidth,width=.5\paperheight] or
     [width=.25\paperwidth,width=.25\paperheight].
     With any setting other than these you get a little worse image quality.
Dat: genspumux.pl detects missing \dvdbutton()s in LaTeX
Dat: SUXX: ImageMagick text doesn't do pair kerning (=> use ftbannerpnm)
Dat: dvdauthor 0.6.13: verbose warning for more than 128 commands per pgc
Dat: VideoLink takes HTML pages, with links, and turns them into a DVD
     menu structure.
Dat: Videotrans is a set of scripts for converting movies into VOBs for
     dvdauthor. It also has some menu generation abilities.
Dat: It is not an error to have multiple button declarations under the
     same name in a dvdmenuauthor LaTeX menu.
Dat: here is how to quickly test the menu images: edit ex.dmp.xml;
     make generate-latex compile-pdflatex
Dat: spumux refuses intersecting (overlapping, non-disjoint) buttons,
     so we don't have to check for it
Dat: good: pdflatex can embed JPEG and PNG images directly
Dat: SUXX: neither sam2p(1) nor pdfTeX 1.10b can embed PNG with transparency,
     but convert(1) can, using `/SMask 9 0 R', where 9 0 R is a grayscale
     image
OK: select menu audio codec from XML:
    <dvdmenuauthor genmpeg:audio-codec="ac3"
OK: select MPEG generation software from XML:
    <dvdmenuauthor genmpeg:video-with="ffmpeg"
!! compress fonts horizontally (4:3)
!! new dvdauthor 0.6.13 needs even y0 and y1 for buttons (not veri picky)
!! feature: GIMP backend
!! feature: Perl image backend
!! investigate: tantia-000013.ppm is good, menu-000003-spu.mpg in
   mplayer -noaspect;
   is bad displaying the horizontal lines -- who makes it bad? ffmpeg?
!! extsizes.sty, size20.clo
!! possibly use \topskip
!! no font size substitution (like in type1cm.sty)
!! generate selected and highlighted PPMs
!! good quality image downscaling by pdftoppm?
!! pdftoppm -t1lib yes -freetype no
   seems to have better (less gray) antialiasing for lmr in small sizes
   test it properly
   with `-aa no', freetype is much better than t1lib
!! support NTSC
!! \linewidth etc.
!! \small, \large etc.
!! disallow normal page output (such as \begin{document})
!! automatic DVD menu renumbering (pdfpagenr -> titlesetnr.menunr)
   titlesetnr==0 is vmgm
!! \dvdframedbutton
!! default font etc.
!! \dvdhrule (default: width 1bp)
!! doc: side effects of \parskip20bp
!! good quality non-antialiased fonts in pdftoppm
!! verify that same button name/index doesn't get repeated
!! button left= right= etc.
!! verify that all required buttons are generated (\dvdtextbutton)
!! keyval-style interface to e.g. {dvdmenupage}[buttonorder={c,b,a}]
!! sam2p transparent PDF
!! indicate what is customizable (e.g. dvd*color)
!! doc: \color{dvdfakepage}
!! doc: buttons are not allowed to be put into constructs with
   PDF `cm' transformations (such as \scalebox and \rotatebox)
   !! verify this
!! using pdftoppm 3.01, provide a statically linked version
!! feature: make the buttons wider (easier to click), as wide as possible
   without touching other buttons; grow them in parallel
!! smart margins
!! \dvdbutton[type=frame]
!! magyar.ldf
!! report desired button with in .aux file (and override autodetect)
!! dependencies: sam2p (PNG generation)
!! make selected different from highlighted in 
!! generated BMP instead of PPM, so we can avoid sam2p -> PNG
!! faster RGB->YUV conversion than convert(1) (a dependency)
!! feature: autodetect 16:9
!! doc: 16:9 menus == 4:3 menus (no aspect ratio)
!! allow 16:9 menus and 4:3 menus with aspect ratio correction
!! feature: generate dvdauthor .xml file from templates
!! genmpeg.pl on $PATH?
!! doc: how to draw the menus without TeX in GIMP (with layers)
!! feature: an image compositor easier to install than TeX
!! doc: dependency: dvdauthor, spumux, ffmpeg, Perl, pdftex, ppmtopdf (xpdf
   3.01)
!! why are the generated DVD highlights blue? (menu 2, menu 3)
!! make -aa yes and -aa no rendering consistent
!! menu3 color highlights (coloring not disabled??)
!! cross-platform (Win32)
!! include dvdmenutest.sh
!! animated menu (without clicking the button)
!! doc: dimensions: 1bp, \paperwidth, aspect ratio
!! doc: \pageref: menu number (i.e. page number not including buttons)
!! test: rounding errors using bp
!! \hline etc. \frulewidth
!! doc: \thispagebgimage etc.
!! .dmp.xml option for no spumux =transparent in genspumux.pl
!! run not from the current folder only (but, for arhival reasons, the
   software should be kept in the same folder as the DVD source and target)
!! test: with magyar.ldf
!! feature: reliable progress indicator while running Makefile
!! feature: automatic recompilation with pdflatex (refs)
!! rename genspuxml.pl to gentexmenu.pl
!! gendap.pl should report project XML file offset on error
!! doc: multiple <tex:page> (and <tex:footer> etc.) in a row are OK
!! create (still) titles in LaTeX, just like menus, in <pgc>, add nframes
!! feature: some tags from project XML to tag (title name??)
!! feature: Makefile preview
!! copy \ref from with dvdmenu.tex to ex.dmp.xml
!! <button><tex:button>...  and \dvdmaybebutton{BUTTONNAME}{IF-NO-SUCH}
!! <button left="..." to spumux
!! spumux <action s (commands that are executed as soon as the associated key is pressed on the remote).
!! dvdauthor 0.6.13: buttons need even 'Y' coordinates
!! dvdauthor `goto' and `break' commands not documented
!! fix: only 1 audio channel:
   INFO: Audio ch 0 format: ac3/6ch, 48khz drc
!! doc: dvdmenutest.pl
!! doc: \global and \c@page in \expandafter\global\expandafter\edef \csname DVD@@definedbutton@#1\endcsname{\the\c@page}%
!! doc: t1lib cannot render Type1 fonts
!! fix design/transp_*.pdf so that \dvdframebutton draws a smaller button
!! doc: \dvdbuttonframesep
!! SUXX: why is rendering so bad?
   \dvdbuttonframewidth4bp is increased to 5 pixels (instead of 4) on
   page 29, 30 etc. (for our buttons). PostScript is good, but currentpoint
   is not an integer. Might be a rounding error? Should we change from bp to
   pt units? Not yet. anyway, the output of pdftops seems to be OK
   `matrix currentmatrix ==' has only integers
!! doc: `<button name="prev" tex:dummy="">'
!! feature: abolity to override tex:image= for `<button name="prev" tex:dummy="">'
!! doc: menus are not auto-connected
