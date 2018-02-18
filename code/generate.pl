#!/usr/bin/perl
use CGI ':standard';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser); 
use warnings;
use strict;
use utf8;
use Encode qw(encode from_to);
# binmode(STDIN, ":encoding(UTF-8)");
use JSON::XS;
use LWP::Simple;
use Data::Dumper;
use lib '.';
use Data::Compare;
use List::Util qw(min max);

my $SIGNWIDTH = 220;

my $q = CGI->new;

my $data = $q->param('POSTDATA');
my $out;
my $store; #processed tags
my $conf;  #calculated data like number of lanes
my $image;
my $error = "";
# $image = "Content-Type: image/svg+xml; charset=utf-8\r\n".
#          "Access-Control-Allow-Origin: *\r\n\r\n";
$image = "Content-Type: text/text; charset=utf-8\r\n".
         "Access-Control-Allow-Origin: *\r\n\r\n";

$out =   "Content-Type: text/text; charset=utf-8\r\n";
         "Access-Control-Allow-Origin: *\r\n\r\n";
$image .= getFile("_head.svg");


#################################################
## Process data
#################################################  
my $dat;

eval {
    $dat = decode_json($data);
    1;
    } 
  or do {
    print  "<h3>No valid data</h3>". $data;
    die;
    };

    
my @showdirections;
my $t = $dat->{'direction'};
if($t == 1 || $t == -1) {
  $showdirections[0] = $t;
  }
else {
  $showdirections[0]=-1; 
  $showdirections[1]=1;
  }

$t = $dat->{'country'};  
if($t =~ /^[A-Z][A-Z]$/) {
  $conf->{country} = $t;
  }
else {
  $conf->{country} = 'EN'
  };  
  
foreach my $tag (keys %{$dat->{tags}}) {
  if ($tag =~ /^destination/) {
    getLaneTags($tag,$dat->{tags}{$tag});
    }
  if ($tag =~ /^turn/) {
    getLaneTags($tag,$dat->{tags}{$tag});  
    }
  if ($tag =~ /^highway/) {
    getLaneTags($tag,$dat->{tags}{$tag});  
    }
  if ($tag =~ /^(ref|int_ref)/) {
    getLaneTags($tag,$dat->{tags}{$tag});  
    }
  }

for (my $sd= 0; $sd < scalar @showdirections; $sd++) {
  next if ($store->{$showdirections[$sd]});
  splice(@showdirections,$sd,1);
  }
  
calcNumbers();
duplicateTags();
correctDoubleLanes();
makeArrows();


my %signs = do "./signs_".$conf->{country}.".pl";

my $imgwidth   = ($conf->{0}{filledlanes}*$SIGNWIDTH+44);
my $imgheight  = ($conf->{0}{maxentries}*20+42);


#################################################
## Draw sign
#################################################  
my $lanecounter = 0;

foreach my $d (@showdirections) {
  $conf->{direction} = $d;
  next if $conf->{$d}{nothing};

  my $signheight = ($conf->{$d}{maxentries}*20+20);  
  
  my $lane = -1;
  foreach my $l (@{$store->{$d}}) {
    $lane++;
    next if $conf->{$d}{empty}[$lane];
    my $backcol  = getBackground($lane,0,'main');
    my $frontcol = getBackground($lane,0,'main','front');
    $image .= '<svg x="'.(10+$lanecounter*$SIGNWIDTH).'" y="10" width="'.($SIGNWIDTH+1).'" height="'.$signheight.'px" class="lane DEdefault">'."\n";
    $image .= '<rect width="100%" height="100%"  class="" style="fill:'.$backcol.';stroke:'.$frontcol.';" />'."\n";
    
    if($l->{'turn'}) {
      $image .= getArrow($lane);
      }
    
    my $entrypos = 0;
    my $pos = 10;
      $pos = 40 if $conf->{$d}{arrowpos}[$lane] eq 'left';
      $pos = 25 if $conf->{$d}{arrowpos}[$lane] eq 'center';
    $image .= '<g transform="translate('.$pos.' 20)">';

    if($conf->{$d}{numberdestto}[$lane]) {
      for(my $i = 0; $i < $conf->{$d}{numberdestto}[$lane];$i++) {
        my $tmp;
        $pos = 0;
        $image .= '<g transform="translate(0 '.$entrypos.')">';
        $image .= drawBackground($lane,$i,':to',$pos);
        
        $tmp = $l->{'destination:symbol:to'}[$i] if ($l->{'destination:symbol:to'});
        if ($tmp && $signs{$tmp}) {
          $image .= '<image xlink:href="'.$signs{$tmp}.'" width="18" height="18" transform="translate(0 -10)"/>';
          $pos += 18;
          }          

        if ($l->{'destination:ref:to'} && ($tmp = $l->{'destination:ref:to'}[$i])) {
          $image .= makeRef($pos,0,$tmp);
          $pos += 38;
          }
      
        $image .= drawText($lane,$i,':to',$pos);

        $image .= "</g>\n";  
        $entrypos+=20;
        }
      }
    if($conf->{$d}{numberdest}[$lane]) {  
      for(my $i = 0; $i < $conf->{$d}{numberdest}[$lane];$i++) {
        $pos = 0;
        my $tmp;
        $image .= '<g transform="translate(0 '.$entrypos.')">';
        $image .= drawBackground($lane,$i,'',$pos);
        
        if($l->{'destination:symbol'} && $conf->{$d}{numbersymbols}[$lane] == 0) {
          $tmp = $l->{'destination:symbol'}[$i]; 
          if ($tmp && $signs{$tmp}) {
            $image .= '<image xlink:href="'.$signs{$tmp}.'" width="18" height="18" transform="translate(0 -10)"/>';
            $pos += 20;
            }       
          }
          
        if ($conf->{$d}{orderedrefs}[$lane]  && $l->{'destination:ref'} && ($tmp = $l->{'destination:ref'}[$i])) {
          $image .= makeRef($pos,0,$tmp);
          $pos += 38;
          }          
         
        $image .= drawText($lane,$i,'',$pos);
        
        $image .= "</g>\n";  
        $entrypos+=20;
        }
      }
      
    $pos = 0;  
    if($conf->{$d}{numbersymbols}[$lane]) {
      for(my $i = 0; $i < $conf->{$d}{numbersymbols}[$lane];$i++) {
        my $tmp = $l->{'destination:symbol'}[$i] if ($l->{'destination:symbol'}); 
        if ($tmp && $signs{$tmp}) {
          $image .= '<g transform="translate('.$pos.' '.$entrypos.')">';
          $image .= '<image xlink:href="'.$signs{$tmp}.'" width="18" height="18" transform="translate(0 -10)"/>';
          $image .= "</g>\n";  
          $pos += 25;
          }       
        }
      $entrypos+=20;
      }
      
    $pos = 0;  
    if ($l->{'destination:ref'} || $l->{'destination:int_ref'}) {
      my @refs;
      push(@refs,@{$l->{'destination:ref'}})  if $l->{'destination:ref'} && $conf->{$d}{numberrefs}[$lane];
      push(@refs,@{$l->{'destination:int_ref'}})  if $l->{'destination:int_ref'};
      
      my $refcount = scalar @refs;
      for(my $i = 0;$i< $refcount; $i++) {
        $image .= makeRef($pos,$entrypos,$refs[$i]);
        $pos+=44;          
        }    
      $entrypos+=20;
      }
    $image .= '</g>';
    $image .= "</svg>\n";
    $lanecounter++;
    }
  $lanecounter += .1;  
  }

#################################################
## Duplicate none-lane tags if needed
#################################################  
sub duplicateTags {
  foreach my $d (@showdirections) {
    return if $conf->{$d}{totallanes} == 1;
    foreach my $t (keys %{$store->{$d}[0]}) {
      next if($store->{$d}[1]{$t});
      for (my $l=1; $l < scalar @{$store->{$d}};$l++) {
        push(@{$store->{$d}[$l]{$t}}, @{$store->{$d}[0]{$t}});
        }
      }
    }
    #TODO: Fill tags with less than correct number of entries with empty entries
#   foreach my $d (@showdirections) {
#     foreach my $l (@{$store->{$d}}) {
#       foreach my $t (keys %{$l}) {
#         if 
#         }
#       }
#     }
  }



#################################################
## Finish image output
#################################################    



$image .= "</svg>\n";
$image =~ s/%IMAGEWIDTH%/$imgwidth/g;
$image =~ s/%IMAGEHEIGHT%/$imgheight/g;
# $image =~ s/%SIGNHEIGHT%/$signheight/g;
print encode('utf-8',$image);
#  $error .= Dumper $conf;
#  $error .= Dumper $store;
# print '<pre>';
# print encode('utf-8',$error);
# print '</pre>';



#################################################
## Load and output file
#################################################    
sub  getFile {
  local $/ = undef;
  open FILE, $_[0] or die "Couldn't open file: $!";
  binmode FILE;
  my $t = <FILE>;
  close FILE;
  return $t;
  }  

  
#################################################
## Read and parse tags
#################################################    
sub getLaneTags {
  my ($k,$v) = @_;
  
  my $sk = $k;
     $sk =~ s/(:backward|:forward|:lanes)//g;
  my $direction = 1;
  if ($k =~ /:backward/) {$direction = -1;}
  
  $v =~ s/none//g;
  $v =~ s/none;//g;
  
  if($k =~ /:lanes/) {
    my @lanes = split('\|',$v,-1);
#     if ($direction == -1) { reverse @lanes;}
    my $i = 0;
    foreach my $l (@lanes) {
      my @tmp = split(';',$l,-1);
      $store->{$direction}[$i++]{$sk} = \@tmp;
      }
    }
  else {
    my @tmp = split(';',$v,-1);
    $store->{$direction}[0]{$sk} = \@tmp;
    }
  }

  
#################################################
## Determine number of lanes and number of entries per lane
#################################################    
sub calcNumbers {
#   $conf->{-1}{filledlanes} = 0;
#   $conf->{1}{filledlanes} = 0;

  foreach my $d (@showdirections) {
    my $maxentries = 0;
    my $lanenum = 0;
    foreach my $lane ( @{$store->{$d}}) {
      my @entries = (0,0,0);
      if (ref($lane) eq 'HASH') {
        foreach my $tag (keys %$lane) {
          my $cnt = scalar @{$lane->{$tag}};
          next if ($tag =~ /colour/);
          if($tag =~ /^destination.*ref.*:to/) {
            $entries[1] = $cnt if $entries[1] < $cnt;
            }          
          elsif($tag =~ /^destination.*:to/) {
            $entries[1] = $cnt if $entries[1] < $cnt;
            }
          elsif($tag =~ /^destination.*ref/ && $cnt) {
            $entries[2] = 1;
            $conf->{$d}{numberrefs}[$lanenum] += $cnt;
            }
          elsif($tag =~ /^destination/ && ! ($tag =~ /symbol/)) {
            $entries[0] = $cnt if $entries[0] < $cnt;
            }
          }
        }
      $conf->{$d}{numberrefs}[$lanenum] //= 0;  
      $conf->{$d}{numberdest}[$lanenum] = $entries[0];  
      $conf->{$d}{numberdestto}[$lanenum] = $entries[1];

      if($conf->{$d}{numberrefs}[$lanenum] == $conf->{$d}{numberdest}[$lanenum] && $conf->{$d}{numberdest}[$lanenum] > 1) {
        $conf->{$d}{numberrefs}[$lanenum] = 0;
        $entries[2] = 0;
        $conf->{$d}{orderedrefs}[$lanenum] = 1;
        }
      $conf->{$d}{entries}[$lanenum] = $entries[0] + $entries[1] + $entries[2];
      $maxentries = max($maxentries,$conf->{$d}{entries}[$lanenum]);
      $lanenum++;
      }
    $conf->{$d}{maxentries} = $maxentries;
    $conf->{$d}{totallanes} = scalar @{$store->{$d}};
    $conf->{$d}{filledlanes} = $conf->{$d}{totallanes};

    #Find number of single symbols
    $lanenum = 0;
    foreach my $lane ( @{$store->{$d}}) {
      if ($lane->{'destination:symbol'}) {
        if (scalar @{$lane->{'destination:symbol'}} != $conf->{$d}{numberdest}[$lanenum]) {
          $conf->{$d}{entries}[$lanenum] += 1;
          $conf->{$d}{numbersymbols}[$lanenum] = scalar @{$lane->{'destination:symbol'}};
          $conf->{$d}{maxentries} = max($maxentries,$conf->{$d}{entries}[$lanenum]);
          }
        }
      $lanenum++;  
      }
    $conf->{0}{totallanes} +=   $conf->{$d}{totallanes};
    $conf->{0}{filledlanes} +=   $conf->{$d}{filledlanes};
    $conf->{0}{maxentries} = max($conf->{$d}{maxentries} , $conf->{0}{maxentries});
    }
  }

  
sub correctDoubleLanes {
  foreach my $d (@showdirections) {
    my $lanenum = scalar (@{$store->{$d}}) - 1;
    foreach my $lane ( @{$store->{$d}}) {
      $conf->{$d}{multilanes}[$lanenum] //= 0;
      if ($conf->{$d}{entries}[$lanenum] == 0)   {
        $conf->{$d}{empty}[$lanenum] = 1;
        $conf->{$d}{filledlanes}--;
        $conf->{0}{filledlanes}--; 
        } 
      elsif ($lanenum > 0 && Compare($store->{$d}[$lanenum],$store->{$d}[$lanenum-1],{ ignore_hash_keys => [qw(ref int_ref)] })) {
        $conf->{$d}{empty}[$lanenum] = 1;
        $conf->{$d}{filledlanes}--;
        $conf->{0}{filledlanes}--;
        $conf->{$d}{multilanes}[$lanenum-1] = 1+($conf->{$d}{multilanes}[$lanenum]);
        }
      else {
        $conf->{$d}{empty}[$lanenum] = 0;
        }
      $lanenum--;  
      }
    $conf->{$d}->{nothing} = 1 if $conf->{$d}{filledlanes} == 0;
    }   
  }
  
#################################################
## Generate a ref number
#################################################   
sub makeRef {
  my ($xpos,$entrypos,$text) = @_;
  $xpos += 17;
  my $class = '';
  
  my $tcol = 'black';
  my $bcol = 'white';
  
  return if $text =~ /^\s*$/;
  if($conf->{country} eq 'DE') {
    if ($text =~ /^\s*A[\s\d]+/) { $tcol = 'white'; $bcol = '#2568aa';}
    if ($text =~ /^\s*B[\s\d]+/) { $tcol = 'black'; $bcol = '#f0e060';}
    if ($text =~ /^\s*E\s+/) { $tcol = 'white'; $bcol = '#007f00';}
    }
  
  if($conf->{country} eq 'DE') {
    $text =~ s/^\s*A\s+//;
    $text =~ s/^\s*B\s+//;
    $text =~ s/\s//g;
    }
  
  my $o = "";
  $o .= '<g  transform="translate('.$xpos.' '.$entrypos.')" class="'.$class.'">';
  $o .= '<rect class="destinationrefs" x="-15" y="-9" width="30" height="16" rx="2" style="fill:'.$bcol.';stroke:'.$tcol.'"/>';
  $o .= '<text class="destinationreftext destinationrefs" style="fill:'.$tcol.'">'
            .$text.'</text>'."\n";
  $o .= '</g>';
  return $o;
}
  
#################################################
## Select direction of way to draw
#################################################    
sub setDirection {
  if (defined $q->param('direction') && ($q->param('direction') == 1 || $q->param('direction') == -1) ) {
    return $q->param('direction');
    }
  if( ! defined $store->{1} && defined $store->{-1}) {
    return -1;
    }
#   if(defined $store->{1} && defined $store->{-1} && scalar keys %{$store->{-1}} > scalar keys %{$store->{1}}) {
#     return -1;
#     }
  return 1;
  }

  
#################################################
## Draw arrows
#################################################     
sub getArrow {
  my $lane  = shift @_;
  my $type  = shift @_;
  my $entry = shift @_ // 0;
  my $height = 30;
  my $d = $conf->{direction};
  my $o = '';

  if ($conf->{$d}{maxentries} == 1) {
    $height = 20;
    }
  
  my $col = getBackground($lane,$entry,'main','front');
  if(defined $type && $type eq 'arrow') {
    #TODO: arrows
    }
  elsif ($conf->{$d}{arrowpos}[$lane] eq 'left') {  
    my $deg = $conf->{$d}{arrows}[$lane][0];
    $o .= '<use xlink:href="#arrow" transform="translate(20 '.$height.') rotate('.$deg.' 0 0)" style="stroke:'.$col.';"/>';
    }
  elsif ($conf->{$d}{arrowpos}[$lane] eq 'right') {
    my $deg = $conf->{$d}{arrows}[$lane][0];
    $o .= '<use xlink:href="#arrow" transform="translate('.($SIGNWIDTH-20).' '.$height.') rotate('.$deg.' 0 0)" style="stroke:'.$col.';"/>';    
    }
  elsif ($conf->{$d}{arrowpos}[$lane] eq 'center') {
    $height = 2+$conf->{$d}{maxentries}*20;
    my $offset = -20*(scalar @{$conf->{$d}{arrows}[$lane]} -1);
    foreach my $deg (@{$conf->{$d}{arrows}[$lane]}) {
      $o .= '<use xlink:href="#arrow" transform="translate('.($SIGNWIDTH/2+$offset).' '.$height.') rotate('.$deg.' 0 0)" style="stroke:'.$col.';"/>';
      $offset += 40;
      }
    }

  return $o;
  }

#################################################
## Define arrows per lane and positions
#################################################   
sub makeArrows {
  foreach my $d (@showdirections) {
    next if $conf->{$d}{nothing};
    my $multiple = 0;
    for(my $l=0; $l < scalar @{$store->{$d}}; $l++) {
      my @deg;
      foreach my $ml(0..$conf->{$d}{multilanes}[$l]) {
        foreach my $arrows (@{$store->{$d}[$l+$ml]{'turn'}}) {
          if ($arrows =~ /sharp_left/)     {push(@deg,135);}
          if ($arrows =~ /^\s*left/)       {push(@deg,180);}
          if ($arrows =~ /slight_left/)    {push(@deg,225);}
          if ($arrows =~ /through/)        {push(@deg,270);}
          if ($arrows =~ /slight_right/)   {push(@deg,-45);}
          if ($arrows =~ /^\s*right/)      {push(@deg,-360);}
          if ($arrows =~ /sharp_right/)    {push(@deg,45);}
        }
      }
      $conf->{$d}{arrows}[$l] = \@deg;
      if ($conf->{$d}{multilanes}[$l]){
        while ($conf->{$d}{multilanes}[$l] >= scalar @deg) {
          push(@deg,270) ;
          }
        }
      if(scalar @deg > 1) {$multiple = 1;}
      }
    for(my $l=0; $l < scalar @{$conf->{$d}{arrows}}; $l++) {
      if((not defined $conf->{$d}{arrows}[$l]) || scalar @{$conf->{$d}{arrows}[$l]} == 0) {
        $conf->{$d}{arrowpos}[$l] = 'none';
        }
      elsif ($multiple == 1 || $conf->{$d}{totallanes} == 1) {
        $conf->{$d}{arrowpos}[$l] = 'center';
        $conf->{$d}{entries}[$l] += 1;
        $conf->{$d}{maxentries} = max($conf->{$d}{maxentries}, $conf->{$d}{entries}[$l]);
        $conf->{0}{maxentries} = max($conf->{$d}{maxentries} , $conf->{0}{maxentries});
        }
      elsif ($conf->{$d}{arrows}[$l][0] < 90){
        $conf->{$d}{arrowpos}[$l] = 'right';
        }
      else {
        $conf->{$d}{arrowpos}[$l] ='left';
        }
      }
    for my $type ('',':to') {
      for(my $l=0; $l < scalar @{$store->{$d}}; $l++) {
        my @deg;
        next unless $store->{$d}[$l]{'destination:arrow'.$type};
        foreach my $arrows (@{$store->{$d}[$l]{'destination:arrow'.$type}}) {
          my @tmp = split(';',$arrows,0);
          foreach my $arrow (@tmp) {
            if    ($arrow =~ /sharp_left/)     {push(@deg,135);}
            elsif ($arrow =~ /^\s*left/)       {push(@deg,180);}
            elsif ($arrow =~ /slight_left/)    {push(@deg,225);}
            elsif ($arrow =~ /through/)        {push(@deg,270);}
            elsif ($arrow =~ /slight_right/)   {push(@deg,-45);}
            elsif ($arrow =~ /^\s*right/)      {push(@deg,-360);}
            elsif ($arrow =~ /sharp_right/)    {push(@deg,45);}
            else                               {push(@deg,'-');}
            }
          }
        $conf->{$d}{'arrowtag'.$type}[$l] = \@deg;
        }
      }
    }
  }
  
#################################################
## Get colours
#################################################   
sub getBackground {
  #Lane, entry number, (':to','main',''), ('front','back','ref');
  my ($lane,$i,$type,$part) = @_;
     $part //= 'back';
     $type //= '';
  my $col = "";
  my $d = $conf->{direction};
  
  if($type eq 'main') {
    if ($store->{$d}[$lane]{'destination:colour'} && scalar $store->{$d}[$lane]{'destination:colour'} == 1) {  
      $col = $store->{$d}[$lane]{'destination:colour'}[0]  if $part eq 'back';
      $col = 'black'  if $part eq 'front';
      }
    else {
      if ($conf->{country} eq 'DE') {
        if (($store->{$d}[$lane]{'destination:ref'} && $store->{$d}[$lane]{'destination:ref'}[0] =~ /^A\s/) || 
            ($store->{$d}[$lane]{'ref'} && $store->{$d}[$lane]{'ref'}[0] =~ /^A\s/) ||
            ($store->{$d}[$lane]{'highway'}[0] =~ /^motorway/)) {
          $col = "#2568aa" if $part eq 'back'; 
          $col = 'white'   if $part eq 'front';
          }
        else {
          $col = "#f0e060" if $part eq 'back'; 
          $col = 'black'   if $part eq 'front';
          }
        }
      }
    }
  if($type eq '' || $type eq ':to') {
    if ($store->{$d}[$lane]{'destination:colour'.$type} && $store->{$d}[$lane]{'destination:colour'.$type}[$i]) {  
      $col = $store->{$d}[$lane]{'destination:colour'.$type}[$i]  if $part eq 'back';
      $col = bestTextColor($store->{$d}[$lane]{'destination:colour'.$type}[$i])  if $part eq 'front';
      }
    else {
      if ($conf->{country} eq 'DE' && $type eq ':to') {
        if (($store->{$d}[$lane]{'destination:ref:to'} && $store->{$d}[$lane]{'destination:ref:to'}[$i] =~ /^A\s/)
            || ($store->{$d}[$lane]{'destination:symbol:to'} && $store->{$d}[$lane]{'destination:symbol:to'}[$i] eq 'motorway')) {
          $col = "#2568aa" if $part eq 'back'; 
          $col = 'white'   if $part eq 'front';
          }
        }
      }      
    }
  if( $col eq '' && $part eq 'front') {
    $col = bestTextColor(getBackground($lane,0,'main','back'));
    }
  $col = getRGBColor($col);  
  return $col;
}


sub bestTextColor {
  my $col = shift @_;
  $col = getRGBColor($col);
  my ($red,$green,$blue) = $col =~ /(\w\w)(\w\w)(\w\w)/;
  return 'black' if (hex($red)*0.299 + hex($green)*0.587 + hex($blue)*0.114) > 186;
  return 'white';
  }
  
sub drawBackground {
  my ($lane,$i,$type,$pos) = @_;
  my $image = '';
  my $background = getBackground($lane,$i,$type,'back');
  if($background) {
    $image .= '<rect y="-11" x="-2" width="'.($SIGNWIDTH-42).'" height="20"  class="bg" style="fill:'.$background.';" />'."\n";
    }
  return $image;
  }
  
sub drawText {
  my ($lane,$i,$type,$pos) = @_;
     $type //= '';
  my $image = ''; 
  my $d = $conf->{direction};

  if($store->{$d}[$lane]{'destination'.$type}) {  
    my $text =  $store->{$d}[$lane]{'destination'.$type}[$i];  
    my $tcol = getBackground($lane,$i,$type,'front');
    $image .= '<g transform="translate('.$pos.' 0)"><text class="resizeme" datapos="'.$pos.'" style="fill:'.$tcol.'">'.$text.'</text></g>'."\n";
    }
  return $image;
  }

  
 
sub getRGBColor {
my @names  = ('aliceblue','antiquewhite','aqua','aquamarine','azure','beige','bisque','black','blanchedalmond','blue',
        'blueviolet','brown','burlywood','cadetblue','chartreuse','chocolate','coral','cornflowerblue','cornsilk',
        'crimson','cyan','darkblue','darkcyan','darkgoldenrod','darkgray','darkgrey','darkgreen','darkkhaki',
        'darkmagenta','darkolivegreen','darkorange','darkorchid','darkred','darksalmon','darkseagreen',
        'darkslateblue','darkslategray','darkslategrey','darkturquoise','darkviolet','deeppink','deepskyblue',
        'dimgray','dimgrey','dodgerblue','firebrick','floralwhite','forestgreen','fuchsia','gainsboro','ghostwhite',
        'gold','goldenrod','gray','grey','green','greenyellow','honeydew','hotpink','indianred','indigo','ivory',
        'khaki','lavender','lavenderblush','lawngreen','lemonchiffon','lightblue','lightcoral','lightcyan',
        'lightgoldenrodyellow','lightgray','lightgrey','lightgreen','lightpink','lightsalmon','lightseagreen',
        'lightskyblue','lightslategray','lightslategrey','lightsteelblue','lightyellow','lime','limegreen',
        'linen','magenta','maroon','mediumaquamarine','mediumblue','mediumorchid','mediumpurple','mediumseagreen',
        'mediumslateblue','mediumspringgreen','mediumturquoise','mediumvioletred','midnightblue','mintcream',
        'mistyrose','moccasin','navajowhite','navy','oldlace','olive','olivedrab','orange','orangered','orchid',
        'palegoldenrod','palegreen','paleturquoise','palevioletred','papayawhip','peachpuff','peru','pink','plum',
        'powderblue','purple','rebeccapurple','red','rosybrown','royalblue','saddlebrown','salmon','sandybrown',
        'seagreen','seashell','sienna','silver','skyblue','slateblue','slategray','slategrey','snow','springgreen',
        'steelblue','tan','teal','thistle','tomato','turquoise','violet','wheat','white','whitesmoke','yellow',
        'yellowgreen');
my @colors = ('f0f8ff','faebd7','00ffff','7fffd4','f0ffff','f5f5dc','ffe4c4','000000','ffebcd','2568aa','8a2be2',
        'a52a2a','deb887','5f9ea0','7fff00','d2691e','ff7f50','6495ed','fff8dc','dc143c','00ffff','00008b','008b8b','b8860b',
        'a9a9a9','a9a9a9','006400','bdb76b','8b008b','556b2f','ff8c00','9932cc','8b0000','e9967a','8fbc8f','483d8b','2f4f4f',
        '2f4f4f','00ced1','9400d3','ff1493','00bfff','696969','696969','1e90ff','b22222','fffaf0','228b22','ff00ff','dcdcdc',
        'f8f8ff','ffd700','daa520','808080','808080','008000','adff2f','f0fff0','ff69b4','cd5c5c','4b0082','fffff0','f0e68c',
        'e6e6fa','fff0f5','7cfc00','fffacd','add8e6','f08080','e0ffff','fafad2','d3d3d3','d3d3d3','90ee90','ffb6c1','ffa07a',
        '20b2aa','87cefa','778899','778899','b0c4de','ffffe0','00ff00','32cd32','faf0e6','ff00ff','800000','66cdaa','0000cd',
        'ba55d3','9370db','3cb371','7b68ee','00fa9a','48d1cc','c71585','191970','f5fffa','ffe4e1','ffe4b5','ffdead','000080',
        'fdf5e6','808000','6b8e23','ffa500','ff4500','da70d6','eee8aa','98fb98','afeeee','db7093','ffefd5','ffdab9','cd853f',
        'ffc0cb','dda0dd','b0e0e6','800080','663399','ff0000','bc8f8f','4169e1','8b4513','fa8072','f4a460','2e8b57','fff5ee',
        'a0522d','c0c0c0','87ceeb','6a5acd','708090','708090','fffafa','00ff7f','4682b4','d2b48c','008080','d8bfd8','ff6347',
        '40e0d0','ee82ee','f5deb3','ffffff','f5f5f5','f0e060','9acd32');
  my $col = shift @_;
  if ($col =~ /^#([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])$/) {
    return "#$1$1$2$2$3$3";
    }
  if ($col =~ /^#([0-9a-fA-F]){6}$/) {
    return $col;
    }
  $col = lc($col);  
  for (my $i = 0; $i < scalar @names;$i++) {
    if ($col eq $names[$i]) { 
      return '#'.$colors[$i];
      }
    }
#   return $col; #leave as is  
  }
  
  
  
