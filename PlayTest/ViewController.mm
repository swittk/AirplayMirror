//
//  ViewController.m
//  PlayTest
//
//  Created by hc on 2017/12/29.
//  Copyright © 2017年 hc. All rights reserved.
//

#import "ViewController.h"
#import "VideoDecoder.h"
#import "airplay_mirror.h"
#import "AudioBufferPlayer.h"

@interface ViewController ()

@property (weak) IBOutlet PlayerView* playerView;
@property (strong) VideoDecoder* videoDecoder;
@property (strong) AudioBufferPlayer* audioBufferPlayer;
@property (strong) NSMutableArray<NSData*>* bufferQueue;

- (void)displayFrame:(CVPixelBufferRef)pixelBuffer;
- (NSData*)getPCM;
- (void)addPCM:(NSData*)data;
@end


void video_data_receive(unsigned char* buffer, long buflen, int payload,void* ref){
    
    @autoreleasepool{
        ViewController* vc = (__bridge ViewController*)ref;
        if (payload == 1){
            //sps
            long sps_size = buffer[6] << 8 | buffer[7];
            NSMutableData* sps = [NSMutableData dataWithCapacity:sps_size];
            [sps appendBytes:&buffer[8] length:sps_size];
            
            //pps
            long pps_size = buffer[9+sps_size] << 8 | buffer[10+sps_size];
            NSMutableData* pps = [NSMutableData dataWithCapacity:pps_size];
            [pps appendBytes:&buffer[11+sps_size] length:pps_size];
            
            if (vc.videoDecoder == nil)
                vc.videoDecoder = [VideoDecoder new];
            
            [vc.videoDecoder setupWithSPS:sps pps:pps];
            
            __weak typeof(vc) weakVC = vc;
            vc.videoDecoder.newFrameAvailable = ^(CVPixelBufferRef pixelBuffer) {
                if (pixelBuffer)
                    [weakVC displayFrame:pixelBuffer];
            } ;
        }else{
            [vc.videoDecoder decodeFrame:buffer bufferLen:buflen];
        }
    }
}

void audio_did_start(void* ref){
    @autoreleasepool{
        ViewController* vc = (__bridge ViewController*)ref;
        if (vc.audioBufferPlayer == nil){
            __weak typeof(vc) weakVC = vc;
            vc.audioBufferPlayer = [[AudioBufferPlayer alloc] initWithSampleRate:44100 channels:2 bitsPerChannel:16 packetsPerBuffer:480];
            vc.audioBufferPlayer.block = ^(AudioQueueBufferRef buffer, AudioStreamBasicDescription audioFormat) {
                
                NSData* data = [weakVC getPCM];
                if (data){
                    memcpy(buffer->mAudioData, data.bytes, data.length);
                    buffer->mAudioDataByteSize = (UInt32)data.length;
                }else{
                    memset(buffer->mAudioData,0,buffer->mAudioDataBytesCapacity);
                    buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
                }
            };
            
            [vc.audioBufferPlayer start];
        }
    }
}

void audio_did_stop(void* ref){
    @autoreleasepool{
        ViewController* vc = (__bridge ViewController*)ref;
        [vc.audioBufferPlayer stop];
        vc.audioBufferPlayer = nil;
    }
}

void audio_data_receive(unsigned char* buffer, long buflen, void* ref){
    @autoreleasepool{
        ViewController* vc = (__bridge ViewController*)ref;
        [vc addPCM:[NSData dataWithBytes:buffer length:buflen]];
    }
}

@implementation ViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

- (NSData*)getPCM{
    NSData* data = nil;
    
    @synchronized (_bufferQueue){
        if (_bufferQueue.count){
            data = _bufferQueue.firstObject;
            [_bufferQueue removeObjectAtIndex:0];
        }
    }
    
    return data;
}

- (void)addPCM:(NSData*)data{
    @synchronized (_bufferQueue){
        [_bufferQueue addObject:data];
    }
}

- (IBAction)startOrStop:(id)sender{
    NSToolbarItem* item = (NSToolbarItem*)sender;
    if (item.tag == 0){
        item.tag = 1;
        [item setLabel:@"Stop"];
        [item setImage:[NSImage imageNamed:@"NSStatusUnavailable"]];
        mirror_context context;
        context.video_data_receive = video_data_receive;
        context.audio_data_receive = audio_data_receive;
        context.audio_did_start = audio_did_start;
        context.audio_did_stop = audio_did_stop;
        context.airplay_did_stop = NULL;
        strcpy(context.name, "AirPlay");
        context.width = 1280;
        context.height = 720;
        context.ref = (__bridge void*)self;
        
        _bufferQueue = [NSMutableArray arrayWithCapacity:10];
        start_mirror(&context);
    }else{
        item.tag = 0;
        [item setLabel:@"Start"];
        [item setImage:[NSImage imageNamed:@"NSStatusAvailable"]];
        
        stop_mirror();
    }
}

- (void)displayFrame:(CVPixelBufferRef)pixelBuffer{
    [_playerView display:pixelBuffer];
}
@end
