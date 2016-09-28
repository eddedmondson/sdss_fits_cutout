#!/usr/bin/perl -w
use strict;
use POSIX "fmod";

###################################################
# INSTRUCTIONS                                    #
# This expects an input catalogue of DR8 or later #
# SDSS objid, ra, dec, run, rerun, camcol, field  #
# and petrorad. You may not use all of these bits #
# of data in your edited version of this script   #
# so feel free to adapt as necessary.             #
#                                                 #
# You should adapt the $idlpath variable to point #
# to a location for various helper IDL code if    # 
# you need to make jpegs.                         #
# I've commented it and other bits out for now so #
# it only generates FITS files.                   #
#                                                 #
# You'll also want a copy of Montage from         #
# http://montage.ipac.caltech.edu                 #
# and point to its installation bin folder in the #
# $montagebin variable.                           #
###################################################

my $inputfile=$ARGV[0];

open INPUT, $inputfile or die;

our @catfields;
our ($objid, $ra, $dec, $run, $rerun, $camcol, $field,$petrorad);

# example download URL http://data.sdss3.org/sas/dr10/boss/photoObj/frames/301/5314/1/frame-u-005314-1-0136.fits.bz2
our $baseurl="http://data.sdss3.org/sas/dr10/boss/photoObj/frames/301";
#our $idlpath="/Volumes/disk2/edd/pipeline";
our $montagebin="/Users/edd/Montage_v3.3/bin";



#discard a line which is normally the file header
my $header=<INPUT>;

our @uurls; our @gurls; our @rurls; our @iurls; our @zurls;

while (<INPUT>) {
#this chunk reads in the text file
    chomp;
    @catfields=split ",",$_;
    $objid=$catfields[0]; $ra=$catfields[1]; $dec=$catfields[2];
    $run=$catfields[3]; $rerun=$catfields[4];
    $camcol=$catfields[5]; $field=$catfields[6];
    $petrorad=$catfields[7];
    
    #send request to skyserver to identify additional fields 
    # within a certain range
    #This new version bases it on bounds of the galaxy rather than the field, which is more constraining
    #We do have an issue in that RA can in principle run through 360 degrees up to 0... we try to deal with this correctly
    my $grange=($petrorad*10)/3600; #check fields that overlap within 10 petrorads of the galaxy
    my $ramax=$ra+$grange; my $ramin=$ra-$grange;
    my $decmax=$ra+$grange; my $decmin=$dec-$grange;
    my $sql;
    if (($ra > 359.6) or ($ra < 0.4)) { #add 180 to everything, and mod 360
	$ramax=fmod($ramax+180,360);
	$ramin=fmod($ramin+180,360);
        $sql="select run, camcol, field from field where (((ramax+180)%360 between $ramin and $ramax) or ((ramin+180)%360 between $ramin and $ramax)) and ((decmin between $decmin and $decmax) or (decmax between $decmin and $decmax))";
    }  else { #we're safe
	$sql="select run, camcol, field from field where ((ramax between $ramin and $ramax) or (ramin between $ramin and $ramax)) and ((decmin between $decmin and $decmax) or (decmax between $decmin and $decmax))";
    }
    
    my $requrl="http://skyserver.sdss3.org/dr10/en/tools/search/x_sql.aspx?format=csv&cmd=$sql"; #remember we have spaces and annoying chars, so quote in system call
    system("wget \"$requrl\" -O fieldsearch.csv");
    sleep(2);
    #open downloaded file, discard first two lines
    open FS, "fieldsearch.csv" or die;
    
    my $discard=<FS>; $discard=<FS>;
    my @xruns; my @xcamcols; my @xfields; my @xrun6s; my @xfield4s;
    #parse the file and push the contents into memory
    while (<FS>) {
	my @split = split ',',$_;
	push @xruns,$split[0];
	push @xcamcols, $split[1];
	push @xfields, $split[2];
	push @xrun6s,sprintf('%06d',$split[0]);
	push @xfield4s,sprintf('%04d',$split[2]);
    }
    #loop over remainder, getting details, then pass into subloop over band and push into @urls....
    #this bit of code gets messy - it's trying to get each file downloaded one by one in each band, but first it is building up a list of all files it will require for all objects - this will save it later from downloading the same file more than once
    my @urls;
    foreach my $band( "u","g","r","i","z") {
	
	for (my $i=0; $i<=$#xruns; $i++) {
	    push @urls,"/$xruns[$i]/$xcamcols[$i]/frame-$band-$xrun6s[$i]-$xcamcols[$i]-$xfield4s[$i].fits.bz2"; 
	}

	my @urlcopy=@urls;
	if ($band eq 'u') {push @uurls, \@urlcopy;}
	if ($band eq 'g') {push @gurls, \@urlcopy;}
	if ($band eq 'r') {push @rurls, \@urlcopy;}
	if ($band eq 'i') {push @iurls, \@urlcopy;}
	if ($band eq 'z') {push @zurls, \@urlcopy;}
	undef @urls;
    }
    rename "fieldsearch.csv","$objid.csv";

}
close INPUT;

#Here we reopen the input catalogue and also start to generate a list of objects with well generated outputs, and objects with problems and some hint of what that problem was
open INPUT, $inputfile or die;
open GOODLIST, "> $inputfile.goodlist.txt" or die;
open WARNINGS, "> $inputfile.status.txt" or die;
$header=<INPUT>;
my $index=-1;
while (<INPUT>) {
    #more file parsing code
    $index++;
    chomp;
    @catfields=split ",",$_;
    print "Working on ObjID $catfields[0]\n";
    $objid=$catfields[0]; $ra=$catfields[1]; $dec=$catfields[2];
    $run=$catfields[3]; $rerun=$catfields[4]; $camcol=$catfields[5];
    $field=$catfields[6]; $petrorad=$catfields[7];

    my $field4=sprintf('%04d',$field);

    #and in this section we check whether our file archive contains the raw fits we need, and if not we get it
    foreach my $band ("u","g","r","i","z") {
	my @urls;
	if ($band eq 'u') {@urls=@{$uurls[$index]}}
	if ($band eq 'g') {@urls=@{$gurls[$index]}}
	if ($band eq 'r') {@urls=@{$rurls[$index]}}
	if ($band eq 'i') {@urls=@{$iurls[$index]}}
	if ($band eq 'z') {@urls=@{$zurls[$index]}}
	my $nurls=$#urls+1;
	warn "$nurls URLs found to check";
	foreach my $url (@urls) {
	    $url =~ /(frame.*)/;
	    my $filetodownload=$1;
	    print "Checking for existence of $filetodownload\n";
	    if (-e "archive/$filetodownload") {
		print "file exists, do not need to redownload\n";
	    } else {
		print "file does not exist, downloading\n";
		system("wget $baseurl".$url." -O archive/$filetodownload");
	    }
	    system("cp archive/$filetodownload mosaic/");
	}
	#do montage - this requires that the proj, diff and corr directories exist for it to work in.
	#we are doing appropriate background modelling to blend the images together properly
	system("bunzip2 ./mosaic/*.fits.bz2");
	chdir "mosaic" or die;
	system("$montagebin/mImgtbl ./ raw.tbl");
	system("$montagebin/mMakeHdr raw.tbl template.hdr");
	system("$montagebin/mProjExec -p ./ raw.tbl template.hdr proj stats.tbl");
	system("$montagebin/mImgtbl proj images.tbl");
	system("$montagebin/mOverlaps images.tbl diffs.tbl");
	system("$montagebin/mDiffExec -p proj diffs.tbl template.hdr diff");
	system("$montagebin/mFitExec diffs.tbl fits.tbl diff");
	system("$montagebin/mBgModel images.tbl fits.tbl corr.tbl");
	system("$montagebin/mBgExec -p proj images.tbl corr.tbl corr");
	system("$montagebin/mAdd -p corr images.tbl template.hdr ../$band$objid.fits");
	#clean out unwanted raw files
	chdir "..";
	unlink glob "./mosaic/*";
	unlink glob "./mosaic/proj/*";
	unlink glob "./mosaic/corr/*";
	unlink glob "*area.fits";
    }


    my $status=999;
    my $attempts=0;
    #here we decide on how big our cutout should be. $range should be
    # some size in degrees, here we have a scaling off petrosian radius
    my $range = $petrorad * 8.48 /(60 * 60);

    #Now we write a piece of IDL code to be run to do the cut out
    while ($status !=0) {
	open OUTPUT, ">trim_and_jpg.pro" or die;
	my $idlcode=
#this line not needed because idlpath not needed unless doing jpgs
#	    "!PATH=!PATH+':$idlpath'\n".
# the next five lines commented out are involved in jpg creation
#	    ".compile '$idlpath/dr8make_sdss_u.pro'\n".
#	    ".compile '$idlpath/dr8make_sdss_g.pro'\n".
#	    ".compile '$idlpath/dr8make_sdss_r.pro'\n".
#	    ".compile '$idlpath/dr8make_sdss_i.pro'\n".
#	    ".compile '$idlpath/dr8make_sdss_z.pro'\n".
	    "ufile='u$objid.fits'\n".
	    "gfile='g$objid.fits'\n".
	    "rfile='r$objid.fits'\n".
	    "ifile='i$objid.fits'\n".
	    "zfile='z$objid.fits'\n".
	    "ra=$ra\n"."dec=$dec\n".
	    "range=$range\n".
	    
	    "u=READFITS(ufile,uhdr)\n".
	    "g=READFITS(gfile,ghdr)\n".
	    "r=READFITS(rfile,rhdr)\n".
	    "i=READFITS(ifile,ihdr)\n".
	    "z=READFITS(zfile,zhdr)\n".
	    # getrot gets out the cdelt values from the FITS header
	    # these values tell you the coordinate transformation from
	    # (ra,dec) to (x,y)
	    # adxy then does the appropriate coordinate transformation for
	    # the target location and then after that we calculate the
	    # positions of our image corners in (x1,y1) and (x3,y3)
	    "getrot, uhdr, rot, cdelt\n".
            "adxy, uhdr, ra, dec, xc, yc\n".
	    "x1=xc-range/cdelt[0]\n".
	    "y1=yc-range/cdelt[1]\n".
	    "x3=xc+range/cdelt[0]\n".
	    "y3=yc+range/cdelt[1]\n".
	    "size=size(u)\n".
	    # here we swap the corners if they're the wrong way round!
	    "if (x1 gt x3) then swap,x1,x3\n".
	    "if (y1 gt y3) then swap,y1,y3\n".
	    "print, 'u',x1,y1,x3,y3\n".
	    # this is a whole bunch of code to check for failures if we don't have full coverage of the target object
	    "if ((x1 lt 0) and (y1 lt 0)) then exit, status=1\n". #we need (ra-,dec=), (ra=,dec-), (ra-, dec-) 
	    "if ((x1 lt 0) and (y3 gt size[2]-1)) then exit, status=7\n". #we need (ra+,dec=), (ra+,dec-), (ra=,dec-)
	    "if ((x3 gt size[1]-1) and (y1 lt 0)) then exit, status=8\n". #we need (ra-,dec=), (ra-,dec+), (ra=,dec+)
	    "if ((x3 gt size[1]-1) and (y3 gt size[2]-1)) then exit, status=4\n". #we need (ra+,dec+), (ra=,dec+), (ra+,dec=)
	    "if ((x1 lt 0) and (y1 ge 0)) then exit, status=2\n". #we need (ra=,dec-) 
	    "if ((x1 ge 0) and (y1 lt 0)) then exit, status=3\n". #we need (ra-,dec=)
	    "if ((x3 gt size[1]-1) and (y3 le size[2]-1)) then exit, status=5\n". #we need (ra=,dec+)
	    "if ((x3 le size[1]-1) and (y3 gt size[2]-1)) then exit, status=6\n". #we need (ra+,dec=)
	    # hextract generates both the extracted data and the appropriate fits header for it
	    # we then write it out with writefits
	    "hextract, u, uhdr, ucut, ucuthdr, x1,x3,y1,y3\n".
	    "writefits, 'cu$objid.fits.dx',ucut,uhdr\n".

	    #and we repeat teh above for all other bands
	    "getrot, ghdr, rot, cdelt\n".
            "adxy, ghdr, ra, dec, xc, yc\n".
	    "x1=xc-range/cdelt[0]\n".
	    "y1=yc-range/cdelt[1]\n".
	    "x3=xc+range/cdelt[0]\n".
	    "y3=yc+range/cdelt[1]\n".
	    "size=size(g)\n".
	    "if (x1 gt x3) then swap,x1,x3\n".
	    "if (y1 gt y3) then swap,y1,y3\n".
	    "print, 'g',x1,y1,x3,y3\n".
	    "hextract, g, ghdr, gcut, gcuthdr, x1,x3,y1,y3\n".
	    "writefits, 'cg$objid.fits.dx',gcut,ghdr\n".
	    
	    "getrot, rhdr, rot, cdeltr\n".
            "adxy, rhdr, ra, dec, xc, yc\n".
	    "x1=xc-range/cdelt[0]\n".
	    "y1=yc-range/cdelt[1]\n".
	    "x3=xc+range/cdelt[0]\n".
	    "y3=yc+range/cdelt[1]\n".
	    "size=size(r)\n".
	    "if (x1 gt x3) then swap,x1,x3\n".
	    "if (y1 gt y3) then swap,y1,y3\n".
	    "print, 'r',x1,y1,x3,y3\n".
	    "hextract, r, rhdr, rcut, rcuthdr, x1,x3,y1,y3\n".
	    "writefits, 'cr$objid.fits.dx',rcut,rhdr\n".
	    
	    "getrot, ihdr, rot, cdelt\n".
            "adxy, ihdr, ra, dec, xc, yc\n".
	    "x1=xc-range/cdelt[0]\n".
	    "y1=yc-range/cdelt[1]\n".
	    "x3=xc+range/cdelt[0]\n".
	    "y3=yc+range/cdelt[1]\n".
	    "size=size(i)\n".
	    "if (x1 gt x3) then swap,x1,x3\n".
	    "if (y1 gt y3) then swap,y1,y3\n".
	    "print, 'i',x1,y1,x3,y3\n".
	    "hextract, i, ihdr, icut, icuthdr, x1,x3,y1,y3\n".
	    "writefits, 'ci$objid.fits.dx',icut,ihdr\n".
	    
	    "getrot, zhdr, rot, cdelt\n".
            "adxy, zhdr, ra, dec, xc, yc\n".
	    "x1=xc-range/cdelt[0]\n".
	    "y1=yc-range/cdelt[1]\n".
	    "x3=xc+range/cdelt[0]\n".
	    "y3=yc+range/cdelt[1]\n".
	    "size=size(z)\n".
	    "if (x1 gt x3) then swap,x1,x3\n".
	    "if (y1 gt y3) then swap,y1,y3\n".
	    "print, 'z',x1,y1,x3,y3\n".
	    "hextract, z, zhdr, zcut, zcuthdr, x1,x3,y1,y3\n".
	    "writefits, 'cz$objid.fits.dx',zcut,zhdr\n".

# the next bit of commented code does JPG creation, 
# it sounds like you don't need this so I turned it off!	    
#	    "ucutsc=CONGRID(ucut,424,424,1,/INTERP)\n".
#	    "gcutsc=CONGRID(gcut,424,424,1,/INTERP)\n".
#	    "rcutsc=CONGRID(rcut,424,424,1,/INTERP)\n".
#	    "icutsc=CONGRID(icut,424,424,1,/INTERP)\n".
#	    "zcutsc=CONGRID(zcut,424,424,1,/INTERP)\n".
	    
#	    "dr8make_sdss_u,ucutsc,\"cu$objid.jpg\"\n".
#	    "dr8make_sdss_g,gcutsc,\"cg$objid.jpg\"\n".
#	    "dr8make_sdss_r,rcutsc,\"cr$objid.jpg\"\n".
#	    "dr8make_sdss_i,icutsc,\"ci$objid.jpg\"\n".
#	    "dr8make_sdss_z,zcutsc,\"cz$objid.jpg\"\n".
	""; #finish the line!
	# write this code out and run IDL, checking the status	
	print OUTPUT $idlcode;
	# !!! Look out - this will need adapting to your IDL location !!!
	system("/Applications/itt/idl/idl/bin/idl <trim_and_jpg.pro");
	$status=$?; $status /= 256;
	print WARNINGS "$objid $status\n";
	# clean up after myself
	unlink "trim_and_jpg.pro";
	unlink glob "*.fits";
	#record if we were successful
	if ($status == 0) {print GOODLIST "$objid\n";}
	$status=0;
    }
}


close GOODLIST;
close WARNINGS;
