
'''
Created on 12 Jan 2012
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

@author: dev worldlassproject.org.uk
'''

""" Downloads the KA archive """

import os, platform, sys
import subprocess
from optparse import OptionParser
import  traceback
import shutil
import httplib
import simplejson as json
import urllib

readabletitles=[];
globtitles=[];
totalDVDSize=0;
downloadLinks=[];

def main():
	
	parser = OptionParser(usage="%prog [options] -o [] -p [] -x [y|n] -c [y|n]" , description="Downloads video from the KA archive")
	parser.add_option("-p", "--playlist", default="", help="The playlist you want to download e.g Biology or All for all")
	parser.add_option("-e", "--python", default=(sys.executable if platform.system() == "Windows" else "python"), help="Path of python executable.")
	parser.add_option("-o", "--output", default='', help="Location of the output for the DVD")
	parser.add_option("-c", "--clean", default='n', help="Cleans existing downloads")
	parser.add_option("-x", "--sample", default='', help="Perform a sample run ")
	
	
	(options, args) = parser.parse_args()
	
	if options.playlist == "" or options.output == "":
		parser.print_help()
		return
	else:
		createWorkingFolder(options);
		getPlayListFromAPI(options);
		downloadVideos(options);
		
def createWorkingFolder(options):
	if  not os.path.exists(options.output):
		outputMessage("Creating Output Folder")
		os.makedirs(options.output)
	#if clean specified recreate it   
	if options.clean == 'y':
		outputMessage("Cleaning Output")
		shutil.rmtree(options.output, ignore_errors=True);
		os.makedirs(options.output)


def getPlayListFromAPI(options):
	
	outputMessage("Reading Playlist from API")
	httpServ = httplib.HTTPConnection("www.khanacademy.org", 80)
	httpServ.connect()
	httpServ.request('GET', "/api/v1/playlists/library/list")

	
	
	response = httpServ.getresponse()
	if response.status == httplib.OK:
		result = response.read();
		playlistitems = json.loads(result);
		filename = '';
		count = 0;
		names=[];
		if(len(playlistitems)==0):# in case the API is down
			raise IOError('API Playlist is empty');
		for topic in playlistitems:
		   if ('title' in topic and topic['title']==options.playlist or options.playlist=='All'):
			for item in topic['videos']:
				#outputMessage(str(item));
				if('download_urls' in item):
					if(item['download_urls']==None):
						continue;
					playlistfile = item['download_urls']['mp4'];
					name = item['readable_id'];
				
					readabletitles.append(name);
					globtitles.append(item['title']);
					filename = options.output + "/" + name + ".mp4";
					downloadLinks.append([playlistfile,filename]); 
					names.append(name);
					#TESTING
			
					count = count + 1;
					if(count > 1 and options.sample=='y'):
						return;
			
				
	else:
		raise IOError("Playlist API unavailable");
	
	
				
def checkFileDownloadedCorrectly(playlistfile, filename):	
	
	expected=getDownloadFileSize(playlistfile)
	outputMessage ("Content-Length for file :"+playlistfile+" is "+ str(expected))	
	actual=checkFileSize(filename);
	outputMessage("File on disk: "+ str(actual))
		
	if(expected != actual):
		return False;
	else:
		outputMessage("File on disk is OK: "+ str(filename))
		return True;
	
def getDownloadFileSize(playlistfile):
	site = urllib.urlopen(playlistfile)
	meta = site.info()
	expected=int(meta.getheaders("Content-Length")[0]);	
	return expected;	
					
def downloadVideos(options):  
	
	for pairedInfo in downloadLinks:
		if os.path.exists(pairedInfo[1]):
				#clean and re-download
				if options.clean == "y":
					runProcess(["rm", pairedInfo[1]]);
					outputMessage("I removed existing MP4 file: " + pairedInfo[1])
				if(checkFileDownloadedCorrectly(pairedInfo[0], pairedInfo[1])==False):
						outputMessage("MP4 file is incomplete will re-download: " + pairedInfo[1])
						downloadFile(pairedInfo[0], pairedInfo[1])
				else:
					#it exists is fine and so carry on
					continue;
		##download it, it doesnt exist 
		downloadFile(pairedInfo[0], pairedInfo[1])
		if(checkFileDownloadedCorrectly(pairedInfo[0], pairedInfo[1])==False):
			raise IOError("Error downloading file "+pairedInfo[0] +"locally to"+ pairedInfo[1]);

def downloadFile(playlistfile, location):
		outputMessage ("Downloading file: "+playlistfile+ "into location "+location)
 		urllib.urlretrieve(playlistfile, location);
			
def outputMessage(message):
	sys.stderr.write("-----------------------------------------------------------------------\n");
	if (message != None):
		sys.stderr.write(message + "\n");
	sys.stderr.write("-----------------------------------------------------------------------\n");		  

def checkFileSize(filename):	
	return os.path.getsize(filename)
	
def convert_bytes(bytes):
	bytes = float(bytes)
	if bytes >= 1099511627776:
		terabytes = bytes / 1099511627776
		size = '%.2fT' % terabytes
	elif bytes >= 1073741824:
		gigabytes = bytes / 1073741824
		size = '%.2fG' % gigabytes
	elif bytes >= 1048576:
		megabytes = bytes / 1048576
		size = '%.2fM' % megabytes
	elif bytes >= 1024:
		kilobytes = bytes / 1024
		size = '%.2fK' % kilobytes
	else:
		size = '%.2fb' % bytes
	return size
	
def runCommand(call_args):
		try:
			command = "";
			for item in call_args:
				command = command + " " + item;
			outputMessage("Running Process:" + command);
			process = subprocess.check_output(command, shell=True)
			outputMessage(process);
		except:		
			traceback.print_exc()	
		
def runProcess(call_args):
		try:
			command = "";
			for item in call_args:
				command = command + " " + item;
			outputMessage("Running Process:" + command);
			process = subprocess.Popen(call_args, stdin=subprocess.PIPE)
			process.wait();
			
		except:		
			traceback.print_exc()
		
if __name__ == '__main__':
		main()
