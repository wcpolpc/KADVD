
'''
Created on 12 Jan 2012

@author: dev
'''
from libxml2 import readFile

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
import re
import math
from random import choice

readabletitles=[];
globtitles=[];
totalDVDSize=0;
downloadLinks=[];

def main():
	
	parser = OptionParser(usage="%prog [options] -t [] -o [] -p []",
						  description="Compiles DVDs for Khan Academy")
	parser.add_option("-p", "--playlist", default="",
					  help="The playlist you want to transform into a DVD")
	parser.add_option("-e", "--python", default=(sys.executable if platform.system() == "Windows" else "python"), help="Path of python executable.")
	parser.add_option("-s", "--skip", default='y', help="Whether to skip downloading files")
	parser.add_option("-v", "--videos", default='../videos', help="Location of the videos directory")
	parser.add_option("-b", "--background", default='../common_files/menu_template.jpg', help="Location of the Background image for the main menu")
	parser.add_option("-o", "--output", default='', help="Location of the output for the DVD")
	parser.add_option("-c", "--clean", default='n', help="Cleans the output")
	parser.add_option("-m", "--remake", default='n', help="Reconverts mp4 videos to mpeg")
	parser.add_option("-d","--download", default='n', help="Cleans the output")
	parser.add_option("-t", "--common", default='', help="directory for common template xml and background image files")
	parser.add_option("-x", "--sample", default='', help="Perform a sample run")
	#parser.add_option("-r", "--recreate", default='n', help="Recreate menu mpegs")
	parser.add_option("-f", "--redownload", default='y', help="Automatically re-download failed downloads")
	
	
	(options, args) = parser.parse_args()
	
	##TODO checks!
	
	
	if options.playlist == "" or options.output == "" or options.common == "" :
		parser.print_help()
		return
	else:
		if  not os.path.exists(options.common):
			raise  IOError("File not found" + options.common);
		#if options.skip=='n':
		#	downloadVideos(options);
		createWorkingFolder(options);
		getPlayListFromAPI(options);
		downloadVideos(options);
		dvdpoints=convertVideos(options)
		dvdindex=1;
		for point in dvdpoints:
			start=point[0];
			end=point[1];
			createRootMenu(options,start,end);
			createTitlesets(options,start,end,dvdindex);
			createTitles(options,start,end,dvdindex);
			createBackgroundMenuImages(options,start,end,dvdindex);
			checkForRequiredMpegs(options,dvdindex);
			runDVDAuth(options,dvdindex);
			dvdindex=dvdindex+1;
		
def createWorkingFolder(options):
	if  not os.path.exists(options.output):
		outputMessage("Creating Output")
		os.makedirs(options.output)
	#if clean specified recreate it   
	if options.clean == 'y':
		outputMessage("Cleaning Output")
		shutil.rmtree(options.output, ignore_errors=True);
		os.makedirs(options.output)

def checkForRequiredMpegs(options,index):
	f = open(options.output+"/dvd"+str(index)+".xml", "r")
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
		##ignore background/menu mpegs, we will create them later
		if("background" in mpeg):
			continue;
		fileneeded = options.output + "/" + mpeg;
		if not os.path.exists(fileneeded):
			raise IOError("Cannot continue! Some files have not been converted properly or cannot be found:" + fileneeded)

def getPlayListFromAPI(options):
	
	outputMessage("Reading Playlist from API")
	httpServ = httplib.HTTPConnection("www.khanacademy.org", 80)
	httpServ.connect()
	httpServ.request('GET', "/api/v1/playlists/library/list")

	
	
	response = httpServ.getresponse()
	if response.status == httplib.OK:
		if(options.sample=='y'):
			result = readFile('./playlist'); # just read a local copy
		else:
			result = response.read();
		playlistitems = json.loads(result);
		filename = '';
		count = 0;
		names=[];
		if(len(playlistitems)==0):# in case the API is down
			raise IOError('API Playlist is empty');
		for topic in playlistitems:
		   if (topic['title']==options.playlist):
			for item in topic['videos']:
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
	
	
				
def checkFileDownloadedCorrectly(options, playlistfile, filename,count):	
	
	if(count>=5):
		raise IOError('Failed to download video '+ playlistfile + 'max retries exceeded.')
	
	#todo max retries
	site = urllib.urlopen(playlistfile)
	meta = site.info()
	expected=int(meta.getheaders("Content-Length")[0]);	
	outputMessage ("Content-Length for file :"+playlistfile+" is "+ str(expected))	
	f = open(filename, "r")
	actual=len(f.read())
	outputMessage("File on disk: "+ str(actual))
	f.close()	
	if(expected != actual):
		if(options.redownload=='y'):
			outputMessage ("Incomplete download detected will retry file :"+ filename +" from url " +playlistfile);
			downloadVideos(options, playlistfile,filename);
		else:
			raise IOError("Downloaded file: " +filename+"  does match expected size: " + str(expected))	
	
						# do nothing for existing files
				
def downloadVideos(options):  
	
	for pairedInfo in downloadLinks:
		if os.path.exists(pairedInfo[1]):
				#clean and re-download
				if options.download == "y":
					runProcess(["rm", pairedInfo[1]]);
					outputMessage("I removed existing MP4 file: " + pairedInfo[1])
					#downloadAndConvertFile(options, playlistfile, pairedInfo)
				else:
					#TODO check file sizes match
					outputMessage("MP4 file already exists will not bother to re-download it: " + pairedInfo[1])
					##check file sizes match anyway before converting
					continue;
		outputMessage ("Downloading file: "+pairedInfo[0])
 		urllib.urlretrieve(pairedInfo[0], pairedInfo[1]);
		checkFileDownloadedCorrectly(options,pairedInfo[0],pairedInfo[1],0);

def convertVideos(options):
	outputMessage ("Converting Videos")
	dvdindex=0;
	dvdpoints=[];
	dvdstart=0;
	dvdend=1;
	item=1;
	for pairedInfo in downloadLinks:
		convertvideo(options,pairedInfo[1]);
		global totalDVDSize;
		#TODO check size BEFORE convert Video to prevent overflow of Disk!?
		if(totalDVDSize>4300000000):#1136314880):
			dvdend=item+1; # because the for loop is not inclusive of the last element so +1
			dvdpoints.append([dvdstart,dvdend])
			dvdstart=item+1;
			totalDVDSize=0;
		item=item+1;
	
	dvdend=item-1;
	dvdpoints.append([dvdstart,dvdend])
	return dvdpoints;
			
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
			outputMessage("Mpeg file already exists will not bother to re-make it: " + mpegFile)
			updateTotalDVDSize(mpegFile);
			return;
	outputMessage("Converting " + filename)
	
	#call_args=["ffmpeg","-i",filename,"-f","dvd","-r","25","-ar","48000","-vf","setsar=1:1,scale=iw-40:ih-40,pad=iw+40:ih+40:20:20:violet,setdar=16:9","-b:v","6000000","-maxrate","9000000","-bufsize","1835008","-packetsize","2048","-muxrate","10080000","-b:a","448000","-c:v","mpeg2video","-c:a","ac3","-g","15","-pix_fmt","yuv420p","-minrate","0","-qmin","3","-y",mpegFile]
	call_args = ["ffmpeg", "-i", filename,  "-ar","48000","-vf","setsar=1:1,scale=iw-80:ih-40,pad=iw+80:ih+40:40:20:black,setdar=16:9 ","-target", "pal-dvd","-y",mpegFile]; #TODO - aspect 16:9 - keep padding in ratio 80:64
	#call_args = ["ffmpeg", "-i", filename,  "-r","25","-ar","48000","-b:v" ,"1536k", "-qmin", "3",	"-vf","setsar=1:1,scale=iw-40:ih-40,pad=iw+40:ih+40:20:20:violet,setdar=16:9 ","-y",mpegFile,];
#	call_args = ["ffmpeg", "-i", filename, "-target", "pal-dvd", "-ar","48000",	"-vf","setdar=16:9","-vf","scale=iw*min(720/iw\,576/ih):ih*min(720/iw\,576/ih),pad=720:576:(720-iw)/2:(576-ih)/2:violet","-y",mpegFile,];
	#call_args = ["ffmpeg", "-i", filename, "-target", "pal-dvd", "-ar","48000",	"-vf","setdar=16:9","-padtop","10","-padbottom","10","-padcolor","002020","-y",mpegFile,];
	runProcess(call_args);
	time.sleep(2);
	updateTotalDVDSize(mpegFile);
	
def updateTotalDVDSize(mpegFile):
	global totalDVDSize;
	totalDVDSize=totalDVDSize+ checkFileSize(mpegFile)
	outputMessage("Approx Current DVD size "+ str(convert_bytes(totalDVDSize)))	
	

def checkFileSize(filename):	
	##check the size and add it to the total DVD size
	return os.path.getsize(filename)
	#f = open(filename, "r")
	#actual=len(f.read())
	#outputMessage("File on disk: "+ str(actual))
	#f.close()
	#return actual;	
	
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


	
	
	
			
	

def createRootMenu(options,start,end):
	#create the main menu
	im = Image.open(options.background);
	draw = ImageDraw.Draw(im)
	position=60;
	font=getFont();
	menuplus=1;
	titleindex=0;
	for title in range(start,end):
		if(titleindex%14==0 and titleindex!=0):
			draw.text((100, position), "Videos Part "+ str(menuplus), font=font, fill=(255,255,255))
			menuplus=menuplus+1;
			position=position+34
		titleindex=titleindex+1;
	#draw the final text
	draw.text((100, position), "Videos Part "+ str(menuplus), font=font, fill=(255,255,255))
	backFile=options.output +"/mainmenu.jpg";
	im.save(backFile , "JPEG",quality=95);
	
	createMainMenu(options, backFile,"mainmenu",menuplus,1); 
		 

def createTitlesets(options,start,end,dvdindex):
	
	buttonText="";#the text for the template control file
	titleplus=1;
	titleindex=0;
	for title in range(start,end):
		if(titleindex%14==0 and titleindex!=0):
			buttonText=buttonText+"<button>jump titleset "+str(titleplus)+" menu;</button>"+"\n";
			titleplus=titleplus+1;
		titleindex=titleindex+1;
			
	#write the final one
	buttonText=buttonText+"<button>jump titleset "+str(titleplus)+" menu;</button>"+"\n";
	text = readFile(options.common+"/template.xml")
	text = text.replace('@a',buttonText);
	outputDVDXML=options.output + '/dvd'+str(dvdindex)+'.xml';
	writeToFile(outputDVDXML, text)
	
	
def writeToFile(mfile,text):	  
	
	f = open(mfile, "w")
	f.write(text);
	f.close()
def readFile(mfile):
	f = open(mfile, "r")
	text = f.read()
	text = text.rstrip();
	f.close();
	return text;

def createTitles(options,start,end,dvdindex):
	titleText="";				  
	titles="";
	outputDVDXML=options.output+'/dvd'+str(dvdindex)+'.xml';
	buttonText=""
	buttonindex=1; # keep track of how many buttons are in this title
	titleindex=0;
	for title in range(start,end): 
			
		
		if(buttonindex%14==0 and buttonindex!=0):
			titles=flushTitleToTemplate(options, buttonText, titles, titleindex,titleText, dvdindex)
			titleText="";
			buttonText="";
			buttonindex=1;
			titleindex=titleindex+1;
		titleText=titleText+"<vob file=\""+readabletitles[title]+".mpeg\" pause=\"3\" />\n";
		buttonText=buttonText+"<button>jump title 1 chapter "+str(buttonindex)+";</button>"
		buttonindex=buttonindex+1;
	#write the final title
	titles=flushTitleToTemplate(options, buttonText,titles, titleindex,titleText, dvdindex)
	text=readFile(outputDVDXML)
	text = text.replace('@b',titles);
	writeToFile(outputDVDXML, text)
	

def flushTitleToTemplate(options,buttonText, titles,titleindex,titleText,dvdindex):
	buttonText=buttonText+"<button>jump vmgm menu entry title; </button>"
	text=readFile(options.common+"/template-titles.xml")
	first=  text.replace('@a',buttonText);
	second= first.replace('@x',str(titleindex))
	third= second.replace('@y',str(dvdindex))
	titles=titles+ third.replace('@b',titleText);
	return titles;
	
	
	
def getFont():
	#TODO package font 
	fontFile = "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf"
	font = ImageFont.truetype(fontFile, 16)
	return font;
		
		
	
def createBackgroundMenuImages(options,start,end,dvdindex):
	im = Image.open(options.background);
	position=60;
	draw = ImageDraw.Draw(im)
	menuindex=0;
	font=getFont();
	buttoncount=0;
	for title in range(start,end):
		
		
		
		if(buttoncount%13==0 and buttoncount!=0):##13 is the number of video items per menu
			#draw the return to  main menu button text
			draw.text((100, position), " << Return to main menu", font=font, fill=(255,255,255))
			backName="background-image-"+str(menuindex)+"-dvd-"+str(dvdindex); #eg bacground1	
			backFile=options.output +"/"+backName+".jpg";
			im.save(backFile , "JPEG",quality=95)   ;
			im = Image.open(options.background);
			position=60;
			menuindex=menuindex+1;
			del draw;
			draw = ImageDraw.Draw(im)
			createMainMenu(options, backFile, backName,(buttoncount+1),-1); #plus one is for the return to main menu button
			buttoncount=0;
		
		draw.text((100, position), globtitles[title], font=font, fill=(255,255,255))
		position=position+34
		buttoncount=buttoncount+1;
			
	#draw the return to  main menu button text
	draw.text((100, position), " << Return to main menu", font=font, fill=(255,255,255))
	#write the final menu
	backName="background-image-"+str(menuindex)+"-dvd-"+str(dvdindex); #eg bacground1	
	backFile=options.output +"/"+backName+".jpg";
	im.save(backFile , "JPEG",quality=95)   ;
	del draw;
	
	
	createMainMenu(options, backFile, backName,(buttoncount)+1,-1);#plus one for the return to main menu button
	

		 
			
		
	
	

			
def createMainMenu(options, backgroundFile,backName,numButtons,soundTrack):
	if(numButtons>14 ):
		raise IOError("There are too many buttons (>14) for the menu:"+str(numButtons));
	menuindex=numButtons;
	#Add text to the background
	menufile = options.common + "/menu"+str(menuindex)+".xml"; # use the menu with the appropriate number of buttons
	outputMessage("Creating background position=position+40menu  with menu file: "
				 +menufile+ " \n background JPEG: "
				  +backgroundFile 
				  + " \n and output filename: " 
				  +backName +" \n you are in dir: "+ os.getcwd()
				  + " with number of buttons: " +str(numButtons))
	soundtracks=["../common_files/David-Alexandra.mp2", "../common_files/Diana-Hot.mp2"]; 
	chosenTrack=""
	if(soundTrack==1):
		chosenTrack="../common_files/Galdson-Roots.mp2";
	else:
		chosenTrack=choice(soundtracks)
	
	
		
	#if os.path.exists(menufile) :
		#raise IOError("Menufile "+menufile+" does not exist!")
	
	
	outm2v = options.output + '/menu.m2v';
	outputfile=options.output + '/'+backName+'.mpeg';
	#TODO add clean flag
	#if os.path.exists(outputfile) and options.recreate == 'n':
#		outputMessage("Menu MPEG "+outputfile+" already exists, will not recreate unless clean option specified")
#		return;
	#no interlacing -I 0
	# call_args = ['jpegtopnm',options.output+'/back.jpg','|','ppmtoy4m','-n','1','-F','25:1','-I','t','-A','59:54','-L','-S','420mpeg2',
	#			 '|','mpeg2enc','-I','0','-f','8','-n','p','-o',outm2v,'|','mplex','-f','8','-o','/dev/stdout',outm2v,'../dvd_menus/silent.mp2','|','spumux','-v','2',menufile,'>',options.output+'menu.mpg'];
   
	##TODO SLEEPS are bad..maybe there is something better?
	p1 = Popen(['jpegtopnm', backgroundFile], stdout=PIPE)
	time.sleep(1)
	p2 = Popen(['ppmtoy4m', '-n', '1', '-F', '25:1', '-I', 't', '-A', '59:54', '-L', '-S', '420jpeg'], stdin=p1.stdout, stdout=PIPE)
	time.sleep(1)
	#-a 2 is 4:3
	p3 = Popen(['mpeg2enc', '-I', '0', '-f', '8', '-n', 'p','-a','2', '-o', outm2v], stdin=p2.stdout, stdout=PIPE)
	time.sleep(1)
	p4 = Popen(['mplex', '-f', '8', '-o', '/dev/stdout', outm2v, chosenTrack], stdin=p3.stdout, stdout=PIPE)
	time.sleep(1)
	FILE = open(outputfile, "w")
	time.sleep(1)
	p5 = Popen(['spumux', '-v', '2', menufile, ], stdin=p4.stdout, stdout=FILE)
	time.sleep(1)
	FILE.close();
	output = p5.communicate()[0]
	outputMessage(output);
   
def runDVDAuth(options,index):
	outputMessage("Running dvdauthor...");
	
	## go into the output directory
	currentpath = os.getcwd()
	os.chdir(options.output)
	dvdauthfile = "dvd"+str(index)+".xml"
	if not os.path.exists(dvdauthfile):
		raise IOError("DVD auth file " + dvdauthfile + " not found.");
	outputMessage("Now in directory: "+options.output);
	#-O instead of -o used to delete any previous output

	runProcess(["dvdauthor", "-O", "OUT"+str(index), "-x", dvdauthfile ]);
	#go back
	os.chdir(currentpath);
	
		
	
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
