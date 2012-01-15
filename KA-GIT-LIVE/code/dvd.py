
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

def main():
    
    parser = OptionParser(usage="%prog [options] upload|download", 
                          description="Compiles DVDs for Khan Academy")
    parser.add_option("-p", "--playlist", default="",
                      help="The playlist you want to transform into a DVD")
    parser.add_option("-e", "--python", default=(sys.executable if platform.system() == "Windows" else "python"), help="Path of python executable.")
    parser.add_option("-d", "--download", default='./download.py', help="Location of the download script")
    parser.add_option("-s", "--skip", default='y', help="Whether to skip downloading files")
    parser.add_option("-v", "--videos", default='../videos', help="Location of the videos directory")
    parser.add_option("-b", "--background", default='../dvd_menus/beena_khan_academy.jpg', help="Location of the Background image for the main menu")
    parser.add_option("-o", "--output", default='', help="Location of the output for the DVD")
    parser.add_option("-c", "--clean", default='n', help="Cleans the output")
    parser.add_option("-i", "--input", default='', help="input DVDAuthor file")
    
    
    (options, args) = parser.parse_args()
    
    ##TODO checks!
    
    
    if options.playlist =="" or options.output=="" or options.input=="" :
        parser.print_help()
        return
    else:
        if  not os.path.exists(options.input):
            raise  IOError("File not found"+options.input);
        #if options.skip=='n':
        #    downloadVideos(options);
        createWorkingFolder(options);
        identifyRequiredMpegs(options);
        createMainMenu(options);
        runDVDAuth(options);
        
def createWorkingFolder(options):
     if  not os.path.exists(options.output):
         outputMessage("Creating Output")
         os.makedirs(options.output)
     #if clean specified recreate it   
     if options.clean=='y':
         outputMessage("Cleaning Output")
         shutil.rmtree(options.output, ignore_errors=True);
         os.makedirs(options.output)
     shutil.copy2(options.input,options.output+'dvd.xml');
     shutil.copy2(options.input.replace('algebra1.xml','menu.xml'),options.output+'/menu.xml');

def identifyRequiredMpegs(options):
    f = open(options.input, "r")
    text = f.read()
    text=text.rstrip();
    text=text.replace('\n','')
    soup = BeautifulSoup(text, selfClosingTags=['vob'])
    fooId = soup.findAll("vob")
    
    mpegs=[];
    #value = fooId['file']
    for foo in fooId:
        for attr, value in foo.attrs:
            if(attr=="file"):
                mpegs.append(value)
    
    for mpeg in mpegs:
        flv=options.videos+"/"+options.playlist+"/"+mpeg.replace('.mpeg','.flv');
        if mpeg=='menu.mpg':
            continue;
        if not os.path.exists(flv):
            raise IOError("Cant find "+ flv)
        else:
            convertvideo(options,flv,mpeg)
            
            
        
                
    
   
    
    
            
def outputMessage(message):
    sys.stderr.write("-----------------------------------------------------------------------\n");
    if (message !=None):
        sys.stderr.write(message+"\n");
    sys.stderr.write( "-----------------------------------------------------------------------\n");          

def convertvideo(options,infile,mpeg):
    
    mpegFile=infile.replace("flv","mpeg");
    
    if os.path.exists(mpegFile) and options.clean=="y":
       runProcess(["rm",mpegFile]);
       outputMessage("I removed exising MPEG file: " + mpegFile)
    outputMessage( "Converting " + infile)
    dest=options.output+"/"+mpeg;
    call_args = ["ffmpeg", "-i",infile,"-target","pal-dvd",dest];
    runProcess(call_args);
    time.sleep(2)


def renderBackground(options):
    im = Image.open(options.background)

    draw = ImageDraw.Draw(im)
    fontFile = "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf"
    font = ImageFont.truetype(fontFile, 16)
    draw.text((53,55), 'Hello World!',font=font,fill=128)
    
    del draw
    im.save(options.output+'/back.jpg', "JPEG")
    

            
def createMainMenu(options):
  
   #Add text to the background
   renderBackground(options);
   menufile=options.output+"/menu.xml";
   outputMessage("Creating background menu..." )
   outm2v=options.output+'menu.m2v';
     #no interlacing -I 0
  # call_args = ['jpegtopnm',options.output+'/back.jpg','|','ppmtoy4m','-n','1','-F','25:1','-I','t','-A','59:54','-L','-S','420mpeg2',
   #             '|','mpeg2enc','-I','0','-f','8','-n','p','-o',outm2v,'|','mplex','-f','8','-o','/dev/stdout',outm2v,'../dvd_menus/silent.mp2','|','spumux','-v','2',menufile,'>',options.output+'menu.mpg'];
   
   ##TODO SLEEPS are bad..maybe there is something better?
   p1 = Popen(['jpegtopnm',options.output+'/back.jpg'], stdout=PIPE)
   time.sleep(1)
   p2 = Popen(['ppmtoy4m','-n','1','-F','25:1','-I','t','-A','59:54','-L','-S','420mpeg2'], stdin=p1.stdout, stdout=PIPE)
   time.sleep(1)
   p3 = Popen(['mpeg2enc','-I','0','-f','8','-n','p','-o',outm2v], stdin=p2.stdout, stdout=PIPE)
   time.sleep(1)
   p4 = Popen(['mplex','-f','8','-o','/dev/stdout',outm2v,'../dvd_menus/silent.mp2'], stdin=p3.stdout, stdout=PIPE)
   time.sleep(1)
   FILE = open(options.output+'menu.mpg',"w")
   time.sleep(1)
   p5 = Popen(['spumux','-v','2',menufile,], stdin=p4.stdout, stdout=FILE)
   time.sleep(1)
   FILE.close();
   output = p5.communicate()[0]
   outputMessage(output);
   
   #runCommand(call_args)
   
def runDVDAuth(options):
     outputMessage("Running dvdauthor...");
    
     ## go into the output directory
     currentpath=os.getcwd()
     os.chdir(options.output)
     dvdauthfile="dvd.xml";
     if not os.path.exists(dvdauthfile):
          sys.exit("DVD auth file "+ dvdauthfile+ " not found.");
    
     runProcess(["dvdauthor","-o","OUT","-x",dvdauthfile ]);
     #go back
     os.chdir(currentpath);
     
   
def downloadVideos(options):
    call_args = [options.python,options.download,options.playlist];
    outputMessage('DOWNLOADING...................................');
    runProcess(call_args);
   
        
    
def runCommand(call_args):
        try:
            command="";
            for item in call_args:
                command=command+" "+item;
            outputMessage("Running Process:" +command);
            process = subprocess.check_output(command, shell=True)
            outputMessage(process);
        except:        
            traceback.print_exc()    
        
def runProcess(call_args):
        try:
            command="";
            for item in call_args:
                command=command+" "+item;
            outputMessage("Running Process:" +command);
            process = subprocess.Popen(call_args, stdin=subprocess.PIPE)
            process.wait();
            
        except:        
            traceback.print_exc()
        
if __name__ == '__main__':
        main()