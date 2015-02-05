//
//  ImageSnap.m
//  ImageSnap
//
//  Created by Robert Harder on 9/10/09.
//  Updated by Sam Green for Mavericks (OSX 10.9) on 11/22/13
//

#import "ImageSnap.h"

@interface ImageSnap ()

/**
 * Writes an NSImage to disk, formatting it according
 * to the file extension. If path is "-" (a dash), then
 * an jpeg representation is written to standard out.
 */
+ (BOOL)saveImage:(NSImage *)image toPath:(NSString *)path;

/**
 * Converts an NSImage to raw NSData according to a given
 * format. A simple string search is performed for such
 * characters as jpeg, tiff, png, and so forth.
 */
+ (NSData *)dataFrom:(NSImage *)image asType:(NSString *)format;

@property (strong, nonatomic) AVCaptureSession			*session;
@property (strong, nonatomic) AVCaptureDeviceInput		*input;
@property (strong, nonatomic) AVCaptureVideoDataOutput	*output;

@end


@implementation ImageSnap

- (instancetype)init
{
	self = [super init];
    if (self)
	{
        _session = nil;
        _input = nil;
        _output = nil;
        
        mCurrentImageBuffer = nil;
    }
	
	return self;
}

- (void)dealloc
{
    CVBufferRelease(mCurrentImageBuffer);
}

// Returns an array of video devices attached to this computer.
+ (NSArray *)videoDevices
{
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:3];
    [results addObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]];
    [results addObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeMuxed]];
	
    return results;
}

// Returns the default video device or nil if none found.
+ (AVCaptureDevice *)defaultVideoDevice {
	AVCaptureDevice *device = nil;
    
    device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	if (device == nil )
	{
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeMuxed];
	}
	
    return device;
}

// Returns the named capture device or nil if not found.
+ (AVCaptureDevice *)deviceNamed:(NSString *)name
{
    AVCaptureDevice *result = nil;
    
    NSArray *devices = [ImageSnap videoDevices];
	for( AVCaptureDevice *device in devices )
	{
        if ( [name isEqualToString:[device description]] )
		{
            result = device;
        }
    }
    
    return result;
}


// Saves an image to a file or standard out if path is nil or "-" (hyphen).
+ (BOOL)saveImage:(NSImage *)image toPath:(NSString *)path
{
    NSString *ext = [path pathExtension];
    NSData *photoData = [ImageSnap dataFrom:image asType:ext];
    
    // If path is a dash, that means write to standard out
    if (path == nil || [@"-" isEqualToString:path] )
	{
        NSUInteger length = [photoData length];
        char *start = (char *)[photoData bytes];
		
        for( NSUInteger i = 0; i < length; ++i )
		{
            putc( start[i], stdout );
        }
		
        return YES;
    }
	else
	{
        return [photoData writeToFile:path atomically:NO];
    }
    
    return NO;
}


/**
 * Converts an NSImage into NSData. Defaults to jpeg if
 * format cannot be determined.
 */
+ (NSData *)dataFrom:(NSImage *)image asType:(NSString *)format
{
    NSData *tiffData = [image TIFFRepresentation];
    
    NSBitmapImageFileType imageType = NSJPEGFileType;
    NSDictionary *imageProps = nil;
    
    
    // TIFF. Special case. Can save immediately.
    if ([@"tif"  rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound ||
       [@"tiff" rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound )
	{
        return tiffData;
    }
    
    // JPEG
    else if ([@"jpg"  rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [@"jpeg" rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound )
	{
        imageType = NSJPEGFileType;
        imageProps = @{NSImageCompressionFactor: @0.9};
    }
    
    // PNG
    else if ([@"png" rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound )
	{
        imageType = NSPNGFileType;
    }
    
    // BMP
    else if ([@"bmp" rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound )
	{
        imageType = NSBMPFileType;
    }
    
    // GIF
    else if ([@"gif" rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound )
	{
        imageType = NSGIFFileType;
    }
    
    NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:tiffData];
    NSData *photoData = [imageRep representationUsingType:imageType properties:imageProps];
    
    return photoData;
}



/**
 * Primary one-stop-shopping message for capturing an image.
 * Activates the video source, saves a frame, stops the source,
 * and saves the file.
 */

+ (BOOL)saveSnapshotFrom:(AVCaptureDevice *)device toFile:(NSString *)path
{
    return [self saveSnapshotFrom:device toFile:path withWarmup:nil];
}

+ (BOOL)saveSnapshotFrom:(AVCaptureDevice *)device toFile:(NSString *)path withWarmup:(NSNumber *)warmup
{
    return [self saveSnapshotFrom:device toFile:path withWarmup:warmup withTimelapse:nil];
}

+ (BOOL)saveSnapshotFrom:(AVCaptureDevice *)device
                 toFile:(NSString *)path
             withWarmup:(NSNumber *)warmup
          withTimelapse:(NSNumber *)timelapse
{
    ImageSnap *snap;
    NSImage *image = nil;
    double interval = timelapse == nil ? -1 : [timelapse doubleValue];
    
    snap = [[ImageSnap alloc] init];            // Instance of this ImageSnap class
    DBNSLog(@"Starting device...");
    if ([snap startSession:device] ) // Try starting session
	{
        DBNSLog(@"Device started.");
        
        if (warmup == nil )
		{
            // Skip warmup
            DBNSLog(@"Skipping warmup period.");
        }
		else
		{
            double delay = [warmup doubleValue];
            DBNSLog(@"Delaying %.2lf seconds for warmup...",delay);
            NSDate *now = [[NSDate alloc] init];
            [[NSRunLoop currentRunLoop] runUntilDate:[now dateByAddingTimeInterval:delay]];
            DBNSLog(@"Warmup complete.");
        }
        
        if ( interval > 0 )
		{
            DBNSLog(@"Time lapse: snapping every %.2lf seconds to current directory.", interval);
            
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            [dateFormatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss.SSS"];
            
            // wait a bit to make sure the camera is initialized
            //[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow: 1.0]];
            
            for (unsigned long seq = 0; ; ++seq)
            {
                NSDate *now = [[NSDate alloc] init];
                NSString *nowstr = [dateFormatter stringFromDate:now];
                
                DBNSLog(@" - Snapshot %5lu", seq);
                DBNSLog(@" (%s)", [nowstr UTF8String]);
                
                // create filename
                NSString *filename = [NSString stringWithFormat:@"snapshot-%05lu-%s.jpg", seq, [nowstr UTF8String]];
                
                // capture and write
                image = [snap snapshot];                // Capture a frame
                if (image != nil)
				{
                    [ImageSnap saveImage:image toPath:filename];
                    DBNSLog(@"%@", filename);
                }
				else
				{
                    DBNSLog(@"Image capture failed.");
                }
                
                // sleep
                [[NSRunLoop currentRunLoop] runUntilDate:[now dateByAddingTimeInterval: interval]];
                
            }
            
        } else
		{
            image = [snap snapshot];                // Capture a frame
        }
        //NSLog(@"Stopping...");
        [snap stopSession];                     // Stop session
        //NSLog(@"Stopped.");
    }
    
    
    if ( interval > 0 ){
        return YES;
    } else {
        return image == nil ? NO : [ImageSnap saveImage:image toPath:path];
    }
}   // end


/**
 * Returns current snapshot or nil if there is a problem
 * or session is not started.
 */
- (NSImage *)snapshot
{
    DBNSLog(@ "Taking snapshot...");
	
    CVImageBufferRef frame = nil;               // Hold frame we find
    while( frame == nil ) // While waiting for a frame
	{
		DBNSLog(@ "\tEntering synchronized block to see if frame is captured yet...");
        @synchronized(self) // Lock since capture is on another thread
		{
            frame = mCurrentImageBuffer;        // Hold current frame
            CVBufferRetain(frame);              // Retain it (OK if nil)
        }
		DBNSLog(@ "Done." );
		
        if (frame == nil ) // Still no frame? Wait a little while.
		{
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow: 0.1]];
        }
    }
    
    // Convert frame to an NSImage
    NSCIImageRep *imageRep = [NSCIImageRep imageRepWithCIImage:[CIImage imageWithCVImageBuffer:frame]];
    NSImage *image = [[NSImage alloc] initWithSize:[imageRep size]];
    [image addRepresentation:imageRep];
	DBNSLog(@ "Snapshot taken." );
    
    return image;
}


/**
 * Blocks until session is stopped.
 */
- (void)stopSession
{
	DBNSLog(@"Stopping session..." );
    
    // Make sure we've stopped
    while( _session != nil )
	{
		DBNSLog(@"\tCaptureSession != nil");
        
		DBNSLog(@"\tStopping CaptureSession...");
        [_session stopRunning];
		DBNSLog(@"Done.");
        
        if ([_session isRunning] )
		{
			DBNSLog(@ "[mCaptureSession isRunning]");
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow: 0.1]];
        }
		else
		{
            DBNSLog(@ "\tShutting down 'stopSession(..)'" );
            
            _session = nil;
            _input = nil;
            _output = nil;
        }
        
    }
}


/**
 * Begins the capture session. Frames begin coming in.
 */
- (BOOL)startSession:(AVCaptureDevice *)device
{
	
	DBNSLog(@ "Starting capture session..." );
	
    if (device == nil )
	{
		DBNSLog(@ "\tCannot start session: no device provided." );
		return NO;
	}
    
    // If we've already started with this device, return
    if ([device isEqual:[_input device]] &&
       _session != nil &&
       [_session isRunning] )
	{
        return YES;
    }
    else if (_session != nil )
	{
		DBNSLog(@ "\tStopping previous session." );
        [self stopSession];
    }
	
	// Create the capture session
	DBNSLog(@ "\tCreating AVCaptureSession..." );
    _session = [[AVCaptureSession alloc] init];
    _session.sessionPreset = AVCaptureSessionPresetHigh;
	DBNSLog(@ "Done.");
	
	// Create input object from the device
	DBNSLog(@ "\tCreating AVCaptureDeviceInput with %s...", [[device description] UTF8String] );
	_input = [AVCaptureDeviceInput deviceInputWithDevice:device error:NULL];
	DBNSLog(@ "Done.");
    [_session addInput:_input];
	
	// Decompressed video output
	DBNSLog(@ "\tCreating AVCaptureDecompressedVideoOutput...");
    _output = [[AVCaptureVideoDataOutput alloc] init];
    _output.videoSettings = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
    
    // Add sample buffer serial queue
    dispatch_queue_t queue = dispatch_queue_create("VideoCaptureQueue", NULL);
    [_output setSampleBufferDelegate:self queue:queue];
	DBNSLog(@ "Done." );
    [_session addOutput:_output];
    
    // Clear old image?
	DBNSLog(@"\tEntering synchronized block to clear memory...");
    @synchronized(self)
	{
        if (mCurrentImageBuffer != nil )
		{
            CVBufferRelease(mCurrentImageBuffer);
            mCurrentImageBuffer = nil;
        }
    }
	DBNSLog(@ "Done.");
    
	[_session startRunning];
	DBNSLog(@"Session started.");
    
    return YES;
}


#pragma mark - AVCaptureVideoDataOutput Delegate
// This delegate method is called whenever the AVCaptureVideoOutput receives frame
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    // Swap out old frame for new one
    CVImageBufferRef videoFrame = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVBufferRetain(videoFrame);
    
    CVImageBufferRef imageBufferToRelease;
    @synchronized(self)
	{
        imageBufferToRelease = mCurrentImageBuffer;
        mCurrentImageBuffer = videoFrame;
    }
	
    CVBufferRelease(imageBufferToRelease);
}

@end
