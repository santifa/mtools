## mtools

A small perl script which simplifies the usage of ffmpeg by providing
common operations on video files.

Dependencies: `perl >= 5.32, ffmpeg >= 4.3`

#### Usage

Clone the repository and either add the folder to your `.*rc` or run in the folder.

Some basic operations:  

Show help: `./mtools.pl help`  
Join file: `./mtools.pl join file_a.mp4 file_b.mp4`  
Convert file: `./mtools.pl conv -c mkv -a acc file.mp4`  
Split file: `./mtools.pl split -b file.mp4`  

See help for more informations.

