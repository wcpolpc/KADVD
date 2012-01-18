
'''
Created on 12 Jan 2012

@author: dev
'''

""" Wrapper for uploading/downloading all the system-wide data """

import os, platform, sys
import subprocess
from optparse import OptionParser
import os
import glob
import  traceback
import shutil
from BeautifulSoup import BeautifulSoup
from subprocess import Popen, PIPE
import time
import Image, ImageDraw, ImageFont
import httplib
import simplejson as json
import urllib

def main():
	
	parser = OptionParser(usage="%prog [options] -i [] -o [] -p []",
						  description="Compiles DVDs for Khan Academy")
	parser.add_option("-p", "--playlist", default="",
					  help="The playlist you want to transform into a DVD")
	parser.add_option("-e", "--python", default=(sys.executable if platform.system() == "Windows" else "python"), help="Path of python executable.")
	parser.add_option("-s", "--skip", default='y', help="Whether to skip downloading files")
	parser.add_option("-v", "--videos", default='../videos', help="Location of the videos directory")
	parser.add_option("-b", "--background", default='../dvd_menus/menu_template.jpg', help="Location of the Background image for the main menu")
	parser.add_option("-o", "--output", default='', help="Location of the output for the DVD")
	parser.add_option("-c", "--clean", default='n', help="Cleans the output")
	parser.add_option("-m", "--remake", default='n', help="Cleans the output")
	parser.add_option("-d","--download", default='n', help="Cleans the output")
	parser.add_option("-i", "--input", default='', help="input DVDAuthor file")
	
	
	(options, args) = parser.parse_args()
	
	##TODO checks!
	
	
	if options.playlist == "" or options.output == "" or options.input == "" :
		parser.print_help()
		return
	else:
		if  not os.path.exists(options.input):
			raise  IOError("File not found" + options.input);
		#if options.skip=='n':
		#	downloadVideos(options);
		createWorkingFolder(options);
		getPlayListFromAPI(options);
		checkForRequiredMpegs(options);
		createMainMenu(options);
		runDVDAuth(options);
		
def createWorkingFolder(options):
	 if  not os.path.exists(options.output):
		 outputMessage("Creating Output")
		 os.makedirs(options.output)
	 #if clean specified recreate it   
	 if options.clean == 'y':
		 outputMessage("Cleaning Output")
		 shutil.rmtree(options.output, ignore_errors=True);
		 os.makedirs(options.output)
	 outputDVDXML=options.output + '/dvd.xml';
	 shutil.copy2(options.input, outputDVDXML);
	 shutil.copy2(options.input.replace('algebra1.xml', 'menu.xml'), options.output + '/menu.xml');
	 if not os.path.exists(outputDVDXML):
			raise IOError("DVDAuthor file not copied correctly and cannot be found:" + outputDVDXML)

def checkForRequiredMpegs(options):
	f = open(options.input, "r")
	text = f.read()
	text = text.rstrip();
	text = text.replace('\n', '')
	soup = BeautifulSoup(text, selfClosingTags=['vob'])
	fooId = soup.findAll("vob")
	
	mpegs = [];
	#value = fooId['file']
	for foo in fooId:
		for attr, value in foo.attrs:
			if(attr == "file"):
				mpegs.append(value)
	
	for mpeg in mpegs:
		if(mpeg == "menu.mpg"):
			continue;
		fileneeded = options.output + "/" + mpeg;
		if not os.path.exists(fileneeded):
			raise IOError("Cannot continue! Some files have not been converted properly or cannot be found:" + fileneeded)

def getPlayListFromAPI(options):
	httpServ = httplib.HTTPConnection("www.khanacademy.org", 80)
	httpServ.connect()
	httpServ.request('GET', "/api/v1/playlists/Algebra/videos")

	response = httpServ.getresponse()
	if response.status == httplib.OK:
		print "Output from HTML request"
		result = response.read();
		playlistitems = json.loads(result);
		filename = '';
		count = 0;
		for item in playlistitems:
			playlistfile = item['download_urls']['mp4'];
			name = item['readable_id'];
			filename = options.output + "/" + name + ".mp4"; 
			#TESTING
			count = count + 1;
			if(count > 4):
				return;
			##if the file already exists and the clean option is not used don't bother re-downloading
			if os.path.exists(filename):
				#clean and re-download
				if options.download == "y":
					runProcess(["rm", filename]);
					outputMessage("I removed existing MP4 file: " + filename)
					downloadAndConvertFile(options, playlistfile, filename)
				else:
					outputMessage("MP4 file already exists will not bother to re-download it: " + filename)
					convertvideo(options, filename)
					continue;
			else: 
				downloadAndConvertFile(options, playlistfile, filename)
		   
				
				
						# do nothing for existing files
				
def downloadAndConvertFile(options, playlistfile, filename):  
	outputMessage("Retrieving file ..." + playlistfile);
	urllib.urlretrieve(playlistfile, filename);
	convertvideo(options, filename);		  
			
def outputMessage(message):
	sys.stderr.write("-----------------------------------------------------------------------\n");
	if (message != None):
		sys.stderr.write(message + "\n");
	sys.stderr.write("-----------------------------------------------------------------------\n");		  

def convertvideo(options, filename):
	
	mpegFile = filename.replace("mp4", "mpeg");
	
	if os.path.exists(mpegFile):
		if options.remake == "y":
			runProcess(["rm", mpegFile]);
			outputMessage("I removed existing MPEG file: " + mpegFile)
		else:
			# do nothing for existing files
			outputMessage("Mepg file already exists will not bother to re-make it: " + mpegFile)
			return;
	outputMessage("Converting " + filename)
	call_args = ["ffmpeg", "-i", filename, "-target", "pal-dvd", mpegFile,"-ar","48000","-acodec","TrueHD"];
	runProcess(call_args);
	time.sleep(2)


def renderBackground(options):
	im = Image.open(options.background)

	draw = ImageDraw.Draw(im)
    #TODO package font 
	fontFile = "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf"
	font = ImageFont.truetype(fontFile, 16)
	draw.text((53, 55), 'Hello Worlds!', font=font, fill=(255,255,255))
	
	del draw
	im.save(options.output + '/back.jpg', "JPEG",quality=95)
    
	

			
def createMainMenu(options):
	#Add text to the background
   renderBackground(options);
   menufile = options.output + "/menu.xml";
   outputMessage("Creating background menu. with menu file: " +menufile)
   outm2v = options.output + '/menu.m2v';
   #no interlacing -I 0
   # call_args = ['jpegtopnm',options.output+'/back.jpg','|','ppmtoy4m','-n','1','-F','25:1','-I','t','-A','59:54','-L','-S','420mpeg2',
   #			 '|','mpeg2enc','-I','0','-f','8','-n','p','-o',outm2v,'|','mplex','-f','8','-o','/dev/stdout',outm2v,'../dvd_menus/silent.mp2','|','spumux','-v','2',menufile,'>',options.output+'menu.mpg'];
   
   ##TODO SLEEPS are bad..maybe there is something better?
   p1 = Popen(['jpegtopnm', options.output + '/back.jpg'], stdout=PIPE)
   time.sleep(1)
   p2 = Popen(['ppmtoy4m', '-n', '1', '-F', '25:1', '-I', 't', '-A', '59:54', '-L', '-S', '420jpeg'], stdin=p1.stdout, stdout=PIPE)
   time.sleep(1)
   p3 = Popen(['mpeg2enc', '-I', '0', '-f', '8', '-n', 'p', '-o', outm2v], stdin=p2.stdout, stdout=PIPE)
   time.sleep(1)
   p4 = Popen(['mplex', '-f', '8', '-o', '/dev/stdout', outm2v, '../dvd_menus/silent.mp2'], stdin=p3.stdout, stdout=PIPE)
   time.sleep(1)
   FILE = open(options.output + '/menu.mpg', "w")
   time.sleep(1)
   p5 = Popen(['spumux', '-v', '2', menufile, ], stdin=p4.stdout, stdout=FILE)
   time.sleep(1)
   FILE.close();
   output = p5.communicate()[0]
   outputMessage(output);
   
   #runCommand(call_args)
   
def runDVDAuth(options):
	outputMessage("Running dvdauthor...");
	
	## go into the output directory
	currentpath = os.getcwd()
	os.chdir(options.output)
	dvdauthfile = "dvd.xml";
	if not os.path.exists(dvdauthfile):
		raise IOError("DVD auth file " + dvdauthfile + " not found.");
	outputMessage("Now in directory"+options.output);
	#-O instead of -o used to delete any previous output
	runProcess(["dvdauthor", "-O", "OUT", "-x", dvdauthfile ]);
	#go back
	os.chdir(currentpath);
	
def downloadVideos(options):
	call_args = [options.python, options.download, options.playlist];
	outputMessage('DOWNLOADING...................................');
	runProcess(call_args);
   
		
	
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
