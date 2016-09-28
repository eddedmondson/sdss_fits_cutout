# sdss_fits_cutout
#### A somewhat kludgy script to generate FITS cutouts from SDSS data

The script is written in Perl, with dependencies on IDL, the IDL astronomy library (http://idlastro.gsfc.nasa.gov/), and Montage (http://montage.ipac.caltech.edu/). Hardcoded variables in it point to the location of these and need to be edited. I've not actually tested it again since I last worked on it in April 2015.

It reads a CSV file of objid, ra, dec, run, rerun, camcol, field, and petrorad. It acquires all fields with coverage within 10x the Petrosian radius.

In the process of generating the cutouts it maintains a list of successfully created objects ($inputfile.goodlist.txt) and of a status code for those where an issue was hit ($inputfile.status.txt). You should only get issues at the edge of the survey footprint I think...

It expects to be working in a directory with subdirectories:  
archive - holding a cache of previously downloaded files - might need to be cleared if a download fails  
mosaic/proj - Montage working directory  
mosaic/diff - "   
mosaic/corr - "  

Line 175 defines how big the cutout should be for an object - currently scales to the Petrosian radius.

At line 180 an IDL script is generated - there's a lot of commented code for making jpeg images from the cutouts. I could be poked to provide them or they're based on http://cosmo.nyu.edu/hogg/visualization/. The commented code also rescales the image in the CONGRID calls.

Line 303 has a hard coded location to the IDL binary.
