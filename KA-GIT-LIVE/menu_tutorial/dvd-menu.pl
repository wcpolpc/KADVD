#!/usr/bin/perl

#
#  dvd-menu.pl (c) 2003-2004 by  Dr. Peter Sebbel, a perl script to facilitate the 
# automated  Video DVD generation using dvdauthor and other programs.
#  Contact: peter@vdr-portal.de
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; version 2 of the License
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.

#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA



use strict;
use warnings;

use GD;
use GD::Text;
#use GD::Text::Align;
use GD::Text::Wrap;



my $output_dir  = "./vdrsync";
my $tmp_dir     = "/tmp/";

my $version = "0.0.1";
#my $menu_mpeg;
#my $movie_mpeg;
#my $xml_path    = "/tmp/";
#my $xml_file    = "tmp.xml";
my $root_menu = 0;
my $title_menu = 0;
my $run_dvdauthor = 0;
my $finish = 0;
my @title_sets;
my %root_menu_cfg;
my %borders = (
    top    => 50,
    bottom => 526,
    right  => 670,
    left   => 50,
);
my $font ="/usr/X11R6/lib/X11/fonts/truetype/arial.ttf";

my $enhance_text_area = 50;
my $font_color        = "black";


my $usage =   qq(
    
    dvd-menu.pl $version (c) 2004 Dr. Peter Sebbel
    A little helper script for the generation of DVDs using dvdauthor
    Written as a helper for VDRsync
    
    Options:   
        
        -title [background=XY.jpg,title="Lost in Space",...]
            Tells the script to add a Title Set to the DVD. This Option
            can be set multiple times. For every Title Set, you can provide
            a comma-separated list of parameters. The parameters are key=value
            pairs (see examples below). Valid keys are
                title
                text
                background
                vob
                chapters
        
        -root [background=XY.jpg,title="Space Series",....]
            Tells the script to add a DVD Main Menu. This Option
            can be set only one time. You can provide
            a comma-separated list of parameters. The parameters are key=value
            pairs (see examples below). Valid keys are
                title
                text
                    This is special! The value you set here is split at | and 
                    the generated text parts are used to label the buttons in 
                    the main menu!
                background
                
        
        -run-dvdauthor
            Tells the script to run dvdauthor. Otherwise only the mpeg-files 
            for the menus and the xml-Files for DVDauthor are created
        
        -o PATH
            output-Path. Here the DVD-Structure is generated
        
        -font "PATH"
            Full path to the ttf file you want to use. Default is
            /usr/X11R6/lib/X11/fonts/truetype/arial.ttf
            
        -borders x1,y1,x2,y2
            sets the image borders, usefull if the overscan of your TV is 
            bigger than mine. Default borders are at:  50, 526, 670, 50
        
        -enhance-text-area
            the area in which text is pasted is merged with a white area to
            ensure readability of the text. By default the white area is 
            merged with a weight of 50%. If you want a fully white block as 
            text-background, choose 100 here. To switch this feature of, 
            choose 0. Or adjust to your taste.
                
        -font-color
            default is black, alternative is white. Do not forget to adjust
            the enhance-text-area Option if you choose this.
);

# print $usage;
parse_parameters();




foreach my $title (@title_sets) {
    create_title_menu (\%{$title});
    
}

if ($root_menu)  {
    print "creating DVD Menu\n";
    create_root_menu();
} else {
    print "NOT creating DVD Menu\n";
}

exit;

sub fit_text_to_box {
    my ($height, $width, $pt_size, $text) = @_;
    
    my $fit = 0;
    
    my $test_img  = new GD::Image("720", "576", "1");
    
    #
    # Allocate black and white
    #
    print "Trying to fit text $text to $height pt in height\n";
    
    my $white = $test_img->colorResolve(255,255,255);
    my $black = $test_img->colorResolve(0,0,0);
    
     my $label = GD::Text::Wrap->new($test_img,
          line_space  => 3,
          color       => $black,
          text        => $text,
          width       => $width,
          align       => "justified",
          font        => $font,
          ptsize      => $pt_size,
        );
        
    while ((! $fit) && ($pt_size > 10)) {
        
        $label->set( ptsize => $pt_size);
        
        my ($left, $top, $right, $bottom) = $label->draw(0, 0);
        
        print "Takes the following space $left, $top, $right, $bottom\n";
        
        if (($bottom - $top) <= $height) {
            $fit = 1;
            print "Text fitted at pt_size $pt_size\n";
        } else {
            $pt_size--
        }
    }
    while (! $fit) {
        
        my $length = length($text);
        my @words = split / /,$text;
        
        $text = join " ",(@words[0..(scalar(@words)-2)]);
        print "Before: $length, after " . length($text) ."\n";
        $label->set( text => $text);
        my ($left, $top, $right, $bottom) = $label->get_bounds(0, 0);
        print "After trimming: $left, $top, $right, $bottom\n";
        if (($bottom - $top) <= $height) {
            $fit = 1;
            print "Text fitted at pt_size $pt_size\n";
        }
        
    }
        
    return $pt_size, $text;
    
    
}

sub create_title_menu{
    print "creating title\n";
    my %config = %{ shift @_ };
    
    print "starting to create Menu pngs...\n";
    foreach (keys(%config)) {
        print "$_: $config{$_}\n";
    }
    $config{buttons} = 1;
    
    my %button_layers = %{ create_button_Masks(\%config) };

    foreach(keys(%button_layers)) {
        open OF, ">$tmp_dir/$_" or die "$!\n";
        print OF $button_layers{$_};
        close OF;

    }
    create_mpeg(\%config);
    create_titleset_xml(\%config);
}

sub create_root_menu {
    
    my $title_set_no = scalar(@title_sets);
    if (! $root_menu_cfg{buttons}) {
        $root_menu_cfg{buttons} = $title_set_no;
    }
    
    my %button_layers = %{ create_button_Masks(\%root_menu_cfg) };

    foreach(keys(%button_layers)) {
        open OF, ">$tmp_dir/$_" or die "$!\n";
        print OF $button_layers{$_};
        close OF;

    }
    create_mpeg(\%root_menu_cfg);
    create_root_menu_xml(\%root_menu_cfg);
}

sub add_to_title_list {
    my $param = shift;
    my $title_set_no = scalar(@title_sets);
    $title_sets[$title_set_no] = ();
    
    
    while ($param =~/(vob|background|chapters|title|text)=(.+?)(?=(,vob|,background|,chapters|,title|,text|$))/g) {
        print "Matched  $1 = $2 \n ";
        $title_sets[$title_set_no]{$1} = $2;
    }
    
    $title_sets[$title_set_no]{title_set_menu} = 1;
    if (! $title_sets[$title_set_no]{title}) {
        $title_sets[$title_set_no]{title} = "Title " . ($title_set_no + 1);
    }
    if (! $title_sets[$title_set_no]{text}) {
        $title_sets[$title_set_no]{text} = "No Information available";
    }
    if ( -f $title_sets[$title_set_no]{text} ) {
        open IFH, "$title_sets[$title_set_no]{text}" or die "could not open $title_sets[$title_set_no]{text}: $!\n";
        my @help = <IFH>;
        close IFH;
        $title_sets[$title_set_no]{text} = join"", @help;
    }
    return 0;
}




sub create_button_Masks {
    
    my %config = % { shift @_ };
    
    
    foreach (keys(%config)) {
        print "$_: $config{$_}\n";
    }
    
    
    my %ret_hash;    
    
    $ret_hash{"background.jpg"} = create_bg_image       (\%config);
    $ret_hash{"menu.png"}       = create_menu_Mask      (\%config);
    $ret_hash{"highlight.png"}  = create_highlight_Mask (\%config);
    $ret_hash{"select.png"}     = create_select_Mask    (\%config);
    return \%ret_hash;
}

sub create_bg_image {
    
    
    my %config = %{ shift @_ };
    my $temp_img;
    my $enhance_color;
    my $label_color;
    
    my $align = "justified";
    if ($config{root_menu}) {
        $align = "left";
    }
    
    
    my ($left, $top, $right, $bottom);
    
    GD::Image->trueColor(1);
    print "Creating Background image\n";
    
    
    my $ret_img  = new GD::Image("720", "576", "1");
    
    #
    # Allocate black and white
    #
    
    my $white = $ret_img->colorResolve(255,255,255);
    my $black = $ret_img->colorResolve(0,0,0);
    if (($black == -1) || ($white == -1)) {
        die "Could not resolve to black or white\n";
    }
    # Set label color
    if ($font_color eq "white") {
        $label_color = $white;
    } else {
        $label_color = $black;
    }
       
    #
    # Check whether we should use an existing JPEG, and resize it if necessary
    # Also create a dummy image, used for enhancing text areas
    #
    
    
    
    my $dummy_img = GD::Image->new("720", "576");
    my $dwhite = $dummy_img->colorResolve(255,255,255);
    my $dblack = $dummy_img->colorResolve(0,0,0);
    if (($dblack == -1) || ($dwhite == -1)) {
        print "Could not allocate color dwhite or dblack\n";
    }
    if ($font_color eq "white") {
        $enhance_color = $dblack;
    } else {
        $enhance_color = $dwhite;
    }
    $dummy_img->filledRectangle(0,0,(719), (575), $enhance_color);
    
    if ($config{background}) {
        my $temp_img = newFromJpeg GD::Image($config{background});
        #print "Created temp image from jpeg: $temp_img\n";
        my ($width, $height) = $temp_img->getBounds();
        $ret_img->copyResized($temp_img,0,0,0,0,720,576,$width,$height);
    } else {
        if ($font_color eq "white") {
            $ret_img->filledRectangle(0,0,(719), (575), $black);
            print "Creating black bg\n";
        } else {
            $ret_img->filledRectangle(0,0,(719), (575), $white);
            print "Creating white bg\n";
        }
    }
    
   
    # Draw Title of the menu
        
    my $wrapbox = GD::Text::Wrap->new($ret_img,
      line_space  => 3,
      color       => $label_color,
      text        => $config{title},
      width       => ($borders{right} - $borders{left}),
      align       => "center",
      font        => $font,
      ptsize      => 24,
    );
    
    if ($enhance_text_area) {
        ($left, $top, $right, $bottom) = $wrapbox->get_bounds($borders{left}, $borders{top});
        $ret_img->copyMerge($dummy_img, $left,$top,$left,$top,($right-$left), ($bottom - $top), $enhance_text_area);
    }
    ($left, $top, $right, $bottom) = $wrapbox->draw($borders{left}, $borders{top});
    
    #
    # Now draw Menus items
    # dist is the spacing of the menu items, if you have more than one item, those are evenly distributed 
    # NOTE: $bottom here means bottom of the title text area, so in fact for the labels it is the top border
    # 
    # This value is added to the %borders hash to allow reference later, when the masks are created
    #
    
    $borders{list_top} = $bottom + 20;
    
    my $dist = (576 - $borders{list_top} - (576 - $borders{bottom})) /  $config{buttons};
    
    my @titles = split/\|/,$config{text};
    
    print "Splitting $config{text}\n";
   
    
    for (my $i = 0; $i < $config{buttons}; $i++) {
        my $text = shift @titles;
        if (! $text) {
            $text = "Title " . ($i +1);
        }
        print "adding $text to button\n";
        
        my ($pt_size, $final_text) = fit_text_to_box(
                                        $dist,                                    # max height
                                        ($borders{right} - $borders{left}- 40),   # max width
                                        20,                                       # pt_size
                                        $text);                                   # text to fit in
        
        
        # created the label
        my $label = GD::Text::Wrap->new($ret_img,
          line_space  => 3,
          color       => $label_color,
          text        => $final_text,
          width       => ($borders{right} - $borders{left} - 50),
          align       => $align,
          font        => $font,
          ptsize      => $pt_size,
        );
        
        if ($enhance_text_area) {
            ($left, $top, $right, $bottom) = $label->get_bounds($borders{left} + 40, $borders{list_top} + ($i*$dist));
            $ret_img->copyMerge($dummy_img, $left - 40, $top, $left - 40, $top, ($right-$left) + 50, ($bottom - $top), $enhance_text_area);
        }
        $label->draw($borders{left} + 40, $borders{list_top}  + ($i*$dist));
    }
    
    # Now draw the black circles as background for the buttons
    #
    for (my $i = 0;  $i < $config{buttons}; $i++) {
        $ret_img->filledEllipse($borders{left} + 20, $borders{list_top} + 15 + ($i*$dist), 30, 30 ,$black);
        #$ret_img->filledRectangle(20, 80+($i*$dist), 60, 100+($i*$dist), $red);
        #  print "painting: 20, " . (80+($i*$dist)) .", 60, " . (100+($i*$dist)) . "\n"; 
    }
    
    #
    # Finally the back button
    #
    
    my $back = GD::Text::Wrap->new($ret_img,
      line_space  => 3,
      color       => $label_color,
      text        => "Back",
      width       => 40,
      align       => "left",
      font        => $font,
      ptsize      => 12,
    );
    if ($enhance_text_area) {
        ($left, $top, $right, $bottom) = $back->get_bounds((($borders{right}-$borders{left}) * 0.9), $borders{bottom} - 20);
        $ret_img->copyMerge($dummy_img, $left, $top, $left, $top, ($right-$left), ($bottom - $top), $enhance_text_area);
    }
    ($left, $top, $right, $bottom) = $back->draw((($borders{right}-$borders{left}) * 0.9), $borders{bottom} - 20);
    
    
    return $ret_img->jpeg;
}

sub create_menu_Mask {
    
    my %config = % { shift @_ };
    
    my $ret_img;
    
    
    print "Creating menu image\n";
    foreach (keys(%config)) {
    #    print "$_: $config{$_}\n" if ($_ ne "text");
    }
    
    #print "Got the top value: $borders{list_top}\n";
    
    


    $ret_img = new GD::Image("720", "576");
    my $white = $ret_img->colorAllocate(255,255,255);
    my $lred   = $ret_img->colorAllocate(150,0,0);
    my $black = $ret_img->colorAllocate(0,0,0);
    $ret_img->transparent($black);
    $ret_img->filledRectangle(0,0,(719), (575), $black);
    
        
    my $dist = (576 - $borders{list_top} - (576 - $borders{bottom})) /  $config{buttons};
    #my $dist = (576 - $borders{top} - (576 - $borders{bottom})) /  $config{buttons};
    
    for (my $i = 0;  $i < $config{buttons}; $i++) {
        $ret_img->filledEllipse($borders{left} + 20, $borders{list_top} + 15 + ($i*$dist), 20, 20, $lred);
        
        #$ret_img->filledEllipse(70, 90, 20, 20, $red);
        
        #$ret_img->filledEllipse(40, 90+($i*$dist), 35, 35 ,$black);
        #$ret_img->filledEllipse(40, 90+($i*$dist), 20, 20 ,$red);
        #$ret_img->filledRectangle(20, 80+($i*$dist), 60, 100+($i*$dist), $red);
        #print "painting: 20, " . (80+($i*$dist)) .", 60, " . (100+($i*$dist)) . "\n"; 
    }
    
    
    
    #Back Button
       
    
    $ret_img->filledEllipse((($borders{right}-$borders{left}) * 0.9) - 20, $borders{bottom} - 12, 20, 20, $lred);
    print "returning\n";
    return $ret_img->png;
}


sub create_highlight_Mask {
    
    my %config = % { shift @_ };
    print "Creating Highlight image\n";
    foreach (keys(%config)) {
    #    print "$_: $config{$_}\n";
    }
    
    
    my $dist = (576 - $borders{list_top} - (576 - $borders{bottom})) /  $config{buttons};
    #my $dist = (576 - $borders{top} - (576 - $borders{bottom})) /  $config{buttons};
    
    my $ret_img = new GD::Image("720", "576");
    my $white = $ret_img->colorAllocate(255,255,255);
    my $lgrey = $ret_img->colorAllocate(150,150,150);
    my $red = $ret_img->colorAllocate(255,0,0);
    my $black = $ret_img->colorAllocate(0,0,0);    
    
    $ret_img->transparent($black);
    $ret_img->filledRectangle(0,0,(719), (575), $black);
    
    for (my $i = 0; $i < $config{buttons}; $i++) {
        #
        #$ret_img->filledRectangle(20, 80+($i*$dist), 60, 100+($i*$dist), $lred);
        #$ret_img->filledEllipse(40, 90+($i*$dist), 20, 20 ,$lred);
        $ret_img->filledEllipse(($borders{left} + 20), ($borders{list_top} + 15 + ($i*$dist)), 20, 20, $red);
        
        #print  $borders{left} + 20 .",". ($borders{top} + 40 + ($i*$dist)) .", 20, 20, $lred)\n";
    }
    # Exit Button
    #$ret_img->filledRectangle(250, 510, 290, 550, $lred);
    #$ret_img->filledEllipse(270, 530, 20, 20, $lred);
    $ret_img->filledEllipse((($borders{right}-$borders{left}) * 0.9) - 20, $borders{bottom} - 12, 20, 20, $red);
    return $ret_img->png;
}       

sub create_select_Mask {
    
    my %config = % { shift @_ };
    print "Creating Select image\n";
    foreach (keys(%config)) {
      #  print "$_: $config{$_}\n";
    }
    
    #my $dist = (576 - $borders{list_top} - (576 - $borders{bottom})) /  $config{buttons};
    my $dist = (576 - $borders{list_top} - (576 - $borders{bottom})) /  $config{buttons};
    
    my $ret_img = new GD::Image("720", "576");
    my $white = $ret_img->colorAllocate(255,255,255);
    my $lred = $ret_img->colorAllocate(150,0,0);
    my $black = $ret_img->colorAllocate(0,0,0);
    $ret_img->transparent($black);
    $ret_img->filledRectangle(0,0,(719), (575), $black);
    
    for (my $i = 0; $i < $config{buttons}; $i++) {
        $ret_img->filledEllipse(($borders{left} + 20), ($borders{list_top} + 15 + ($i*$dist)), 20, 20, $lred);
        #$ret_img->filledRectangle(20, 80+($i*$dist), 60, 100+($i*$dist), $lred);
        #$ret_img->filledEllipse(40, 90+($i*$dist), 35, 35 ,$black);
        #$ret_img->filledEllipse(40, 90+($i*$dist), 20, 20 ,$lred);
    }
    # Exit Button
    #$ret_img->filledRectangle(250, 510, 290, 550, $lred);
    #$ret_img->filledEllipse(270, 530, 20, 20, $lred);
    $ret_img->filledEllipse((($borders{right}-$borders{left}) * 0.9) - 20, $borders{bottom} - 12, 20, 20, $lred);
    return $ret_img->png;
}


sub create_mpeg {
    
    my %config = % { shift @_ };
    print "Creating menu mpeg\n";
    foreach (keys(%config)) {
       # print "$_: $config{$_}\n";
    }
    open OFH, ">./jpeg.list";
    print OFH "$tmp_dir/background.jpg\n" x 12;
    #print "transcode -i jpeg.list -k -z  -x imlist,null  -g 720x576   -y ffmpeg,null -F mpeg2video   -o $tmp_dir" . "menu -H 0";
    system "transcode -i jpeg.list -k -z  -x imlist,null  -g 720x576   -y ffmpeg,null -F mpeg2video   -o $tmp_dir" . "menu -H 0  &>/dev/null";
    my $silence = get_silent_frame();
    open OFH, ">./silence.mpa";
    print OFH $silence x 20;
    close OFH;
    system "mplex -f 8 $tmp_dir/menu.m2v silence.mpa -o $tmp_dir/menu.mpg &>/dev/null";
}


sub get_silent_frame {


    my $frame;
    my $function;
    
    
    my $uu_frame =  <<'End_FRAME';
M__V$`"(B(D1$1#,R(B(B)))```````````"JJJJJJJJJ^^^^^^^^^^^^^^^^
M^^^^^^^^^^^^;;;;;;;;;6Q;%L6Q;%L;;;;;Y\^?/GSYK6M:UMMMMMMMMM;%
ML6Q;%L6QMMMMOGSY\^?/FM:UK6VVVVVVVVUL6Q;%L6Q;&VVVV^?/GSY\^:UK
M6M;;;;;;;;;6Q;%L6Q;%L;;;;;Y\^?/GSYK6M:UMMMMMMMMM;%L6Q;%L6QMM
MMMOGSY\^?/FM:UK6VVVVVVVVUL6Q;%L6Q;&VVVV^?/GSY\^:UK6M;;;;;;;;
M;6Q;%L6Q;%L;;;;;Y\^?/GSYK6M:UMMMMMMMMM;%L6Q;%L6QMMMMOGSY\^?/
MFM:UK6VVVVVVVVUL6Q;%L6Q;&VVVV^?/GSY\^:UK6M;;;;;;;;;6Q;%L6Q;%
ML;;;;;Y\^?/GSYK6M:UMMMMMMMMM;%L6Q;%L6QMMMMOGSY\^?/FM:UK6VVVV
8VVVVUL6Q;%L6Q;&VVVV^?/GSY\^:UK6M
end
End_FRAME
    foreach (split "\n", $uu_frame) {
        last if /^end/;
        next if /[a-z]/;
        next unless int((((ord() - 32) & 077) + 2) / 3) == int(length() / 4);
        $frame .= unpack "u", $_;
    }
    return $frame;
}


sub create_titleset_xml {
    my %config = %{ shift @_ };
    print "Creating Titleset menu and xmls\n";
    foreach (keys(%config)) {
       # print "$_: $config{$_}\n";
    }
    
    my $xml = qq(<subpictures>
  <stream>
    <spu start="00:00:01.0"
         image="$tmp_dir/menu.png"
         highlight="$tmp_dir/highlight.png"
         select="$tmp_dir/select.png"
         autooutline="infer"
         force="yes"
         autoorder="rows">
    </spu>
  </stream>
</subpictures>);

    open  OFH, ">$tmp_dir/submux_title.xml" or die "$!\n";
    print OFH $xml;
    close OFH;
    
    my $result = system "spumux $tmp_dir/submux_title.xml < $tmp_dir/menu.mpg > $tmp_dir/title_menu.mpg";
    if ($result) {
        die "Menu generation failed: $result\n";
    }
    
     $xml = qq(<dvdauthor dest="$output_dir/">
  <titleset>
    <menus>
      <video format="pal" aspect="4:3" />
      <pgc entry="root">
        <button> jump title 1; </button>
        <button> jump vmgm menu 1; </button>
        <vob file="$tmp_dir/title_menu.mpg"/>
      </pgc>
    </menus>
    <titles>
      <pgc>
        <post>
          call vmgm menu 1;
        </post>
          );
    if ($config{vob}) {
        $xml .= "<vob file=\"$config{vob}\"";
    }
    else {
        $xml .= "<vob file=\"Please insert MPEG File here\"";
    }
    if ($config{chapters}) {
        $xml .= qq(
            chapters=\"$config{chapters}\"/>
      );
    } else {
        $xml .= "/>";
    }
    $xml .= qq(  </pgc>
    </titles>
  </titleset>
</dvdauthor>
);
    open  OFH, ">$tmp_dir/title_menu.xml" or die "$!\n";
    print OFH $xml;
    close OFH;
    if ($run_dvdauthor && $config{vob}) {
        $result = system"dvdauthor -x  $tmp_dir/title_menu.xml";
        print "DVDauthor run for title set ended with $result\n";
    } else {
        print "only producing xml file\n";
    }

}

sub create_root_menu_cfg {
    
    my $param = shift;
    my $title_set_no = scalar(@title_sets);
    
    print "preparing root Menu settings\n";
    
    while ($param =~/(background|title|text|buttons)=(.+?)(?=(,background|,title|,text|,buttons|$))/g) {
        print "Matched  $1 = $2 \n ";
        $root_menu_cfg{$1} = $2;
    }
        
  
    $root_menu_cfg{root_menu} = 1;
    if (! $root_menu_cfg{title}) {
        $root_menu_cfg{title} = "DVD Main Menu";
    }
    
    if (! $root_menu_cfg{buttons}) {
        if (! $title_set_no) {
            $root_menu_cfg{buttons} = 1;
            $root_menu_cfg{text} = "Title 1";
        } else {
            $root_menu_cfg{buttons} = $title_set_no;
        }
    }
    if (! $root_menu_cfg{text}) {
        if ($title_set_no) {
            for (my $i = 1; $i <= $root_menu_cfg{buttons}; $i++) {
                #print "we have " . scalar(@title_sets) . " to deal with\n";
                #print "Checking Title Set $i: $title_sets[$i-1]{title}\n";
                #foreach(keys(%{$title_sets[$i-1]})) {
                #    print "Title set $i-1 key: $_\n";
                #}
                $root_menu_cfg{text} .= "$title_sets[$i-1]{title}|";
            }
        } else {            
            for (my $i = 1; $i <= $root_menu_cfg{buttons}; $i++) {
                $root_menu_cfg{text} .= "Title $i|";
            }
        }
    }
    
    foreach (keys(%root_menu_cfg)) {
        print "ROOTMENU $_: $root_menu_cfg{$_}\n";
    }
}

sub create_root_menu_xml {
    
    my %config = %{ shift @_ };
    print "Creating Titleset menu and xmls\n";
    foreach (keys(%config)) {
        print "$_: $config{$_}\n";
    }
    my $xml = qq(<subpictures>
  <stream>
    <spu start="00:00:1.0" 
         image="$tmp_dir/menu.png"
         highlight="$tmp_dir/highlight.png"
         select="$tmp_dir/select.png"
         autooutline="infer"
         force="yes"
         autoorder="rows">
    </spu>
  </stream>
</subpictures>);

    open  OFH, ">$tmp_dir/submux_root.xml" or die "$!\n";
    print OFH $xml;
    close OFH;
    
    my $result = system "spumux $tmp_dir/submux_root.xml < $tmp_dir/menu.mpg > $tmp_dir/root_menu.mpg";
    if ($result) {
        die "Menu generation failed: $result\n";
    }
    
     $xml = qq(<dvdauthor dest="$output_dir/">
  <vmgm>
    <menus>
      <video format="pal" aspect="4:3" />
      <pgc entry="title">\n);
    
    
    for (my $i = 1; $i <= $config{buttons}; $i++) {     
        $xml .="        <button> jump titleset $i menu; </button>\n";
    }
    
    
    $xml .= qq(        <button> exit; </button>
        <vob file="$tmp_dir/root_menu.mpg" pause="inf"/>
      </pgc>
    </menus>
  </vmgm>
</dvdauthor>
);
    open  OFH, ">$tmp_dir/root_menu.xml" or die "$!\n";
    print OFH $xml;
    close OFH;
    if ($run_dvdauthor) {
        $result = system"dvdauthor -x  $tmp_dir/root_menu.xml";
        print "DVDauthor run for root menu ended with $result\n";
    }

}


sub parse_parameters {
    
    my $root_settings;
    while(@ARGV) {
        my $param = shift @ARGV;
        if ($param !~ /^-/) {
            die "Unknown parameter $param\n";
        }
        if ($param =~ /^-title$/) {
            my $title = shift @ARGV;
            print "ADD $title to title menu\n";
            my $result = add_to_title_list($title);
            if ($result) {
                die "Failed to add $title to title sets\n";
            }
        }
        elsif ($param =~ /^-root$/) {
            if ($ARGV[0] !~ /^-/) { 
                $root_settings = shift @ARGV;
            }
            $root_menu = 1;
        }
        elsif ($param =~ /^-o$/) {
            $output_dir = shift @ARGV;
            if (! -d $output_dir) {
                my $result = system "mkdir $output_dir\n";
                if ($result) {
                    die "Could not find $output_dir and failed to create it\n";
                }
            }
            if ($output_dir !~/\/$/) {
                $output_dir .= "/";
            }
        } 
        elsif ($param =~ /^-run-dvdauthor$/) {
            $run_dvdauthor = 1;
        } 
        
        elsif ($param =~ /^-borders$/) {
            my @dummy = split /,/,(shift @ARGV);
            $borders{left}    = $dummy[0] || $borders{left};
            $borders{top}     = $dummy[1] || $borders{top};
            $borders{right}   = $dummy[2] || $borders{right};
            $borders{bottom}  = $dummy[3] || $borders{bottom};
            print "$borders{left} $borders{top} $borders{right} $borders{bottom}\n";
            
        } 
        elsif ($param =~ /^-font$/) {
            if ($ARGV[0] !~ /^-/) { 
                $font = shift @ARGV;
            }
        }
        elsif ($param =~ /^-font-col(o|ou)r$/) {
            if ($ARGV[0] !~ /(black|white)/) { 
                die "Font color must be black or white!\n";
            } else  {
                $font_color = shift @ARGV;
            }
        }            
        elsif ($param =~ /^-enhance-text-area$/) {
            if ($ARGV[0] !~ /\d{1,3}/) { 
                die "Please specifiy a percentage by which the text areas ocntrast will be enhanced\n";
            } else {
                $enhance_text_area = shift @ARGV;
            }
        }
        else {
            die "Unknown parameter $param\n";
        }
    }
    if ($root_menu) {
        my $result = create_root_menu_cfg($root_settings);
        if ($result) {
            die "Failed to define root menu: $root_settings\n";
        }
    }
    print "Finished parsing command line\n";
    if ((! @title_sets) &&(! $root_menu)) {
        print $usage;
        exit;
    }
    
}










