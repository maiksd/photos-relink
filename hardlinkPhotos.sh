#!/bin/bash
#
# Script to reduce storage requirements after copying external images into Photos.app's library, by deleting
# the external images and putting hardlink to the library's file in it's place. Works on basis of sha1 hashes.
# The external links are chmodded to read-only to prevent accidental modifications, as any future change would
# probably confuse Photos.app's internal management.
#
# Dependency: gawk (can be installed with homebrew)
#
# USE AT YOUR OWN RISK! If this screws up your photos, blame yourself. Do not run this script if you do not
# fully understand what it's doing. Test it before really executing the commands. And as all software,
# it may contain bugs. Also consider that my photo library is the only one I ever tested this against, and
# this has only run once, so it cannot be considered well tested.
#
# Maik Musall <maik@musall.de> May 2015, twitter.com/maikm

if [ $# -ne 2 ]; then
	echo "usage: $0 pathToPhotosLibrary pathToConventionalImageFolder"
	exit 1
fi

# While stdout will have a few lines informing about what the script is doing, the log contains an entry for
# each linked file, so if something goes wrong, there is a chance to find out.
LOG=/tmp/hardlinkPhotos.$$.log
touch $LOG

# Check arguments and folder structures, prevent confusing the two cmd args
photoslibpath="$1"
folderpath="$2"
if [[ ! -d "${photoslibpath}/Masters" ]]; then
	echo "${photoslibpath} is not a Photos.app library"
	exit 1
fi
let libvers=`grep -A1 MinorVersion "${photoslibpath}/ProjectDBVersion.plist" | awk -F "[<>]" '/integer/{print $3}'`
if [[ $libvers -lt 32 ]]; then
	echo "${photoslibpath} appears to be an iPhoto library, not a Photos library"
	exit 1
fi
if [[ ! -d "${folderpath}" ]]; then
	echo "${folderpath} is not a folder"
	exit 1
fi

# Check that hard links can actually be used
photoslibfs=`df "${photoslibpath}" | tail -n 1 | cut -d' ' -f1`
folderfs=`df "${folderpath}" | tail -n 1 | cut -d' ' -f1`
if [ "$photoslibfs" != "$folderfs" ]; then
	echo "folder is not on the same filesystem as the Photos library, cannot use hard links"
	exit 2
fi

mastersHashes=/tmp/mastersHashes.$$
folderHashes=/tmp/folderHashes.$$
#mastersHashes=/tmp/mastersHashes
#folderHashes=/tmp/folderHashes

# Build sha hash lists. Runs with 2x3 threads in parallel, reading about 770 MByte/s on my MBP SSD.
# Remove the "-P 3" if you have a slow SSD, and also remove the "&" and the "wait" if you have a
# spinning hard disk.
echo -n "Building lists of hashes..."
find "${photoslibpath}/Masters" -type f -size +1 | grep -i -e 'jpg$' -e 'jpeg$' -e 'cr2$' -e 'nef$' | sed 's/ /\\ /g' | xargs -n 20 -P 3 shasum > $mastersHashes &
find "${folderpath}" -type f -size +1 | grep -i -e 'jpg$' -e 'jpeg$' -e 'cr2$' -e 'nef$' | sed 's/ /\\ /g' | xargs -n 20 -P 3 shasum > $folderHashes &
wait
echo "done"

# Output an intermediate number to have an idea what to expect. This may also count duplicates within
# the folder structure itself, which will not be touched if there is no matching master in the library.
echo -n "Number of duplicates identified: "
echo `cat $folderHashes $mastersHashes | cut -d' ' -f1 | sort | uniq -d | wc -l`

echo "Filesystem before:" >> $LOG
df -m $folderpath >> $LOG

# The awk script works by building a dictionary of the masters hashes, then going through the folder
# files, look for that hash, and if found, do the re-linking.
cat $folderHashes | sort -k2 | gawk -v mastersHashes=$mastersHashes '
BEGIN {
	while( (getline line < mastersHashes) > 0 ) {
		hash = substr( line, 0, 40 )
		path = substr( line, 43 )
		mhash[ hash ] = path
	}
	close( mastersHashes )
}
{
	hash = substr( $0, 0, 40 )
	masterfile = mhash[ hash ]
	if( length( masterfile ) > 0 ) {
		path = substr( $0, 43 )

		cmdm = "ls -i \"" masterfile "\" | cut -d\" \" -f1"
		cmdm | getline minode
		close( cmdm )

		cmdf = "ls -i \"" path "\" | cut -d\" \" -f1"
		cmdf | getline finode
		close( cmdf )

		if( minode == finode ) {
			print "SKIPPING file already sharing same inode: " masterfile ", " path
		} else {
			#print "minode = " minode
			#print "finode = " finode
			print "Linking " path
			ret = system( "ln -f \"" masterfile "\" \"" path "\"" )
			if( ret != 0 ) {
				print "Failure executing ln"
				exit ret
			}
			ret = system( "chmod a-w \"" path "\"" )
			if( ret != 0 ) {
				print "Failure executing chmod"
				exit ret
			}
		}
	} else {
		#print "masterfile length is 0 on " $0
	}
}
' >> $LOG

# This may not reflect any changes yet, as this can take a little while to get updated, somehow. Also
# mobile time machine logic may still hold on to the old inodes.
echo "Filesystem after:" >> $LOG
df -m $folderpath >> $LOG

# Cleanup is optional. I prefer to leave these files behind for archiving along with the logfile.
#rm -f $mastersHashes $folderHashes

