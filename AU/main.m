//
//  main.m
//  AwesomeAUGraphPlayer
//
//  Created by macbook on 18/06/15.
//  Copyright (c) 2015 home. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <AudioToolbox/AudioToolbox.h>
#define kInputFileLocation CFSTR("/Users/macbook/Desktop/george-cosbuc.wav")


#pragma mark user-data struct

typedef struct AwesomeAUGraphPlayer
{
    AudioStreamBasicDescription  inputFormat;
    AudioFileID inputFile;
    
    AUGraph graph;
    AudioUnit fileAU;

} AwesomeAUGraphPlayer;


#pragma mark utility functions

/* error checking */
static void CheckError(OSStatus error, const char *operation)
{
    if(error == noErr) return;
    
    char errorString[20];
    
    /* check for 4-char-error-codes */
    *(UInt32 *)(errorString +1) = CFSwapInt32HostToBig(error);
    if(isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4]))
    {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else
        sprintf(errorString, "%d", (int) error);
    
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    
    exit(1);
}

/* create awesome graph */
void CreateAwesomeAUGraph(AwesomeAUGraphPlayer *player)
{
    CheckError(NewAUGraph(&player->graph),
               "NewAUGraph failed");
    
    /* generate description for output device */
    
    AudioComponentDescription outputcd = {0};
    outputcd.componentType = kAudioUnitType_Output;
    outputcd.componentSubType = kAudioUnitSubType_DefaultOutput;
    outputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    /* add a node with the above description on the graph */
    
    AUNode outputNode;
    CheckError(AUGraphAddNode(player->graph, &outputcd, &outputNode),
               "AUGraphAddNode[kAudioUnitSubType_defaultOutput] failed");
    
    /* create the description for audio player */
    AudioComponentDescription filePlayercd = {0};
    filePlayercd.componentType = kAudioUnitType_Generator;
    filePlayercd.componentSubType = kAudioUnitSubType_AudioFilePlayer;
    filePlayercd.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    /* add player node to graph */
    
    AUNode fileNode;
    CheckError(AUGraphAddNode(player->graph, &filePlayercd, &fileNode),
               "AUGraphAddNode[kAudioUnitSubType_AudioFilePlayer] failed");
    
    /* open the graph - this does not allocate the resources yet, it only opens the connected AU */
    
    CheckError(AUGraphOpen(player->graph), "AUGraphOpen failed");
    
    /* get a reference to the AudioUnit object for the file player graph node */
    
    CheckError(AUGraphNodeInfo(player->graph,
                               fileNode,
                               NULL,
                               &player->fileAU),
               "AUGraphNodeInfo failed");
    
    /* connect the output source to input source of the output node */
    
    CheckError(AUGraphConnectNodeInput(player->graph,
                                       fileNode,
                                       0,
                                       outputNode,
                                       0),
               "AUGraphConnectNodeInput");
    
    /* initialize the graph - allocate resources */
    
    CheckError(AUGraphInitialize(player-> graph),
               "AUGraphInitialize failed");
}

Float64 PrepareFileAU(AwesomeAUGraphPlayer *player)
{
    /* tell the file player to load the file we want to play */
    CheckError(AudioUnitSetProperty(player->fileAU,
                                    kAudioUnitProperty_ScheduledFileIDs,
                                    kAudioUnitScope_Global,
                                    0,
                                    &player->inputFile,
                                sizeof(player->inputFile)),
               "AudioUnitSetProperty[kAudioUnitProperty_ScheduledFileIds] failed");
    
    /* schedule a region for the file to play */
    
    UInt64 nPackets;
    UInt32 propsize = sizeof(player-> inputFile);
    
    CheckError(AudioFileGetProperty(player->inputFile,
                                    kAudioFilePropertyAudioDataPacketCount,
                                    &propsize,
                                    &nPackets),
               "AudioFileGetProperty[kAudioFilePropertyAudioDataPacketCount] failed");
    
    /* tell the file player to play the whole file */
    
    ScheduledAudioFileRegion rgn ;
    memset(&rgn.mTimeStamp, 0, sizeof(rgn.mTimeStamp));
    rgn.mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
    rgn.mTimeStamp.mSampleTime = 0;
    rgn.mCompletionProc = NULL;
    rgn.mCompletionProcUserData = NULL;
    rgn.mAudioFile = player->inputFile;
    rgn.mLoopCount = 1;
    rgn.mStartFrame = 0;
    rgn.mFramesToPlay = nPackets * player->inputFormat.mFramesPerPacket;
    
    CheckError(AudioUnitSetProperty(player->fileAU, kAudioUnitProperty_ScheduledFileRegion,
                                    kAudioUnitScope_Global,
                                    0,
                                    &rgn,
                                    sizeof(rgn)),
               "AudioUnitSetProperty[kAudioUnitProperty_scheduledFileRegion] failed");
    
    /* tell the player AU when to start playing / -1sample time = render cycle */
    
    AudioTimeStamp startTime;
    memset(&startTime, 0, sizeof(startTime));
    startTime.mFlags = kAudioTimeStampSampleTimeValid;
    startTime.mSampleTime = -1;
    
    CheckError(AudioUnitSetProperty(player->fileAU,
                                    kAudioUnitProperty_ScheduleStartTimeStamp,
                                    kAudioUnitScope_Global,
                                    0,
                                    &startTime,
                                    sizeof(startTime)),
               "AudioUnitSetProperty[kAudioUnitProperty_ScheduleStartTimeStamp] failed");
    
    return (nPackets * player->inputFormat.mFramesPerPacket)/player->inputFormat.mSampleRate;
    
}


//7.7-7.13
//7.14 - 7.17


#pragma mark main function

int main(int argc, const char * argv[])
{

    /* open the input audio & get the audio data format from file */
    
    CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                          kInputFileLocation,
                                                          kCFURLPOSIXPathStyle,
                                                          false);
    AwesomeAUGraphPlayer player = {0};
    
    /* open the input audio file */
    
    CheckError(AudioFileOpenURL(inputFileURL,
                                kAudioFileReadPermission,
                                0,
                                &player.inputFile),
               "AudioFileOpenURL failed");

    CFRelease(inputFileURL);
    
    /* get audio data format */
    UInt32 propSize = sizeof(player.inputFormat);
    
    CheckError(AudioFileGetProperty(player.inputFile,
                                    kAudioFilePropertyDataFormat,
                                    &propSize,
                                    &player.inputFormat),
               "Could not get file's data format");
    
    /* build a fileplayer - speakers graph*/
    CreateAwesomeAUGraph(&player);
    
    /* configure file player */
    
    Float64 fileDuration = PrepareFileAU(&player);
    
    /* start playing */
    CheckError(AUGraphStart(player.graph),
               "AUGraphStart failed");
    
    /* sleep */
    usleep((int) fileDuration * 1000.0*1000.0);
    
    /* cleanup */
    
cleanup:
    AUGraphStop(player.graph);
    AUGraphUninitialize(player.graph);
    AUGraphClose(player.graph);
    AudioFileClose(player.inputFile);
    
    
    return 0;
}
