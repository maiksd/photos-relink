# OS X Yosemite Photos Library Relinker

One model of keeping the original master files of your photos is to have them in a traditional folder structure on your filesystem.
That model also worked fine with iPhoto.app or Photos.app, but as soon as you want to use the fancy new iCloud Photo Library, you
have to merge (copy) them into the Photos.app library.

While Photos.app is smart and uses hard links when it creates it's library from a iPhoto library you already had, it isn't so smart
when doing this merge. It copies the files, wasting huge portions of your storage with duplicate files.

So I hacked this little script that you can point at your Photos.app library and an external folder, and it will look for
files that are the same in the library masters, delete the folder file and put a hard link to the library master in it's place.
This frees up all the space that was lost during the external file merge.

**Do not use this script if you do not understand what it does!** Even then, test it (e.g. by letting it print out the actual ln
command instead of executing it) before applying it to your library.

