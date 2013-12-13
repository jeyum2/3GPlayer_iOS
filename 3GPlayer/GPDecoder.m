//
//  GPDecoder.h
//  Source : "amrnb-dec.c" in test of opencore-amr
//

#import "GPDecoder.h"
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "wavwriter.h"
#include "interf_dec.h"

@implementation GPDecoder

/* From WmfDecBytesPerFrame in dec_input_format_tab.cpp */
const int sizes[] = { 12, 13, 15, 17, 19, 20, 26, 31, 5, 6, 5, 5, 0, 0, 0, 0 };

-(BOOL)decodeWith:(NSString *)sourcePath To:(NSString *)targetPath
{
    NSLog(@"Original Path : %@",sourcePath);
    NSData *mdat = nil;
    NSData *data = [NSData dataWithContentsOfFile:sourcePath];

    NSRange containerLengthRange;
    containerLengthRange.length = 4;
    containerLengthRange.location = 0;
    
    NSUInteger dataLength =  [data length];
    NSLog(@"Data Length %lu", (unsigned long)dataLength);
    while(true)
    {
        NSData *subData = [data subdataWithRange:containerLengthRange];
        if(!subData)
        {
            NSLog(@"Read length fail at %lu",(unsigned long)containerLengthRange.location);
            break;
        }

        uint32_t length = *(const uint32_t *)[subData bytes];
        length = CFSwapInt32(length);

        containerLengthRange.location += 4;
        subData = [data subdataWithRange:containerLengthRange];
        if(!subData)
        {
            NSLog(@"Read type fail at %lu",(unsigned long)containerLengthRange.location);
            break;
        }
        NSString *type = [NSString stringWithUTF8String:[subData bytes]];
        
        NSLog(@"Position : %lu, Length : %u, Type : %@", (unsigned long)containerLengthRange.location - 4, length, type);
// Skip "moov" tag
//        if([type isEqualToString:@"moov"])
//        {
//            NSRange moovString;
//            moovString.length = length - 8;
//            moovString.location =  containerLengthRange.location + 4;
//            NSLog(@"Moov : %@",[NSString stringWithUTF8String:[data subdataWithRange:moovString].bytes]);
//        }
        if([type isEqualToString:@"mdat"])
        {
            NSRange subDataRange;
            subDataRange.length = length - 8;
            subDataRange.location =  containerLengthRange.location + 4;
            mdat = [data subdataWithRange:subDataRange];
        }

        containerLengthRange.location += (length - 4);
        if(containerLengthRange.location == dataLength)
        {
            NSLog(@"Reached End");
            break;
        }else if(containerLengthRange.location > dataLength)
        {
            NSLog(@"Broken file : can't read %lu of %lu", (unsigned long)containerLengthRange.location, (unsigned long)dataLength);
            break;
        }
    }
    if(!mdat)
    {
        NSLog(@"Can't find mdat");
        return NO;
    }
    
    
	void *wav, *amr;
    size_t lengthOfMdat = [mdat length];
    uint8_t* arMdat = (uint8_t *)[mdat bytes];
    NSRange packetRange;
    packetRange.length = 0;
    packetRange.location = 0;
    
	wav = wav_write_open(targetPath.UTF8String, 8000, 16, 1);
    
	if (!wav) {
        NSLog(@"Unable to open %@", targetPath);
        return NO;
	}
    
	amr = Decoder_Interface_init();
    
	while (1) {
		uint8_t littleendian[320], *ptr;
		int16_t outbuffer[160];
		/* Find the packet size */
        packetRange.length = sizes[(arMdat[packetRange.location] >> 3) & 0x0f];
        packetRange.length ++; //Include mode
        
        NSLog(@"Packet Size : %lu", (unsigned long)packetRange.length);
        
        NSData *packetData = [mdat subdataWithRange:packetRange];
		/* Decode the packet */
		Decoder_Interface_Decode(amr, (const unsigned char*)[packetData bytes], outbuffer, 0);
        
		/* Convert to little endian and write to wav */
		ptr = littleendian;
		for (int i = 0; i < 160; i++) {
			*ptr++ = (outbuffer[i] >> 0) & 0xff;
			*ptr++ = (outbuffer[i] >> 8) & 0xff;
		}
		wav_write_data(wav, littleendian, 320);

        packetRange.location += (packetRange.length);

        if(packetRange.location == lengthOfMdat){
            NSLog(@"Reached end of mdat");
            break;
        }else if(packetRange.location > lengthOfMdat)
        {
            NSLog(@"Broken file in mdat");
            return NO;
        }
	}
	Decoder_Interface_exit(amr);
	wav_write_close(wav);
    return YES;
}

@end
