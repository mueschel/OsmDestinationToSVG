#!/usr/bin/perl
use CGI ':standard  -debug';
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
use List::Util qw(min max sum);
$Data::Dumper::Sortkeys = 1;

my $SIGNWIDTH = 220;

my $q = CGI->new;

my $data = $q->param('POSTDATA');
my $out;
my $store; #processed tags
our $conf;  #calculated data like number of lanes
my $image;
my $topimage = "";
our $error = "";
# $image = "Content-Type: image/svg+xml; charset=utf-8\r\n".
#          "Access-Control-Allow-Origin: *\r\n\r\n";
$image = "Content-Type: text/text; charset=utf-8\r\n".
         "Access-Control-Allow-Origin: *\r\n\r\n";

$out =   "Content-Type: text/text; charset=utf-8\r\n".
         "Access-Control-Allow-Origin: *\r\n\r\n";
$image .= getFile("_head.svg"); #TODO make country specific headers

unless($data) {
  print $out;
  print "No valid data received\n\n\n";
  exit 1;
  }


require "./colorcodes.pl";

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
# if($t == 1 || $t == -1) {
#   $showdirections[0] = $t;
#   }
# else {
  $showdirections[0]=1; 
  $showdirections[1]=-1;
#   }

$t = $dat->{'country'};  
if($t =~ /^[A-Z][A-Z]$/) {
  $conf->{country} = $t;
  }
else {
  $conf->{country} = 'DE'
  };  

if ($dat->{tags}{'oneway'} eq 'yes')   {
  $conf->{oneway} = 1;
  }
  
foreach my $tag (keys %{$dat->{tags}}) {
  if ($tag =~ /^destination/) {
    getLaneTags($tag,$dat->{tags}{$tag});
    }
  if ($tag =~ /^colour/) {
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

#################################################
## Define order and style of signs
#################################################    
my @order = ('to','dest','symbol','ref','country');
my @pinline = (0,0,0,0,0,0,0,0,0,0);
my @bottom  = (0,0,0,0,0,0,0,0,0,0);

@order    = ('country','to','dest','symbol','ref') if($conf->{country} eq 'DE');
@pinline  = ( 0,        0,   0,     0,       0)    if($conf->{country} eq 'DE');
@bottom   = ( 0,        1,   0,     0,       1)    if($conf->{country} eq 'DE');

@order    = ('country','symbol','ref','to','dest') if($conf->{country} eq 'AT');
@pinline  = ( 0,        1,       0,    0,   0)     if($conf->{country} eq 'AT');
@bottom   = ( 0,        0,       0,    1,   0)     if($conf->{country} eq 'AT');

@order    = ('country','symbol','ref','dest','to') if($conf->{country} eq 'PT');
@pinline  = ( 0,        0,   0,     0,       0)    if($conf->{country} eq 'PT');
@bottom   = ( 0,        0,   0,     0,       0)    if($conf->{country} eq 'PT');

@order    = ('country','ref','to','dest','symbol') if($conf->{country} eq 'FR');
@pinline  = ( 0,         0,   0,     0,       0)   if($conf->{country} eq 'FR');
@bottom   = ( 0,         0,   0,     0,       0)   if($conf->{country} eq 'FR');

@order    = ('country','to','dest','symbol','ref') if($conf->{country} eq 'SR');
@pinline  = ( 0,        0,   0,     0,       0)    if($conf->{country} eq 'SR');
@bottom   = ( 0,        1,   0,     0,       1)    if($conf->{country} eq 'SR');

my $allowstack = 0;


#################################################
## Process data
#################################################    
checkSplitLanes();
calcNumbers();
duplicateTags();
calcNumbers();
correctDoubleLanes();
makeArrows();

my %signs = do "./signs_".$conf->{country}.".pl";

# my $imgwidth   = ($conf->{0}{filledlanes}*$SIGNWIDTH+44);
# my $imgheight  = ($conf->{0}{maxentries}*20+42);
#TODO dont use maxentries, but max pos after each lane

  my $sizes={maxheight => 0,
            maxwidth  => 0,
            currentx  => 10,
            currenty  => 10,
  };

#################################################
## Draw sign
#################################################  
my $lanecounter = 0;
my $hasarrows = 0;
my $hasbottomline = 0;

foreach my $d (@showdirections) {
  $conf->{direction} = $d;
  next if $conf->{$d}{nothing};

  
#   my $signheight = ($conf->{$d}{maxentries}*20+20);  
  
  my $lane = -1;
  foreach my $l (@{$store->{$d}}) {
    $lane++;
    my $newline = 0;
    next if ($conf->{$d}{empty}[$lane] && $conf->{$d}{splitlane}[$lane] == 0);
    my $backcol  = getBackground($lane,0,'main','back');
    my $frontcol = getBackground($lane,0,'main','front');
    if($conf->{$d}->{splitlane}[$lane]) {
      $topimage .= '<svg x="'.(10+$lanecounter*$SIGNWIDTH-$SIGNWIDTH/8).'" y="10" width="'.($SIGNWIDTH/4+1).'" height="%SIGNHEIGHT%" class="lane '.$conf->{country}.'default">'."\n";
      $topimage .= getArrow($lane,'split') if($l->{'turn'});
      #$image .= '<rect width="100%" height="100%"  class="" style="fill:'.$backcol.';stroke:'.$frontcol.';" />'."\n";
#       $topimage .= '</g>';
      $topimage .= "</svg>\n";
      next;
      }

    if ($allowstack && ($conf->{$d}{arrowpos}[$lane] eq 'left' ||$conf->{$d}{arrowpos}[$lane] eq 'right')) {
      $image .= '<svg  x="10" y="'.$sizes->{currenty}.'" width="'.($SIGNWIDTH+1).'" height="%SIGNHEIGHT%" class="lane '.$conf->{country}.'default">'."\n";
      }
    else {
      $image .= '<svg  x="'.(10+$lanecounter*$SIGNWIDTH).'" y="10" width="'.($SIGNWIDTH+1).'" height="%SIGNHEIGHT%" class="lane '.$conf->{country}.'default">'."\n";
      }
    $image .= '<rect width="100%" height="100%"  class="" style="fill:'.$backcol.';stroke:'.$frontcol.';" />'."\n";
    if($l->{'turn'}) {
      $image .= getArrow($lane);
      }
          
    my $entrypos = 0;
    my $pos = 10;
       $pos = 40 if $conf->{$d}{arrowpos}[$lane] eq 'left';
       $pos = 25 if $conf->{$d}{arrowpos}[$lane] eq 'center';
    $image .= '<g transform="translate('.$pos.' 20)">';
    $hasarrows = 1 if $conf->{$d}{arrowpos}[$lane] eq 'center';
    
    $pos = 0;
    foreach my $p (0..scalar @order-1) {    
      my $part = $order[$p];
      my $inline = $pinline[$p];
      my $bottomline = $bottom[$p];
#          $bottomline = 0 if $conf->{$d}{arrowpos}[$lane] ne 'center';
      
#Draw DESTINATION:TO        
      if ($part eq 'to') {
        if($conf->{$d}{numberdestto}[$lane]) {
          for(my $i = 0; $i < $conf->{$d}{numberdestto}[$lane];$i++) {
            my $tmp;
            $image .= '<g transform="translate(0 '.$entrypos.')">'."\n";
            $image .= drawBackground($lane,$i,':to',$pos);

            if($l->{'destination:arrow:to'} && $conf->{$d}{'arrowtag:to'}[$lane] && scalar @{$conf->{$d}{'arrowtag:to'}[$lane]}) {
              $image .= getArrow($lane,'arrowto',$i);
              $pos += 25;
              }

            $tmp = $l->{'destination:symbol:to'}[$i] if ($l->{'destination:symbol:to'});
            if ($tmp) {
              foreach my $t (split(',',$tmp)) {
                $t = lc($t);
                $t = "notfound" unless ($signs{$t});
                $image .= '<image href="'.$signs{$t}.'" width="18" height="18" transform="translate('.$pos.' -10)"/>'."\n";
                $pos += 20;
                }
              }          

            if ($conf->{$d}{orderedrefto}[$lane]  &&  $l->{'destination:ref:to'} && ($tmp = $l->{'destination:ref:to'}[$i])) {
              $image .= makeRef($pos,0,$tmp);
              $pos += 38;
              }
            if ($conf->{$d}{orderedrefto}[$lane]  &&  $l->{'destination:int_ref:to'} && ($tmp = $l->{'destination:int_ref:to'}[$i])) {
              $image .= makeRef($pos,0,$tmp);
              $pos += 38;
              }

            $image .= drawText($lane,$i,':to',$pos);
            if($l->{'destination:distance:to'}) {
              if (existEntryI($l,'destination:distance:to',$i)) {
                $image .= drawDistance($lane,$i,':to',$pos);
                }
              }
            $image .= "</g>\n";  
            $entrypos+=20;
            $pos = 0;
            }
          $image .= drawDivider($entrypos-20,$lane) if $bottomline;            
          $entrypos += 10;  
          }
        }
        
#Draw DESTINATION
      if($part eq 'dest') {  
        if($conf->{$d}{numberdest}[$lane]) {  
          for(my $i = 0; $i < $conf->{$d}{numberdest}[$lane];$i++) {
            my $tmp;
            $image .= '<g transform="translate(0 '.$entrypos.')">'."\n";
            $image .= drawBackground($lane,$i,'',$pos);
            
            if($l->{'destination:arrow'} && $conf->{$d}{arrowtag}[$lane] && scalar @{$conf->{$d}{arrowtag}[$lane]}) {
              unless(scalar @{$conf->{$d}{arrows}} <= 1 && $conf->{$d}{arrowtag}[$lane][$i] eq $conf->{$d}{arrows}[0]) {
                if($conf->{$d}{arrowtag}[$lane][$i+1] && $conf->{$d}{arrowtag}[$lane][$i] != $conf->{$d}{arrowtag}[$lane][$i+1]) {
                  $image .= drawDivider(0,$lane);
                  $entrypos += 10;
                  }
                $image .= getArrow($lane,'arrow',$i);
                $pos += 25;
                }
              }
 
            if($l->{'destination:symbol'} && $conf->{$d}{numbersymbols}[$lane] == 0) {
              $tmp = $l->{'destination:symbol'}[$i]; 
              if ($tmp) {
                foreach my $t (split(',',$tmp)) {
                  $t = lc($t);
                  $t = "notfound" unless ($signs{$t});
                  $image .= '<image href="'.$signs{$t}.'" width="18" height="18" transform="translate('.$pos.' -10)"/>'."\n";
                  $pos += 20;
                  }
                }
              }
            if($l->{'destination:country'} && $conf->{$d}{numbercountries}[$lane] == 0) {
              $tmp = $l->{'destination:country'}[$i]; 
              if ($tmp) {
                $image .= '<ellipse class="country" cx="9" cy="0" rx="12" ry="8" style="fill:white;stroke:black;"  transform="translate('.$pos.' 0)"/>'."\n";
                $image .= '<g transform="translate('.($pos+9).' 0)">'."\n".'<text class="country" datapos="'.$pos.'" style="fill:black">'.$tmp.'</text>'."\n".'</g>'."\n";

                $pos += 22;
                }       
              }              
              
            if ($conf->{$d}{orderedrefs}[$lane]  && $l->{'destination:ref'} && ($tmp = $l->{'destination:ref'}[$i])) {
              $image .= makeRef($pos,0,$tmp,$l,$i);
              $pos += 38;
              }          
            if ($conf->{$d}{orderedrefs}[$lane]  && $l->{'destination:int_ref'} && ($tmp = $l->{'destination:int_ref'}[$i])) {
              $image .= makeRef($pos,0,$tmp,$l,$i);
              $pos += 38;
              }           
            $image .= drawText($lane,$i,'',$pos);
            if($l->{'destination:distance'}) {
              if (existEntryI($l,'destination:distance',$i)) {
                $image .= drawDistance($lane,$i,'',$pos);
                }
              }
            $image .= "</g>\n";  
            $entrypos+=20;
            $pos = 0;           
            }
          }
        }
#Draw SYMBOLS
      if ($part eq 'symbol') {    
        if($conf->{$d}{numbersymbols}[$lane]) {
          for(my $i = 0; $i < $conf->{$d}{numbersymbols}[$lane];$i++) {
            my $tmp = $l->{'destination:symbol'}[$i] if ($l->{'destination:symbol'}); 
            if ($tmp) {
              foreach my $t (split(',',$tmp)) {
                $t = lc($t);
                $t = "notfound" unless ($signs{$t});
                $image .= '<g transform="translate('.$pos.' '.$entrypos.')">'."\n";
                $image .= '<image href="'.$signs{$t}.'" width="18" height="18" transform="translate(0 -10)"/>'."\n";
                $image .= "</g>\n";  
                $pos += 25;
                }  
              $newline = 1;
              }       
            }
          unless ($inline && $pos < 75) {
            $pos = 0 ;  
            $entrypos += 20;
            $newline = 0;
            }
          }
        }
#Draw COUNTRY
      if ($part eq 'country') {    
        if($conf->{$d}{numbercountries}[$lane]) {
          for(my $i = 0; $i < $conf->{$d}{numbercountries}[$lane];$i++) {
            my $tmp = $l->{'destination:country'}[$i] if ($l->{'destination:country'}); 
            if ($tmp ) {
              $image .= '<g transform="translate('.$pos.' '.$entrypos.')">'."\n";
                $image .= '<ellipse class="country" cx="9" cy="0" rx="12" ry="8" style="fill:white;stroke:black;"  transform="translate('.$pos.' 0)"/>'."\n";
                $image .= '<g transform="translate('.($pos+9).' 0)">'."\n".'<text class="country" datapos="'.$pos.'" style="fill:black">'.$tmp.'</text>'."\n".'</g>'."\n";
              $image .= "</g>\n";  
              $pos += 25;
              $newline = 1;
              }       
            }
          unless ($inline && $pos < 75) {
            $pos = 0 ;  
            $entrypos += 20;
            $newline = 0;
            }
          }
        }        
#Draw REF        
      if ($part eq 'ref') {  
        if ($conf->{$d}{numberrefs}[$lane] || $conf->{$d}{numberintrefs}[$lane] || $conf->{$d}{numberrefto}[$lane]) {
          my @refs;
          push(@refs,@{$l->{'destination:ref:to'}})   if $l->{'destination:ref:to'} && $conf->{$d}{numberrefto}[$lane];
          push(@refs,@{$l->{'destination:ref'}})      if $l->{'destination:ref'} && $conf->{$d}{numberrefs}[$lane];
          push(@refs,@{$l->{'destination:int_ref'}})  if $l->{'destination:int_ref'} && $conf->{$d}{numberintrefs}[$lane];
          
          my $refcount = scalar @refs;
          for(my $i = 0;$i< $refcount; $i++) {
            if($bottomline) {
              $image .= makeRef($pos,'%BOTTOMLINE%',$refs[$i]);
              $hasbottomline = 1;
              }
            else {
              $image .= makeRef($pos,$entrypos,$refs[$i]);
              }
            $pos+=44;          
            $newline = 1;
            }
          if($hasbottomline && $refcount == 1) {
#             $hasarrows = 0;
              $entrypos -= 20;
            }
          unless ($inline && $pos < 75) {
            $pos = 0 ;  
            $entrypos += 20;
            $newline = 0;
            }
          }
        }
        
    
      if(!$inline && $newline) {
        $entrypos+=20;
        $pos = 0;
        $newline = 0;
        }
      }
    $image .= "</g>\n</svg>\n";
    $lanecounter++;    
    $sizes->{maxheight} = max($sizes->{maxheight},$entrypos);
    $sizes->{currenty}  += $entrypos+20;
    }
  $lanecounter += .1;  
  }

#################################################
## Finish image output
#################################################
# $hasarrows *= $hasbottomline;
# $error .= $hasarrows.$hasbottomline;
$hasbottomline = 0 if $hasarrows;
my $imgheight  = $sizes->{currenty}+20+$hasarrows*30+$hasbottomline*20;
my $imgwidth   = $lanecounter*$SIGNWIDTH+10;
my $signheight = $sizes->{maxheight}+19+$hasarrows*40+$hasbottomline*20;
my $bottomline = $sizes->{maxheight};#-20+$hasarrows*30;
my $arrowpos   = $sizes->{maxheight}+$hasarrows*40; #+$hasbottomline*10;

$image .= "$topimage</svg>\n";
$image =~ s/%IMAGEWIDTH%/$imgwidth/g;
$image =~ s/%IMAGEHEIGHT%/$imgheight/g;
$image =~ s/%SIGNHEIGHT%/$signheight/g;
$image =~ s/%BOTTOMLINE%/$bottomline/g;
$image =~ s/%ARROWPOS%/$arrowpos/g;

print encode('utf-8',$image);

# $error .= Dumper $conf;
# $error .= Dumper $store;
print '<pre>';
print encode('utf-8',$error);
print '</pre>';





sub drawDivider {
  my $pos = shift @_ // 0;
  my $lane = shift @_ // 0;
  my $o = '';
  my $col = getBackground($lane,0,'main','front');
  $o .= '<rect y="'.(16+$pos).'" x="-40" width="'.($SIGNWIDTH+40).'" height="1"  class="bg" style="fill:'.$col.';" />'."\n";
  return $o;
  }
  
#################################################
## Duplicate non-lane tags if needed
#################################################  
sub duplicateTags {
  foreach my $d (@showdirections) {
    
#if all arrows are identical, then push to turn      
    foreach my $l (0..$conf->{$d}{totallanes}-1) {        
      if($store->{$d}[$l]{'destination:arrow'}) {
        if (allsameorempty(@{$store->{$d}[$l]{'destination:arrow'}})) {
#TODO Should show like turn, but only if not in a split plane        
#           push(@{$store->{$d}[$l]{'turn'}},$store->{$d}[$l]{'destination:arrow'}[0]);
          @{$store->{$d}[$l]{'destination:arrow'}} = ();
          }
        else {
           @{$store->{$d}[$l]{'turn'}} = ();
          }
        }
      }
      
#colour:back is a synonym for colour
    foreach my $l (0..$conf->{$d}{totallanes}-1) {
      if($store->{$d}[$l]{'destination:colour:back'}) {
        $store->{$d}[$l]{'destination:colour'} = $store->{$d}[$l]{'destination:colour:back'};
        }
      if($store->{$d}[$l]{'colour:back'}) {
        $store->{$d}[$l]{'destination:colour'} = $store->{$d}[$l]{'colour:back'};
        }
      if($store->{$d}[$l]{'colour:ref'}) {
        $store->{$d}[$l]{'destination:colour:ref'} = $store->{$d}[$l]{'colour:ref'};
        }
      if($store->{$d}[$l]{'destination:colour:back:to'}) {
        $store->{$d}[$l]{'destination:colour:to'} = $store->{$d}[$l]{'destination:colour:back:to'};
        }
      if($store->{$d}[$l]{'colour:ref:to'}) {
        $store->{$d}[$l]{'destination:colour:ref:to'} = $store->{$d}[$l]{'colour:ref:to'};
        }
      }
      
#Treat all colour identical as if there is just a single one
    foreach my $l (0..$conf->{$d}{totallanes}-1) {
      next if $conf->{country} eq 'GR'; #keep blue background on all white signs
      foreach my $ta (qw(destination:colour destination:colour:to colour:back colour:text)) {
        if($store->{$d}[$l]{$ta} && (scalar @{$store->{$d}[$l]{$ta}}) >= 1) {
          if (allsame(@{$store->{$d}[$l]{$ta}})) {
            @{$store->{$d}[$l]{$ta}} = ($store->{$d}[$l]{$ta}[0]);
            }
          }
        }
      }


    next if $conf->{$d}{totallanes} == 1;
    foreach my $t (keys %{$store->{$d}[0]}) {
      next if($store->{$d}[1]{$t});
      for (my $l=1; $l < scalar @{$store->{$d}};$l++) {
#         $error .= $l.$t."<br>";
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

sub allsame {
  my @arr = @_;
  return 1 if scalar @arr <= 1 ;
  for my $i (1..((scalar @arr) -1)) {
    return 0 if $arr[$i-1] ne $arr[$i];
    }
  return 1;  
  }


sub allsameorempty {
  my @arr = @_;

  return 1 if scalar @arr <= 1 ;
  my $last = $arr[0];
  for my $i (1..((scalar @arr) -1)) {
    next if $arr[$i] eq '';
    return 0 if $last ne $arr[$i];
    $last = $arr[$i];
    }
  return 1;  
  }
  


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
  my $direction = $conf->{oneway} // 0;
  if ($k =~ /:both_ways/) {next;}
  if ($k =~ /:backward/) {$direction = -1;}
  if ($k =~ /:forward/) {$direction = 1;}
  
  $v =~ s/(^|;|\|)\s*none\s*(?=$|;|\|)/$1/g;
  $v =~ s/(^|;|\|)\s+/$1/g;
  $v =~ s/\s+($|;|\|)/$1/g;
  
  if($k =~ /:lanes/) {
    my @lanes = split('\|',$v,-1);
    my $i = 0;
    foreach my $l (@lanes) {
      my @tmp = split(';',$l,-1);
      $store->{1}[$i++]{$sk} = \@tmp  if $direction >= 0;
      $store->{-1}[$i++]{$sk} = \@tmp if $direction <= 0;
      }
    }
  else {
    my @tmp = split(';',$v,-1);
    $store->{1}[0]{$sk} = \@tmp    if $direction >= 0 && ! $store->{1}[0]{$sk};
    $store->{-1}[0]{$sk} = \@tmp   if $direction <= 0 && ! $store->{-1}[0]{$sk};
    }
#TODO proper priority and overwriting of values  
  }

  
#################################################
## Determine number of lanes and number of entries per lane
#################################################    
sub calcNumbers {
#   $conf->{-1}{filledlanes} = 0;
#   $conf->{1}{filledlanes} = 0;
  $conf->{0}{totallanes}  = 0;
  $conf->{0}{filledlanes} = 0;
  foreach my $d (@showdirections) {
#     my $maxentries = 0;
    my $lanenum = 0;
    foreach my $lane ( @{$store->{$d}}) {
      $conf->{$d}{numberrefs}[$lanenum] = 0;
      $conf->{$d}{numberrefto}[$lanenum] = 0;
      $conf->{$d}{numberintrefs}[$lanenum] = 0;
      my @entries = (0,0,0,0); #normal, :to,:ref,:int_ref
      if (ref($lane) eq 'HASH') {
        foreach my $tag (keys %$lane) {
          my $cnt = scalar @{$lane->{$tag}};
          next if ($tag =~ /colour/);
          if($tag =~ /^destination.*ref.*:to/) {
            if ($entries[1] < $cnt){
              $entries[1] = $cnt;
              $conf->{$d}{numberrefto}[$lanenum] = $cnt;
              }
            }          
          elsif($tag =~ /^destination.*:to/) {
            if ($entries[1] < $cnt){
              $entries[1] = $cnt;
              $conf->{$d}{numberrefto}[$lanenum] = $cnt;
              }
            }
          elsif($tag =~ /^destination:ref/ && $cnt) {
            $entries[2] = 1;
            $conf->{$d}{numberrefs}[$lanenum] += $cnt;
            }
          elsif($tag =~ /^destination:int_ref/ && $cnt) {
            $entries[3] = 1;
            $conf->{$d}{numberintrefs}[$lanenum] += $cnt;
            }
          elsif($tag =~ /^destination/ && ! ($tag =~ /symbol|country|ref/)) {
            $entries[0] = $cnt if $entries[0] < $cnt;
            }
          }
        }
      $conf->{$d}{numberrefs}[$lanenum] //= 0;  
      $conf->{$d}{numberdest}[$lanenum] = $entries[0];  
      $conf->{$d}{numberdestto}[$lanenum] = $entries[1];

      if( ($conf->{$d}{numberrefs}[$lanenum]    == $conf->{$d}{numberdest}[$lanenum] || $conf->{$d}{numberrefs}[$lanenum] == 0) &&      #refs = dests or no ref
          ($conf->{$d}{numberintrefs}[$lanenum] == $conf->{$d}{numberdest}[$lanenum] || $conf->{$d}{numberintrefs}[$lanenum] == 0) &&   #and intrefs = dests or no intref
#           ($conf->{$d}{numberdestto}[$lanenum] == 0 || $conf->{$d}{numberdest}[$lanenum] >= 2) &&                                     #and no destto or at least 2 refs
          ($conf->{$d}{numberintrefs}[$lanenum] != 0 || $conf->{$d}{numberrefs}[$lanenum] != 0)                                         #and at least some ref/intref
      ) {
        $conf->{$d}{numberrefs}[$lanenum] = 0;                                     #remove ref counts, because they are ordered with dests
        $conf->{$d}{numberintrefs}[$lanenum] = 0;
        $entries[2] = 0;
        $conf->{$d}{orderedrefs}[$lanenum] = 1;
        }
      if ($conf->{$d}{numberrefto}[$lanenum] == $conf->{$d}{numberdestto}[$lanenum]) {
        $conf->{$d}{numberrefto}[$lanenum] = 0;
        $conf->{$d}{orderedrefto}[$lanenum] = 1;
        }
      elsif ($conf->{$d}{numberrefto}[$lanenum]) {  
        if ($conf->{$d}{numberrefs}[$lanenum] == 0) {
          $entries[2] += 1;
          }
#       $conf->{$d}{maxentries} = max($conf->{$d}{maxentries},$conf->{$d}{entries}[$lanenum]);
        
        }        
 
      $conf->{$d}{entries}[$lanenum] = $entries[0] + $entries[1] + ($entries[2] | $entries[3]);
#       $maxentries = max($maxentries,$conf->{$d}{entries}[$lanenum]);
      $lanenum++;
      }
#     $conf->{$d}{maxentries} = $maxentries;
    $conf->{$d}{totallanes} = scalar @{$store->{$d}};
    $conf->{$d}{filledlanes} = $conf->{$d}{totallanes};

    #Find number of single symbols
    $lanenum = 0;
    foreach my $lane ( @{$store->{$d}}) {
      if ($lane->{'destination:symbol'} && scalar @{$lane->{'destination:symbol'}}) {
        if (scalar @{$lane->{'destination:symbol'}} != $conf->{$d}{numberdest}[$lanenum]) {
          $conf->{$d}{entries}[$lanenum] += 1;
          $conf->{$d}{numbersymbols}[$lanenum] = scalar @{$lane->{'destination:symbol'}};
          }
        }
        
      if ($lane->{'destination:country'} && scalar @{$lane->{'destination:country'}}) {          
        if (scalar @{$lane->{'destination:country'}} != $conf->{$d}{numberdest}[$lanenum]) {         
          $conf->{$d}{entries}[$lanenum] += 1;
          $conf->{$d}{numbercountries}[$lanenum] = scalar @{$lane->{'destination:country'}};
          }
        }
      $lanenum++;  
      }
    $conf->{0}{totallanes}  +=   $conf->{$d}{totallanes};
    $conf->{0}{filledlanes} +=   $conf->{$d}{filledlanes};
#     $conf->{0}{maxentries} = max($conf->{$d}{maxentries} , $conf->{0}{maxentries});
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
      elsif ($lanenum > 0 && Compare($store->{$d}[$lanenum],$store->{$d}[$lanenum-1],{ ignore_hash_keys => [qw(turn ref int_ref highway)] })) {
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


  #REWRITE. isFoundinNext returns position. Check all tags if they are equal in this position (or just 1 entry, skip some tags if not ordered or numbersymbols).
  # repeat for symbol if single symbols, repeat for ref if not ordered
  #same for all :to tags
sub checkSplitLanes {
  foreach my $d (@showdirections) {
    for(my $lanenum = 0; $lanenum < scalar (@{$store->{$d}});$lanenum++) {
      $conf->{$d}->{splitlane}[$lanenum] = 0;
      #There must be 2 'turn', and at least one 'turn' is in an adjacent lane
      next unless($store->{$d}[$lanenum]{'turn'} && scalar @{$store->{$d}[$lanenum]{'turn'}} == 2);
      next if( !isFoundInNext($d,$lanenum,'turn',$store->{$d}[$lanenum]{'turn'}[0])
            && !isFoundInNext($d,$lanenum,'turn',$store->{$d}[$lanenum]{'turn'}[1]));
      my $empty = 1;
      my @found = (0,0,0);
      foreach my $k (sort keys %{$store->{$d}[$lanenum]}) {
        next if $k eq 'turn';
        next if $k eq 'ref';
        next if $k eq 'int_ref';
        next if $k eq 'highway';
        
        next if grep( /^$k$/, qw(destination:colour:to destination:colour destination:arrow destination:arrow:to)); #destination:symbol:to  destination:symbol 
        my @tmp = @{$store->{$d}[$lanenum]{$k}};
        my $i = scalar @tmp;
        while($i--) {
          my $j = isFoundInNext($d,$lanenum,$k,$tmp[$i]);
#            $error .= $lanenum.$tmp[$i]." ".$j."\n";
          $found[$j]++;
          if ($j) {
            splice(@{$store->{$d}[$lanenum]{$k}},$i,1);  
            if($k eq 'destination' || ($k eq 'destination:symbol' && $store->{$d}[$lanenum]{'destination'}==undef)) {
              if($store->{$d}[$lanenum]{'destination:colour'}) {
                splice(@{$store->{$d}[$lanenum]{'destination:colour'}},$i,1);  
                }
              if($store->{$d}[$lanenum]{'destination:arrow'}) {
                splice(@{$store->{$d}[$lanenum]{'destination:arrow'}},$i,1);  
                }
              if($store->{$d}[$lanenum]{'destination:symbol'} && $k ne 'destination:symbol') {
                splice(@{$store->{$d}[$lanenum]{'destination:symbol'}},$i,1);  
                }      
              }
            if($k eq 'destination:to' || ($k eq 'destination:symbol:to' && $store->{$d}[$lanenum]{'destination:to'}==undef)) {
              if($store->{$d}[$lanenum]{'destination:colour:to'}) {
                splice(@{$store->{$d}[$lanenum]{'destination:colour:to'}},$i,1);  
                }
              if($store->{$d}[$lanenum]{'destination:arrow:to'}) {
                splice(@{$store->{$d}[$lanenum]{'destination:arrow:to'}},$i,1);  
                }                
              if($store->{$d}[$lanenum]{'destination:symbol:to'} && $k ne 'destination:symbol:to') {
                splice(@{$store->{$d}[$lanenum]{'destination:symbol:to'}},$i,1);  
                }      
              if($store->{$d}[$lanenum]{'destination:ref:to'}) {
                splice(@{$store->{$d}[$lanenum]{'destination:ref:to'}},$i,1);  
                }      
              if($store->{$d}[$lanenum]{'destination:int_ref:to'}) {
                splice(@{$store->{$d}[$lanenum]{'destination:int_ref:to'}},$i,1);
                }
              }
            }
          else {
            $empty = 0;
            }
          }
        }
      if($empty && ($found[1] > 0 || $found[2] > 0)) {  
        $conf->{$d}->{splitlane}[$lanenum] = 1;
        }
      elsif($found[1] > 0  && $found[2] == 0) {
        insertSplitLane($lanenum,$d,1);
        $conf->{$d}->{splitlane}[$lanenum] = 2;
#         last;
        }
      elsif($found[1] == 0  && $found[2] > 0) {
        insertSplitLane($lanenum+1,$d,-1);
        $conf->{$d}->{splitlane}[$lanenum+1] = 3;
        $lanenum++;
        #last;
        }
#       $error .=  Dumper $store;  
      }
    }
  }
    
  
  
#################################################
## Generate a ref number
#################################################   
sub makeRef {
  my ($xpos,$entrypos,$text,$tags,$entry) = @_;
  $xpos += 17 if $conf->{country} ne 'PT';
  my $class = '';
  
  my $tcol = 'black';
  my $bcol = 'white';
  my $scol = '';
  
  return if $text =~ /^\s*$/;
  if($conf->{country} eq 'DE') {
    if ($text =~ /^\s*A[\s\d]+/) { $tcol = 'white'; $bcol = 'DE:blue';}
    if ($text =~ /^\s*B[\s\d]+/) { $tcol = 'black'; $bcol = 'DE:yellow';}
    if ($text =~ /^\s*E\s+/)     { $tcol = 'white'; $bcol = 'DE:green';}
    $text =~ s/^\s*A\s+//;
    $text =~ s/^\s*B\s+//;
    $text =~ s/\s//g;
    }

  if($conf->{country} eq 'AT') {
    if ($text =~ /^\s*A[\s\d]+/) { $tcol = 'white'; $bcol = 'AT:blue';}
    if ($text =~ /^\s*B[\s\d]+/) { $tcol = 'white'; $bcol = 'AT:blue';}
    if ($text =~ /^\s*E\s*/)     { $tcol = 'white'; $bcol = 'AT:green';}
    $text =~ s/^\s*B\s*//;
    $text =~ s/\s//g;
    }        

  if($conf->{country} eq 'FR') {
    if ($text =~ /^\s*[AN][\s\d]+/)  { $tcol = 'white'; $bcol = 'FR:red';}
    if ($text =~ /^\s*[EF][\s\d]+/)  { $tcol = 'white'; $bcol = 'FR:green';}
    if ($text =~ /^\s*[D][\s\d]+/)   { $tcol = 'black'; $bcol = 'FR:yellow';}
    if ($text =~ /^\s*[CRP][\s\d]+/) { $tcol = 'black'; $bcol = 'white';}
    if ($text =~ /^\s*[MT][\s\d]+/)  { $tcol = 'white'; $bcol = 'FR:lightblue';}
    }     

  if($conf->{country} eq 'GR') {
    $tcol = 'GR:yellow'; $bcol = 'GR:blue';
    if ($text =~ /^\s*ΕΟ[\s\d]+/) { $tcol = 'white'; $bcol = 'GR:blue';}
    if ($text =~ /^\s*Α[\s\d]+/)  { $tcol = 'white'; $bcol = 'GR:green';}
    if ($text =~ /^\s*[ΕE][\s\d]+/)  { $tcol = 'white'; $bcol = 'GR:green';}
    $text =~ s/ΕΟ//g;
    $text =~ s/E\s/E/g;
    $text =~ s/Ε\s/Ε/g;
    $text =~ s/^\s//g;
    $text =~ s/\s$//g;
    }

  if($conf->{country} eq 'PT') {
    $tcol = 'black'; $bcol = 'white';
    if ($text =~ /^\s*A[\s\d]+/) { $tcol = 'white'; $bcol = 'PT:blue';}
    if ($text =~ /^\s*N[\s\d]+/) { $tcol = 'black'; $bcol = 'white';}
    if ($text =~ /^\s*R[\s\d]+/) { $tcol = 'black'; $bcol = 'white';}
    $text =~ s/^\s//g;
    $text =~ s/\s$//g;
    }      
    
  if($conf->{country} eq 'SR') {
    $bcol = 'SR:yellow';
    if ($text =~ /^\s*A/) { $tcol = 'white'; $bcol = 'SR:green';}
    if ($text =~ /^\s*E/) { $tcol = 'white'; $bcol = 'SR:green';}
    }
    
  if(existEntryI($tags,'destination:colour:ref',$entry))  {
    $bcol = $tags->{'destination:colour:ref'}[$entry];
    $tcol = bestTextColor($bcol);
    }
  if(existEntryOnlyOne($tags,'destination:colour:ref'))  {
    $bcol = $tags->{'destination:colour:ref'}[0];
    $tcol = bestTextColor($bcol);
    }

  $bcol = getRGBColor($bcol);
  $tcol = getRGBColor($tcol);

  my $o = "";
  $o .= '<g  transform="translate('.$xpos.' '.$entrypos.')" class="'.$class.'">'."\n";
  if($conf->{country} eq 'PT') {
    $o .= '<rect class="destinationrefs '.$conf->{country}.'" x="0" y="-9" width="30" height="16" rx="2" style="fill:'.$bcol.';stroke:none"/>'."\n";
    }
  else {
    $o .= '<rect class="destinationrefs '.$conf->{country}.'" x="-15" y="-9" width="30" height="16" rx="2" style="fill:'.$bcol.';stroke:'.$tcol.'"/>'."\n";
    }
  $o .= '<text datapos="0" class="destinationreftext destinationrefs '.$conf->{country}.'" style="fill:'.$tcol.'">'
            .$text.'</text>'."\n";
  $o .= '</g>'."\n";
  return $o;
}

sub checkRepeatedArrow {
  my $lane  = shift @_;
  my $type  = shift @_;
  my $entry = shift @_ // 0;
  my $d = $conf->{direction};
  my $tags = $store->{$d}[$lane];

  return 0 if $entry == 0;
  return 0 if $conf->{$d}{'arrowtag'.$type}[$lane][$entry] ne $conf->{$d}{'arrowtag'.$type}[$lane][$entry-1];
  return 0 if getArrowColor($lane,$entry,$type,'arrow') ne getArrowColor($lane,$entry-1,$type,'arrow');
  return 1;
  }


#################################################
## Draw arrows
#################################################     
sub getArrow {
  my $lane  = shift @_;
  my $type  = shift @_;
  my $entry = shift @_ // 0;
  my $height = 20;
  my $d = $conf->{direction};
  my $o = '';

  if (($conf->{$d}{entries}[$lane] == 1) ) {
    $height = 20;
    }
  
  my @col;
  $col[0] = getArrowColor($lane,$entry,'main','arrow');
  
  if(defined $type && $type eq 'arrow') {
    $height = 0;
    my $deg = $conf->{$d}{arrowtag}[$lane][$entry];
    return "" unless defined $deg;
    return "" if checkRepeatedArrow($lane,"",$entry);
    $col[0] = getArrowColor($lane,$entry,'','front');
    $o .= '<use href="#arrow" transform="translate(10 '.$height.') rotate('.$deg.' 0 0) scale(1)" style="stroke:'.$col[0].';"/>'."\n";
    }
  elsif(defined $type && $type eq 'arrowto') {
    $height = 0;
    my $deg = $conf->{$d}{'arrowtag:to'}[$lane][$entry];
    return "" unless defined $deg;
    return "" if checkRepeatedArrow($lane,":to",$entry);
    $col[0] = getArrowColor($lane,$entry,':to','front');
    $o .= '<use href="#arrow" transform="translate(10 '.$height.') rotate('.$deg.' 0 0) scale(1)" style="stroke:'.$col[0].';"/>'."\n";
    }  
#   elsif ($conf->{$d}{splitlane}[$lane]) {
#
#
#       my @col;
# #       $col[0] = getBackground($lane-1,$entry,'main','front');
# #       $col[1] = getBackground($lane+1,$entry,'main','front');
#
#       my $i = 0;
#       my $offset = -15*(scalar @{$conf->{$d}{arrows}[$lane]} -1);
#       foreach my $deg (@{$conf->{$d}{arrows}[$lane]}) {
#         next if $deg eq 'none';
#         $o .= '<use href="#arrow" transform="translate('.($SIGNWIDTH/8+$offset).' %ARROWPOS%) rotate('.$deg.' 0 0)" style="stroke:'.$col[$i++].';"/>'."\n";
#         $offset += 30;
#         }
#       }
  else {
    my $offset = -20*(scalar @{$conf->{$d}{arrows}[$lane]} -1);
    my $offsetstep = 40;
    my $mergearrows = scalar @{$conf->{$d}{arrows}[$lane]}>1 ? 1 : 0;

    my $tx; my $ty;
    if ($conf->{$d}{arrowpos}[$lane] eq 'left')  {  $tx = 20;              $ty = $height;}
    if ($conf->{$d}{arrowpos}[$lane] eq 'right') {  $tx = $SIGNWIDTH-20;   $ty = $height;}
    if ($conf->{$d}{arrowpos}[$lane] eq 'center'){  $tx = $SIGNWIDTH/2;    $ty = '%ARROWPOS%';}
    if ($conf->{$d}{splitlane}[$lane])           {  $tx = $SIGNWIDTH/8;    $ty = '%ARROWPOS%';}

    if ($conf->{$d}{splitlane}[$lane]) {
      #If I'm a split lane, and (the lane on the right if 3, has arrowpos=none, then remove 2nd arrow)
      #                         (the lane on the left if 2, has arrowpos=none, then remove 1st arrow)
      if ($conf->{$d}{splitlane}[$lane]==3 && $conf->{$d}{arrowpos}[$lane+1] eq 'none') {
        $conf->{$d}{arrows}[$lane][-1] = 'none';
        }
      if ($conf->{$d}{splitlane}[$lane]==2 && $conf->{$d}{arrowpos}[$lane-1] eq 'none') {
        $conf->{$d}{arrows}[$lane][0] = 'none';
        }

      $offset = -10*(scalar @{$conf->{$d}{arrows}[$lane]} -1);
      $offsetstep = 20;

      $col[0] = getArrowColor($lane-1,$entry,'main','arrow');
      $col[1] = getArrowColor($lane+1,$entry,'main','arrow');

      if($col[0] ne $col[1]) { $mergearrows = 0;}

      }

    my $deg = $conf->{$d}{arrows}[$lane][0];
    if($mergearrows && $conf->{$d}{arrows}[$lane][0] == 270 && $conf->{$d}{arrows}[$lane][1] == -360) {
      $tx -= 12 if $conf->{$d}{splitlane}[$lane];
      $o .= '<use href="#arrow_tr" transform="translate('.$tx.' '.$ty.')" style="stroke:'.$col[0].';"/>'."\n";
      }
    elsif($mergearrows && $conf->{$d}{arrows}[$lane][0] == 180 && $conf->{$d}{arrows}[$lane][1] == 270) {
      $tx += 12 if $conf->{$d}{splitlane}[$lane];
      $o .= '<use href="#arrow_tr" transform="translate('.$tx.' '.$ty.') scale(-1,1) " style="stroke:'.$col[0].';"/>'."\n";
      }
    elsif($mergearrows && $conf->{$d}{arrows}[$lane][0] == 270 && $conf->{$d}{arrows}[$lane][1] == -45) {
      $tx -= 12 if $conf->{$d}{splitlane}[$lane];
      $o .= '<use href="#arrow_tsr" transform="translate('.$tx.' '.$ty.')" style="stroke:'.$col[0].';"/>'."\n";
      }
    elsif($mergearrows && $conf->{$d}{arrows}[$lane][0] == 225 && $conf->{$d}{arrows}[$lane][1] == 270) {
      $tx += 12 if $conf->{$d}{splitlane}[$lane];
      $o .= '<use href="#arrow_tsr" transform="translate('.$tx.' '.$ty.') scale(-1,1) " style="stroke:'.$col[0].';"/>'."\n";
      }
    else {
      my $i = 0;
      foreach my $deg (@{$conf->{$d}{arrows}[$lane]}) {
        $o .= '<use href="#arrow" transform="translate('.($tx+$offset).' '.$ty.') rotate('.$deg.' 0 0)" style="stroke:'.$col[$i].';"/>'."\n";
        $i += 1-$mergearrows; #count only with unmerged arrows
        $offset += $offsetstep;
        }
      }
    }

  return $o;
  }
#       $error .= Dumper @{$conf->{$d}{arrows}[$lane]};


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
        push(@deg,calcArrows(@{$store->{$d}[$l+$ml]{'turn'}}));
        }
      $conf->{$d}{arrows}[$l] = \@deg;
      if ($conf->{$d}{multilanes}[$l]){
        while ($conf->{$d}{multilanes}[$l] >= scalar @deg) {
          if ($conf->{country} eq 'FR') {push(@deg,90);}
          else                          {push(@deg,270);}
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
#         $conf->{$d}{maxentries} = max($conf->{$d}{maxentries}, $conf->{$d}{entries}[$l]);
#         $conf->{0}{maxentries} = max($conf->{$d}{maxentries} , $conf->{0}{maxentries});
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
        next unless $store->{$d}[$l]{'destination:arrow'.$type};
        my @deg;
        @deg = calcArrows(@{$store->{$d}[$l]{'destination:arrow'.$type}});
        @{$conf->{$d}{'arrowtag'.$type}[$l]} = @deg;
        }
      }
    }
  }

#################################################
## Convert directions to degrees
#################################################   
sub calcArrows {
  my @deg;

  if ($conf->{country} eq 'FR') {
    foreach my $arrow (@_) {
      if    ($arrow =~ /sharp_left/)     {push(@deg,180);}
      elsif ($arrow =~ /(^|;|\s)left/)   {push(@deg,180);}
      elsif ($arrow =~ /slight_left/)    {push(@deg,135);}
      elsif ($arrow =~ /through/)        {push(@deg,90);}
      elsif ($arrow =~ /slight_right/)   {push(@deg,45);}
      elsif ($arrow =~ /(^|;|\s)right/)  {push(@deg,0);}
      elsif ($arrow =~ /sharp_right/)    {push(@deg,0);}
  #     else                               {push(@deg,'');}
      }
    }
  else {  
    foreach my $arrow (@_) {
      if    ($arrow =~ /sharp_left/)     {push(@deg,135);}
      elsif ($arrow =~ /(^|;|\s)left/)   {push(@deg,180);}
      elsif ($arrow =~ /slight_left/)    {push(@deg,225);}
      elsif ($arrow =~ /through/)        {push(@deg,270);}
      elsif ($arrow =~ /slight_right/)   {push(@deg,-45);}
      elsif ($arrow =~ /(^|;|\s)right/)  {push(@deg,-360);}
      elsif ($arrow =~ /sharp_right/)    {push(@deg,45);}
  #     else                               {push(@deg,'');}
      }
    }  
  return @deg;  
  }
  
#################################################
## Get arrow colour
#################################################
sub getArrowColor {
  #Lane, entry number, (':to','main',''), ('arrow');
  my ($lane,$i,$type,$part) = @_;
     $part //= 'back';
     $type //= '';
  my $d = $conf->{direction};
  my $tags = $store->{$d}[$lane];

  my $col = "";
  $col = getBackground($lane,$i,$type,'front'); #fallback

  if ($conf->{country} eq 'GR') {  #hard override for white arrows in Greece
    $col = 'white';
    }

  if(existEntryI($tags,'destination:colour:arrow'.$type,$i)) {
    $col = $tags->{'destination:colour:arrow'.$type}[$i];
    }
  if(existEntryOnlyOne($tags,'destination:colour:arrow'.$type)) {
    $col = $tags->{'destination:colour:arrow'.$type}[0];
    }
  $col = getRGBColor($col);
  return $col;
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
  my $tags = $store->{$d}[$lane];
#Main part  
  if($type eq 'main' || $type eq '') {
    if($part eq 'back' && existEntryOnlyOne($tags,'destination:colour')) {
      $col = $tags->{'destination:colour'}[0];
      }
    elsif ($part eq "front" && existEntryOnlyOne($tags,'destination:colour:text')) {
      $col = $tags->{'destination:colour:text'}[0];
      }
    elsif ($tags->{'destination:colour:text'} && $part eq "front" && $tags->{'destination:colour'} && $conf->{country} eq 'AT'
             && ($tags->{'destination:colour'}[$i] eq 'green' ||
                ($tags->{'destination:colour'}[0] eq 'green' && (scalar @{$tags->{'destination:colour'}} == 1)))) {
      $col = 'yellow';
      }
    elsif ($part eq "front" && existEntryOnlyOne($tags,'destination:colour')) {
      $col = bestTextColor($tags->{'destination:colour'}[0]);
      }
    elsif ($part eq "front" && existEntryI($tags,'destination:colour',$i)) {
      $col = bestTextColor($tags->{'destination:colour'}[$i]);
      }
    else {
#Main DE    
      if ($conf->{country} eq 'DE') {
        if (($tags->{'destination:ref'} && $tags->{'destination:ref'}[0] =~ /^A\s/) || 
            ($tags->{'ref'} && $tags->{'ref'}[0] =~ /^A\s/) ||
            ($store->{$d}[0]{'highway'}[0] =~ /^motorway$/)) {
          $col = 'DE:blue' if $part eq 'back';
          $col = 'white'   if $part eq 'front';
          }
        else {
          $col = 'DE:yellow' if $part eq 'back';
          $col = 'black'     if $part eq 'front';
          }
        }
#Main AT        
      if ($conf->{country} eq 'AT') {
        if (($tags->{'destination:ref'} && $tags->{'destination:ref'}[0] =~ /^A/) || 
            ($tags->{'ref'} && $tags->{'ref'}[0] =~ /^A/) ||
            ($store->{$d}[0]{'highway'}[0] =~ /^motorway/)) {
          $col = 'AT:blue' if $part eq 'back';
          $col = 'white'   if $part eq 'front';
          }
        else {
          $col = 'white'   if $part eq 'back';
          $col = 'AT:blue' if $part eq 'front';
          }
        }
#Main PT    
      if ($conf->{country} eq 'PT') {
        if (($tags->{'destination:ref'} && $tags->{'destination:ref'}[0] =~ /^A/) || 
#             ($tags->{'ref'} && $tags->{'ref'}[0] =~ /^A/) ||
            ($store->{$d}[0]{'highway'}[0] =~ /^motorway$/)) {
          $col = 'PT:blue' if $part eq 'back';
          $col = 'white'   if $part eq 'front';
          }
        else {
          $col = 'white'   if $part eq 'back';
          $col = 'black'   if $part eq 'front';
          }
        }        
#Main FR        
      if ($conf->{country} eq 'FR') {
        if (($tags->{'destination:ref'} && $tags->{'destination:ref'}[0] =~ /^A/) || 
            ($tags->{'ref'} && $tags->{'ref'}[0] =~ /^A/) ||
            ($store->{$d}[0]{'highway'}[0] =~ /^motorway$/)) {
          $col = 'FR:blue' if $part eq 'back';
          $col = 'white'   if $part eq 'front';
          }
        else {
          $col = 'white'   if $part eq 'back';
          $col = 'black'   if $part eq 'front';
          }
        }
#Main GR
      if ($conf->{country} eq 'GR') {
        if (($tags->{'destination:ref'} && $tags->{'destination:ref'}[0] =~ /^[AΑ]/) ||
            ($tags->{'ref'} && $tags->{'ref'}[0] =~ /^[AΑ]/) ||
            ($store->{$d}[0]{'highway'}[0] =~ /^motorway$/)) {
          $col = 'GR:green'   if $part eq 'back';
          $col = 'GR:yellow'  if $part eq 'front';
          }
        else {
#         elsif (($tags->{'destination:ref'} && $tags->{'destination:ref'}[0] =~ /^ΕΟ/) ||
#             ($tags->{'ref'} && $tags->{'ref'}[0] =~ /^ΕΟ/)) {
          $col = 'GR:blue'     if $part eq 'back';
          $col = 'GR:yellow'   if $part eq 'front';
          }
#         else {
#           $col = "white"     if $part eq 'back';
#           $col = 'black'     if $part eq 'front';
#           }
        }
#Main SR    
      if ($conf->{country} eq 'SR') {
        if (($tags->{'destination:ref'} && $tags->{'destination:ref'}[0] =~ /^A/) || 
            ($tags->{'ref'} && $tags->{'ref'}[0] =~ /^A/) ||
            ($store->{$d}[0]{'highway'}[0] =~ /^motorway/)) {
          $col = 'SR:green' if $part eq 'back';
          $col = 'white'    if $part eq 'front';
          }
        elsif (($store->{$d}[0]{'highway'}[0] =~ /^trunk/)) {
          $col = 'SR:blue' if $part eq 'back';
          $col = 'white'   if $part eq 'front';
        }
        else {
          $col = 'SR:yellow' if $part eq 'back';
          $col = 'black'     if $part eq 'front';
          }
        }        
      }
    }
    
  if($type eq '' || $type eq ':to') {    #TODO priorities are not right
#Entry front text
    if ($part eq 'front') {
      foreach my $ta ("colour$type:text","destination:colour:text$type") { #,"colour:text"
        if (existEntryI($tags,$ta,$i)) {
          $col = $tags->{$ta}[$i];
          last;
          }
        if (existEntryOnlyOne($tags,$ta)) {
          $col = $tags->{$ta}[0];
          last;
          }
        }
      }  
#Entry colour tags
    if (existEntryI($tags,'destination:colour'.$type,$i)) {
      if ($part eq 'back'){
        $col = $tags->{'destination:colour'.$type}[$i]  
        }
      if ($part eq 'front' && $col eq '') {
        $col = bestTextColor($tags->{'destination:colour'.$type}[$i]);
        if ($conf->{country} eq 'AT' && $tags->{'destination:colour'.$type}[$i] eq 'green') {
          $col = 'AT:yellow';
          }
        }
      }
    elsif (existEntryI($tags,'destination:colour:back'.$type,$i)) {
      if ($part eq 'back'){
        $col = $tags->{'destination:colour:back'.$type}[$i]
        }
      if ($part eq 'front' && $col eq '') {
        $col = bestTextColor($tags->{'destination:colour:back'.$type}[$i]);
        if ($conf->{country} eq 'AT' && $tags->{'destination:colour:back'.$type}[$i] eq 'green') {
          $col = 'AT:yellow';
          }
        }
      }
    else {

#Entry DE
      if ($conf->{country} eq 'DE' && $type eq ':to') {
        if (($tags->{'destination:ref:to'} && $tags->{'destination:ref:to'}[$i] =~ /^A\s/)
            || ($tags->{'destination:symbol:to'} && $tags->{'destination:symbol:to'}[$i] eq 'motorway')
#             ||
            ) {
          $col = 'DE:blue' if $part eq 'back';
          $col = 'white'   if $part eq 'front';
          }
        }
#Entry AT
      if ($conf->{country} eq 'AT' && $type eq ':to') {
        if (($tags->{'destination:ref:to'} && $tags->{'destination:ref:to'}[$i] =~ /^A/)
            || ($tags->{'destination:symbol:to'} && $tags->{'destination:symbol:to'}[$i] eq 'motorway')) {
          $col = 'AT:blue' if $part eq 'back';
          $col = 'white'   if $part eq 'front';
          }
        }  
#Entry FR
      if ($conf->{country} eq 'FR' && $type eq ':to') {
        if (($tags->{'destination:ref:to'} && $tags->{'destination:ref:to'}[$i] =~ /^A/)
            || ($tags->{'destination:symbol:to'} && $tags->{'destination:symbol:to'}[$i] eq 'motorway')) {
          $col = 'FR:blue' if $part eq 'back';
          $col = 'white'   if $part eq 'front';
          }
        }        
#Entry GR
      if ($conf->{country} eq 'GR' && $type eq ':to') {
        if (($tags->{'destination:ref:to'} && $tags->{'destination:ref:to'}[$i] =~ /^A\s/)
            || ($tags->{'destination:symbol:to'} && $tags->{'destination:symbol:to'}[$i] eq 'motorway')) {
          $col = 'GR:green'  if $part eq 'back';
          $col = 'GR:yellow' if $part eq 'front';
          }
        }
#Entry PT
      if ($conf->{country} eq 'PT' && $type eq ':to') {
        if (($tags->{'destination:ref:to'} && $tags->{'destination:ref:to'}[$i] =~ /^A/)
            || ($tags->{'destination:symbol:to'} && $tags->{'destination:symbol:to'}[$i] eq 'motorway')) {
          $col = 'PT:blue' if $part eq 'back';
          $col = 'white'   if $part eq 'front';
          }
        }
      }      
    if( $col eq '' && $part eq 'front') {
      $col = bestTextColor(getBackground($lane,$i,$type,'back'));
      }
    }
  if( $col eq '' && $part eq 'front') {
    $col = bestTextColor(getBackground($lane,0,'main','back'));
    }

  $col = getRGBColor($col);  
  return $col;
}



sub existEntryI {
  my ($tags,$ta,$i) = @_;
  return 1 if $tags->{$ta} && scalar @{$tags->{$ta}}>$i && $tags->{$ta}[$i] ne "";
  return 0;
  }

sub existEntryOnlyOne {
  my ($tags,$ta) = @_;
  return 1 if $tags->{$ta} && scalar @{$tags->{$ta}}==1 && $tags->{$ta}[0] ne "";
  return 0;
  }



sub bestTextColor {
  my $col = shift @_;
  $col = getRGBColor($col);
  my ($red,$green,$blue) = $col =~ /(\w\w)(\w\w)(\w\w)/;
  return 'black' if (hex($red)*0.299 + hex($green)*0.587 + hex($blue)*0.114) > 186;
  return 'GR:yellow' if ($conf->{country} eq 'GR');
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
    $image .= '<g transform="translate('.$pos.' 0)">'."\n".'<text class="resizeme" datapos="'.$pos.'" style="fill:'.$tcol.'">'.$text.'</text>'."\n".'</g>'."\n";
    }
  return $image;
  }

sub drawDistance {
  my ($lane,$i,$type,$pos) = @_;
     $type //= '';
  my $image = '';
  my $d = $conf->{direction};

  return;

  if($store->{$d}[$lane]{'destination:distance'.$type}) {

    if( existEntryI($store->{$d}[$lane],'destination:distance'.$type,$i)) {
      my $dis = $store->{$d}[$lane]{'destination:distance'.$type}[$i];
      my $tcol = getBackground($lane,$i,$type,'front');
      $image .= '<g transform="translate('.(170).' 0)">'."\n".'<text class="distance" datapos="'.($pos).'" style="fill:'.$tcol.'">'.$dis.'</text>'."\n".'</g>'."\n";
      }
    }
  }
 
  
sub isFoundInNext { #TODO rewrite to return position of entry
  my ($d,$lane,$key,$val) = @_;
  return 3 if $val eq "";
  return 3 if $val eq "none";
  
  if($lane>0) {
    return 1 if grep( /^\Q$val\E$/, @{$store->{$d}[$lane-1]{$key}});
    }
  if($store->{$d}[$lane+1]) {
    return 2 if grep( /^\Q$val\E$/, @{$store->{$d}[$lane+1]{$key}});
    }
  return 0;
  }
  
sub insertSplitLane {
  my $pos = shift @_;
  my $d = shift @_;
  my $side = shift @_;
  my $rempos = $pos+$side;
  splice(@{$store->{$d}},$pos,0,{});
  foreach my $k (keys %{$store->{$d}[$rempos]}) {
    if ($k eq 'turn') {
      $store->{$d}[$pos]{$k} = $store->{$d}[$rempos]{$k};
      $store->{$d}[$rempos]{$k} = [];
      }
    else {
      $store->{$d}[$pos]{$k} = [];
      }
    }
  foreach my $k (keys %{$conf->{$d}}) {
    next unless ref($conf->{$d}{$k}) eq 'ARRAY';
    splice(@{$conf->{$d}{$k}},$pos,0,"");
    }
  $conf->{$d}{totallanes}++;  
  }

  
#Used tags
# destination
# destination:to
# 
# destination:arrow
# destination:arrow:to
# 
# destination:colour
# destination:colour:back
# destination:colour:ref
# destination:colour:text
# destination:colour:to
# colour:text
# colour:back
# colour:ref
# 
# destination:ref
# destination:ref:to
# destination:int_ref
# 
# destination:symbol
# destination:symbol:to
#
# turn
