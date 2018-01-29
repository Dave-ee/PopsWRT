Here you can put your own payloads for you to launch remotely from PopsWRT.

Usage:
To launch a payload, go to the 'Payloads' page on PopsWRT and type in the name of the directory in this folder.
When you launch a payload via it's directory it will automatically source the 'payload.sh' in that directory.

Example:
	File Structure:	custom/
				ledchanger/
					payload.sh
					log.txt
					readme.txt
	Launch: ledchanger