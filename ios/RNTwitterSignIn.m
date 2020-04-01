//
//  TwitterSignin.m
//  TwitterSignin
//
//  Created by Justin Nguyen on 22/5/16.
//  Copyright © 2016 Golden Owl. All rights reserved.
//
#import <TwitterKit/TwitterKit.h>
#import <React/RCTConvert.h>
#import <React/RCTUtils.h>
#import "RNTwitterSignIn.h"
#import <AssetsLibrary/ALAsset.h>
#import <AssetsLibrary/ALAssetsLibrary.h>
#import <AssetsLibrary/ALAssetRepresentation.h>

@import Photos;
@implementation RNTwitterSignIn

- (void)presentView:(UIViewController *)newVC {
    UIViewController *rootVC = UIApplication.sharedApplication.delegate.window.rootViewController;
    
    while (rootVC.presentedViewController != nil) {
        rootVC = rootVC.presentedViewController;
    }
    
    [rootVC presentViewController:newVC
                         animated:YES
                       completion:nil];
}
- (id)init {
    self = [super init];
    if(self) {
        backgroundQueue = dispatch_queue_create("com.convert.gif", NULL);
    }
    return self;
}
- (void)convertGIFToMP4:(NSData *)gif speed:(float)speed size:(CGSize)size repeat:(int)repeat output:(NSString *)path completion:(void (^)(NSError *))completion {
    
    repeat++;
    __block float movie_speed = speed;
    
    dispatch_async(backgroundQueue, ^(void){
        if(movie_speed == 0.0)
            movie_speed = 1.0; // You can't have 0 speed stupid
        NSLog(@"giger 0");
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if([fileManager fileExistsAtPath:path]) {
            dispatch_async(dispatch_get_main_queue(), ^(void){
                completion([[NSError alloc] initWithDomain:@"com.appreviation.gifconverter" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Output file already exists"}]);
            });
            return;
        }
        NSLog(@"giger 1");
        NSDictionary *gifData = [self loadGIFData:gif resize:size repeat:repeat];
        
        UIImage *first = [[gifData objectForKey:@"frames"] objectAtIndex:0];
        CGSize frameSize = first.size;
        frameSize.width = round(frameSize.width / 16) * 16;
        frameSize.height = round(frameSize.height / 16) * 16;
        
        NSError *error = nil;
        self.videoWriter = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:path] fileType:AVFileTypeMPEG4 error:&error];
        
        if(error) {
            dispatch_async(dispatch_get_main_queue(), ^(void){
                completion(error);
            });
            return;
        }
        NSLog(@"giger 2");
        NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                       AVVideoCodecH264, AVVideoCodecKey,
                                       [NSNumber numberWithInt:frameSize.width], AVVideoWidthKey,
                                       [NSNumber numberWithInt:frameSize.height], AVVideoHeightKey,
                                       nil];
        
        AVAssetWriterInput *writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
        
        NSMutableDictionary *attributes = [[NSMutableDictionary alloc] init];
        [attributes setObject:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_32ARGB] forKey:(NSString *)kCVPixelBufferPixelFormatTypeKey];
        [attributes setObject:[NSNumber numberWithUnsignedInt:frameSize.width] forKey:(NSString *)kCVPixelBufferWidthKey];
        [attributes setObject:[NSNumber numberWithUnsignedInt:frameSize.height] forKey:(NSString *)kCVPixelBufferHeightKey];
        NSLog(@"giger 3");
        AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:writerInput sourcePixelBufferAttributes:attributes];
        
        [self.videoWriter addInput:writerInput];
        
        writerInput.expectsMediaDataInRealTime = YES;
        
        [self.videoWriter startWriting];
        [self.videoWriter startSessionAtSourceTime:kCMTimeZero];
        NSLog(@"giger 4");
        CVPixelBufferRef buffer = NULL;
        buffer = [self pixelBufferFromCGImage:[first CGImage] size:frameSize];
        BOOL result = [adaptor appendPixelBuffer:buffer withPresentationTime:kCMTimeZero];
        if(result == NO)
            NSLog(@"Failed to append buffer");
        
        if(buffer)
            CVBufferRelease(buffer);
        
        int fps = ([[gifData objectForKey:@"frames"] count] / [[gifData valueForKey:@"animationTime"] floatValue]) * movie_speed;
        NSLog(@"FPS: %d", fps);
        
        int i = 0;
        NSLog(@"GIFCounter == %d",[[gifData objectForKey:@"frames"] count]);
        //while(i < [[gifData objectForKey:@"frames"] count]) {
        while(i < 20) {
            UIImage *image = [[gifData objectForKey:@"frames"] objectAtIndex:i];
            if(adaptor.assetWriterInput.readyForMoreMediaData) {
                i++;
                CMTime frameTime = CMTimeMake(1, fps);
                CMTime lastTime = CMTimeMake(i, fps);
                CMTime presentTime = CMTimeAdd(lastTime, frameTime);
                
                buffer = [self pixelBufferFromCGImage:[image CGImage] size:frameSize];
                
                BOOL result = [adaptor appendPixelBuffer:buffer withPresentationTime:presentTime];
                if(result == NO)
                    NSLog(@"Failed to append buffer: %@", [self.videoWriter error]);
                
                if(buffer)
                    CVBufferRelease(buffer);
                
                [NSThread sleepForTimeInterval:0.1];
                
            } else {
                NSLog(@"Error: Adaptor is not ready");
                [NSThread sleepForTimeInterval:0.1];
                i--;
            }
        }
        
        [writerInput markAsFinished];
        [self.videoWriter finishWritingWithCompletionHandler:^(void){
            NSLog(@"Finished writing");
            CVPixelBufferPoolRelease(adaptor.pixelBufferPool);
            self.videoWriter = nil;
            dispatch_async(dispatch_get_main_queue(), ^(void){
                completion(nil);
            });
        }];
    });
}

- (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image size:(CGSize)size {
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                             nil];
    CVPixelBufferRef pxbuffer = NULL;
    
    CVPixelBufferCreate(kCFAllocatorDefault, size.width, size.height, kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef)options, &pxbuffer);
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, size.width, size.height, 8, 4*size.width, rgbColorSpace, kCGImageAlphaNoneSkipFirst);
    CGContextConcatCTM(context, CGAffineTransformMakeRotation(0));
    
    CGContextDrawImage(context, CGRectMake(0, 0, size.width, size.height), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    return pxbuffer;
}

- (NSDictionary *)loadGIFData:(NSData *)data resize:(CGSize)size repeat:(int)repeat {
    NSMutableArray *frames = nil;
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    CGFloat animationTime = 0.f;
    if(src) {
        size_t l = CGImageSourceGetCount(src);
        frames = [NSMutableArray arrayWithCapacity:l];
        for(size_t i = 0; i < l; i++) {
            CGImageRef img = CGImageSourceCreateImageAtIndex(src, i, NULL);
            NSDictionary *properties = (__bridge NSDictionary *)CGImageSourceCopyPropertiesAtIndex(src, i, NULL);
            NSDictionary *frameProperties = [properties objectForKey:(NSString *)kCGImagePropertyGIFDictionary];
            NSNumber *delayTime = [frameProperties objectForKey:(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
            animationTime += [delayTime floatValue];
            if(img) {
                if(size.width != 0.0 && size.height != 0.0) {
                    UIGraphicsBeginImageContext(size);
                    CGFloat width = CGImageGetWidth(img);
                    CGFloat height = CGImageGetHeight(img);
                    int x = 0, y = 0;
                    if(height > width) {
                        CGFloat padding = size.height / height; height = height * padding; width = width * padding; x = (size.width/2) - (width/2); y = 0;
                    } else if(width > height) {
                        CGFloat padding = size.width / width; height = height * padding; width = width * padding; x = 0; y = (size.height/2) - (height/2);
                    } else {
                        width = size.width; height = size.height;
                    }
                    
                    [[UIImage imageWithCGImage:img] drawInRect:CGRectMake(x, y, width, height) blendMode:kCGBlendModeNormal alpha:1.0];
                    [frames addObject:UIGraphicsGetImageFromCurrentImageContext()];
                    UIGraphicsEndImageContext();
                    CGImageRelease(img);
                    
                } else {
                    [frames addObject:[UIImage imageWithCGImage:img]];
                    CGImageRelease(img);
                }
            }
        }
        CFRelease(src);
    }
    
    NSArray *framesCopy = [frames copy];
    for(int i = 1; i < repeat; i++) {
        [frames addObjectsFromArray:framesCopy];
    }
    
    return @{@"animationTime" : [NSNumber numberWithFloat:animationTime * repeat], @"frames":  frames};
}
RCT_EXPORT_MODULE();
RCT_EXPORT_METHOD(init: (NSString *)consumerKey consumerSecret:(NSString *)consumerSecret resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    [[Twitter sharedInstance] startWithConsumerKey:consumerKey consumerSecret:consumerSecret];
    
}
RCT_EXPORT_METHOD(imgsTweet: (NSString *)tweetText imgURLs:(NSArray *)imgURLs  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
   
    
    /*NSString *urlString = @"http://images.moneysavingexpert.com/images/OrangeLogo.jpg";
    NSURL *url = [NSURL URLWithString:urlString];
    NSData *data = [NSData dataWithContentsOfURL:url];
    UIImage *img = [[UIImage alloc]initWithData:data];*/
    //NSArray *images = [NSArray arrayWithObjects:img,img];
    NSMutableArray *myArray = [NSMutableArray array];
    //NSLog(@"img urls === %@",imgURLs);
    [myArray addObject:tweetText];
    for(id s in imgURLs)
    {
        NSLog(@"umg url s %@",(NSString*)s);
        NSURL *url = [NSURL URLWithString:s];
        NSData *data = [NSData dataWithContentsOfURL:url];
        UIImage *img = [[UIImage alloc]initWithData:data];
        [myArray addObject:img];
        
        
    }
   
     dispatch_async(dispatch_get_main_queue(), ^(void){
         //Run UI Updates
         UIActivityViewController *shareController = [[UIActivityViewController alloc] initWithActivityItems:myArray applicationActivities:nil];
            
           
            UIViewController *controller = RCTPresentedViewController();
         [controller presentViewController:shareController animated:YES completion:nil];
     });
         
     
}

RCT_EXPORT_METHOD(gifTweet: (NSString *)tweetText gifUrl:(NSString *)gifUrl)
{
   
    //NSString *urlString = gitUrl;
    
    /*
    UIActivityViewController *activityController = [[UIActivityViewController alloc] initWithActivityItems:@[self] applicationActivities:nil];
    //decide what happens after it closes (optional)
    [activityController setCompletionWithItemsHandler:^(NSString *activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
    }];
    //present the activity view controller
    [[UIApplication sharedApplication].delegate.window.rootViewController presentViewController:activityController animated:YES completion:^{
        
    }];*/
    
    /*outputPath
     /Users/C011333/Library/Developer/CoreSimulator/Devices/053C1D1C-B34D-4B31-8675-408A24999D68/data/Containers/Data/Application/61E1A25B-A7A3-4103-A682-CB5BE61410E0/tmp/50output.mp4
     
     videopathはこれにしたい
     file:///Users/C011333/Library/Developer/CoreSimulator/Devices/053C1D1C-B34D-4B31-8675-408A24999D68/data/Containers/Data/Application/61E1A25B-A7A3-4103-A682-CB5BE61410E0/Documents/hoge.mp4
     */
    
    //NSLog(@"veeeerify");
    
   // NSURL *url = [NSURL URLWithString:@"https://i0.wp.com/cspvoyages18.com/wp-content/uploads/2018/10/giphy.gif?zoom=2&resize=302%2C302"];
   
    NSURL *sourceURL = [NSURL URLWithString:gifUrl];
   
    
    
   
    NSString *outputPath = [NSHomeDirectory()  stringByAppendingString:@"/Documents/640output.mp4"];
    
    //convertGIFToMP4 *gifConverter = [[convertGIFToMP4 alloc] init];
    NSString *docPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSString *filePath = [docPath stringByAppendingPathComponent:@"640output.mp4"];
    NSError *error = nil;
    
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
    
    NSLog(@"xgiger 0");
    //NSLog(@"Logging in with twitter %@",url);
    //NSLog(@"Converted video! outputPath %@",outputPath);
    NSURLSessionTask *download = [[NSURLSession sharedSession] downloadTaskWithURL:sourceURL completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if(error) {
            NSLog(@"error saving: %@", error.localizedDescription);
            return;
        }
      
        NSLog(@"xgiger 2");
         NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
       
         NSURL *tempURL = [documentsURL URLByAppendingPathComponent:[sourceURL lastPathComponent]];
             //? file:///Users/C011333/Library/Developer/CoreSimulator/Devices/053C1D1C-B34D-4B31-8675-408A24999D68/data/Containers/Data/Application/61E1A25B-A7A3-4103-A682-CB5BE61410E0/Documents/ + https://object-storage.tyo2.conoha.io/v1/nc_771af95e34cd4f14b29d6a265f7639b7/pro/uploads/ckeditor/pictures/30103/"395.h6oCkj8.gif"
         [[NSFileManager defaultManager] moveItemAtURL:location toURL:tempURL　 error:nil];
        
         NSLog(@"xgiger 3"); //file:///Users/C011333/Library/Developer/CoreSimulator/Devices/053C1D1C-B34D-4B31-8675-408A24999D68/data/Containers/Data/Application/61E1A25B-A7A3-4103-A682-CB5BE61410E0/tmp/CFNetworkDownload_nJBHT8.tmp -> file:///Users/C011333/Library/Developer/CoreSimulator/Devices/053C1D1C-B34D-4B31-8675-408A24999D68/data/Containers/Data/Application/61E1A25B-A7A3-4103-A682-CB5BE61410E0/Documents/hoge.gif <-videoPath
         NSURL *videoPath = tempURL;
        //file:///Users/C011333/Library/Developer/CoreSimulator/Devices/053C1D1C-B34D-4B31-8675-408A24999D68/data/Containers/Data/Application/61E1A25B-A7A3-4103-A682-CB5BE61410E0/Documents/hoge.gif
         //NSString *message = @"The Upcoming App Scribble Talk";
        /*NSArray *objectsToShare = [NSArray arrayWithObjects:message, videoPath, nil];
       
        UIActivityViewController *shareController = [[UIActivityViewController alloc] initWithActivityItems:objectsToShare applicationActivities:nil];
        
        UIViewController *controller = RCTPresentedViewController();
        
        [controller presentViewController:shareController animated:YES completion:nil];*/
        /*結果としては　 NSArray *objectsToShare = [NSArray arrayWithObjects:message, videoPath, nil];*/
        NSData *gif = [NSData dataWithContentsOfURL:videoPath];
        //NSString *message = @"The Upcoming App Scribble Talk";
        NSLog(@"xgiger 4");
        
        [self convertGIFToMP4:gif speed:1.0 size:CGSizeMake(1000, 1000) repeat:0 output:outputPath completion:^(NSError *error){
            if(!error)
                NSLog(@"Converted video! outputPath %@",outputPath);
            
           
            NSURL *atempURL = [documentsURL URLByAppendingPathComponent:[outputPath lastPathComponent]];
            // NSURL *tempURL = [documentsURL URLByAppendingPathComponent:[sourceURL lastPathComponent]]; sourceURLが取得先ないし取得したファイル
             //A file:///Users/C011333/Library/Developer/CoreSimulator/Devices/053C1D1C-B34D-4B31-8675-408A24999D68/data/Containers/Data/Application/61E1A25B-A7A3-4103-A682-CB5BE61410E0/Documents/ + /tmp/"hoge.mp4"
           // NSLog(@"Cerrorvideo == %@",error);
            [[NSFileManager defaultManager] moveItemAtURL:[NSURL URLWithString:outputPath] toURL:atempURL error:nil];
           // [[NSFileManager defaultManager] moveItemAtURL:location toURL:tempURL error:nil]; locationがアップロードされたtmpのフォルダ
            //NSString *message = @"The Upcoming App Scribble Talk";
            
            NSURL *avideoPath = atempURL;
            //NSLog(@"Converted video! %@",atempURL);
            
            /*outputPath
             /Users/C011333/Library/Developer/CoreSimulator/Devices/053C1D1C-B34D-4B31-8675-408A24999D68/data/Containers/Data/Application/61E1A25B-A7A3-4103-A682-CB5BE61410E0/tmp/50output.mp4
             
            videopathはこれにしたい
             file:///Users/C011333/Library/Developer/CoreSimulator/Devices/053C1D1C-B34D-4B31-8675-408A24999D68/data/Containers/Data/Application/61E1A25B-A7A3-4103-A682-CB5BE61410E0/Documents/hoge.mp4
             */
            
            dispatch_async(dispatch_get_main_queue(), ^(void){
                //Run UI Updates
               NSArray *objectsToShare = [NSArray arrayWithObjects:tweetText, avideoPath, nil];
                UIActivityViewController *shareController = [[UIActivityViewController alloc] initWithActivityItems:objectsToShare applicationActivities:nil];
                
                shareController.completionWithItemsHandler = ^(NSString *activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
                    if (activityError) NSLog(@"ac error %@", activityError);
                    else if (completed) NSLog(@"action completed: %@", activityType);
                    
                    NSString *docPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
                    NSString *filePath = [docPath stringByAppendingPathComponent:@"640output.mp4"];
                    NSError *error = nil;
                    
                    [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
                };
                UIViewController *controller = RCTPresentedViewController();
                
                [controller presentViewController:shareController animated:YES completion:nil];
            });
        }];
        
    }];
    [download resume];
}


RCT_EXPORT_METHOD(logIn: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    
    [[Twitter sharedInstance] logInWithCompletion:^(TWTRSession * _Nullable session, NSError * _Nullable error) {
        if (error) {
            reject(@"Error", @"Twitter signin error", error);
        } else {
            TWTRAPIClient *client = [TWTRAPIClient clientWithCurrentUser];
            NSLog(@"aaaaa===   %@",client);
            NSURLRequest *request = [client URLRequestWithMethod:@"GET"
                                                             URL:@"https://api.twitter.com/1.1/account/verify_credentials.json"
                                                      parameters:@{@"include_email": @"true", @"skip_status": @"true"}
                                                           error:nil];
            [client sendTwitterRequest:request completion:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                NSError *jsonError;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                NSString *email = json[@"email"] ?: @"";
                NSDictionary *body = @{@"authToken": session.authToken,
                                       @"authTokenSecret": session.authTokenSecret,
                                       @"userID":session.userID,
                                       @"email": email,
                                       @"userName":session.userName};
                resolve(body);
            }];
        }
    }];
}
RCT_EXPORT_METHOD(logOut)
{
    TWTRSessionStore *store = [[Twitter sharedInstance] sessionStore];
    NSString *userID = store.session.userID;
    [store logOutUserID:userID];
}
@end

