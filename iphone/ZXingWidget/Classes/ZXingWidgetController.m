// -*- mode:objc; c-basic-offset:2; indent-tabs-mode:nil -*-
/**
 * Copyright 2009-2012 ZXing authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "ZXingWidgetController.h"
#import "Decoder.h"
#import "NSString+HTML.h"
#import "ResultParser.h"
#import "ParsedResult.h"
#import "ResultAction.h"
#import "TwoDDecoderResult.h"
#include <sys/types.h>
#include <sys/sysctl.h>

#import <AVFoundation/AVFoundation.h>
#import "UIImage+Accessory.h"
#import "BlackOverlayView.h"

#define CAMERA_SCALAR 1.12412 // scalar = (480 / (2048 / 480))
#define FIRST_TAKE_DELAY 1.0
#define ONE_D_BAND_HEIGHT 10.0

#define DefaultViewPortWidth 300
#define DefaultViewPortSize CGSizeMake(DefaultViewPortWidth,DefaultViewPortWidth)
#define DefaultCropRectToExactPreview CGRectMake(0,53, 360, 385) //AVCaptureSessionPresetMedium
//#define DefaultCropRectToExactPreview CGRectMake(0,360, 1080, 1200) //AVCaptureSessionPresetHigh, set this because the captured image from AVCaptureSession is bigger than capture view
//#define DefaultViewPort CGRectMake(10,90,100,100) //the x, y, width , height in view, but the y, x, height, width in crop image

@interface ZXingWidgetController ()

@property BOOL showCancel;
@property BOOL showLicense;
@property BOOL oneDMode;
@property BOOL isStatusBarHidden;
@property (nonatomic, strong) UIImageView *animationView;
@property (nonatomic, strong) UITextView *scanTipView;
@property (nonatomic, assign) CGRect viewPort;
@property (nonatomic, strong) UIView *viewPortView;
@property (nonatomic, strong) BlackOverlayView *blackOverlayView;
@property (nonatomic, assign) CGPoint centerPoint;
@property (nonatomic, strong) UIImageView *borderImageView;

- (void)initCapture;
- (void)stopCapture;

@end

@implementation ZXingWidgetController

#if HAS_AVFF
@synthesize captureSession;
@synthesize prevLayer;
#endif
@synthesize result, delegate, soundToPlay;
@synthesize overlayView;
@synthesize oneDMode, showCancel, showLicense, isStatusBarHidden;
@synthesize readers;


- (id)initWithDelegate:(id<ZXingDelegate>)scanDelegate showCancel:(BOOL)shouldShowCancel OneDMode:(BOOL)shouldUseoOneDMode {
    
    return [self initWithDelegate:scanDelegate showCancel:shouldShowCancel OneDMode:shouldUseoOneDMode showLicense:YES];
}

- (id)initWithDelegate:(id<ZXingDelegate>)scanDelegate showCancel:(BOOL)shouldShowCancel OneDMode:(BOOL)shouldUseoOneDMode showLicense:(BOOL)shouldShowLicense {
    self = [super init];
    if (self) {
        [self setDelegate:scanDelegate];
        self.oneDMode = shouldUseoOneDMode;
        self.showCancel = shouldShowCancel;
        self.showLicense = shouldShowLicense;
        self.wantsFullScreenLayout = YES;
        beepSound = -1;
        decoding = NO;
        OverlayView *theOverLayView = [[OverlayView alloc] initWithFrame:[UIScreen mainScreen].bounds
                                                           cancelEnabled:showCancel
                                                                oneDMode:oneDMode
                                                             showLicense:shouldShowLicense];
        [theOverLayView setDelegate:self];
        self.overlayView = theOverLayView;
        [theOverLayView release];
    }
    
    return self;
}

-(void) viewDidLoad{
    [super viewDidLoad];
    [self initialNaviView];
    self.centerPoint = CGPointZero;
}


-(void) initialNaviView{
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(closeQRScanner:)];
    self.navigationItem.title = NSLocalizedString(@"QRScannerTitle", @"the title of QR scanner");
}

-(void) initialScanLineAnimation{
//    self.animationView.backgroundColor = [UIColor greenColor];
    if(self.animationView.superview == nil){
        [self.viewPortView addSubview:self.animationView];
    }
    
}

-(void) startScanAnimation{
    NSLog(@"start animation");
}

-(void) stopScanAnimation{
    CGPoint aniamtionCurrentPosition = [(CALayer *)[self.animationView.layer presentationLayer] position];
    self.animationView.center = aniamtionCurrentPosition;;
    [self.animationView.layer removeAllAnimations];
    [self freezeCapture];
}

-(void) closeQRScanner:(id) sender{
    [self stopCapture];
    [self.delegate zxingControllerDidCancel:self];
}

-(void) initialScanTipView{
    UIFont *tipFont = [UIFont systemFontOfSize:20];
    NSString *tipContent = NSLocalizedString(@"QRTip", @"tip for QR code scanner");
    CGSize tipSize = [tipContent sizeWithFont:tipFont constrainedToSize:CGSizeMake(self.overlayView.bounds.size.width-10, 100) lineBreakMode:NSLineBreakByWordWrapping];
    self.scanTipView.text = tipContent;
    self.scanTipView.font = tipFont;
    [self.scanTipView setTextColor:[UIColor blackColor]];
    self.scanTipView.bounds = CGRectMake(0, 0, tipSize.width, tipSize.height+3);
    self.scanTipView.backgroundColor = [UIColor clearColor];
    self.scanTipView.textAlignment = UITextAlignmentCenter;
    self.scanTipView.userInteractionEnabled = NO;
    self.scanTipView.contentOffset = CGPointMake(0, 6); //To Do: calculate it instead of hard coding
    self.scanTipView.layer.cornerRadius = 3;
    if(self.scanTipView.superview == nil){
        [self.overlayView addSubview:self.scanTipView];
    }
}

-(UIView *) animationView{
    if(_animationView == nil){
        _animationView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _animationView.image = [UIImage imageNamed:@"Scan-line.png"];
    }
    return _animationView;
}

-(UIView *) scanTipView{
    if(_scanTipView == nil){
        _scanTipView = [[UITextView alloc] initWithFrame:CGRectZero];
    }
    return _scanTipView;
}


- (void)dealloc {
    if (beepSound != (SystemSoundID)-1) {
        AudioServicesDisposeSystemSoundID(beepSound);
    }
    
    [self stopCapture];
    
    [result release];
    [soundToPlay release];
    [overlayView release];
    [readers release];
    [super dealloc];
}

- (void)cancelled {
    [self stopCapture];
    //    if (!self.isStatusBarHidden) {
    //        [[UIApplication sharedApplication] setStatusBarHidden:NO];
    //    }
    
    wasCancelled = YES;
    if (delegate != nil) {
        [delegate zxingControllerDidCancel:self];
    }
}

- (NSString *)getPlatform {
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithCString:machine encoding:NSASCIIStringEncoding];
    free(machine);
    return platform;
}

- (BOOL)fixedFocus {
    NSString *platform = [self getPlatform];
    if ([platform isEqualToString:@"iPhone1,1"] ||
        [platform isEqualToString:@"iPhone1,2"]) return YES;
    return NO;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    self.view.bounds = CGRectMake(0, 0, 200, 200);
    
    self.wantsFullScreenLayout = YES;
    if ([self soundToPlay] != nil) {
        OSStatus error = AudioServicesCreateSystemSoundID((CFURLRef)[self soundToPlay], &beepSound);
        if (error != kAudioServicesNoError) {
            NSLog(@"Problem loading nearSound.caf");
        }
    }
    //    self.debugLabel.text = @"";
}

-(void) viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];
    if(self.centerPoint.x == 0 && self.centerPoint.y == 0){
        self.centerPoint = CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2);
        
    }
    CGPoint viewCenter = self.centerPoint;
    viewCenter.y -= 80;
    self.view.bounds = CGRectMake(0,0,DefaultViewPortWidth,DefaultViewPortWidth);
    self.view.center = viewCenter;
    self.prevLayer.frame = self.view.bounds;
    
    self.overlayView.frame = self.view.bounds;
    self.viewPortView.center = CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2);
    self.viewPort = self.viewPortView.frame;
    self.blackOverlayView.transparentRect = self.viewPort;
    [self.blackOverlayView setNeedsDisplay];
    self.blackOverlayView.frame = self.view.bounds;
    self.animationView.center = CGPointMake(self.viewPortView.bounds.size.width/2, 0);
    CGFloat animationViewWidth = self.viewPortView.bounds.size.width;
    CGFloat animationViewHeight = 10;
    
    self.animationView.bounds = CGRectMake(0, 0, animationViewWidth, animationViewHeight);
    self.scanTipView.center = CGPointMake(self.viewPortView.center.x, self.viewPortView.center.y + self.viewPortView.bounds.size.height/2 + 30);
    [self resetScanlineAnimation];
    
    CGRect borderFrame = self.overlayView.bounds;
    borderFrame.size.width += 6;
    borderFrame.size.height +=6;
    borderFrame.origin.x -= 3;
    borderFrame.origin.y -=3;
    self.borderImageView.frame = borderFrame;
}


-(void) resetScanlineAnimation{
    [UIView beginAnimations:@"theAnimation" context:NULL];
    [UIView setAnimationDuration:3.25];
    [UIView setAnimationRepeatCount:FLT_MAX];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationCurve:UIViewAnimationCurveLinear];
    self.animationView.center = CGPointMake(self.viewPortView.bounds.size.width/2, self.viewPortView.bounds.size.height-self.animationView.bounds.size.height/2);
    [UIView commitAnimations];
}

-(void) initialZXing{
    decoding = YES;
    [self initCapture];
    [self.view addSubview:overlayView];
    [overlayView setPoints:nil];
    wasCancelled = NO;
    [self initialBlackOverlayView];
    [self initialScanTipView];
    [self initialViewPortView];
    [self initialScanLineAnimation];
    [self initialBorderImageView];
    //    [self initialDebugLabel];
}

-(void) initialBorderImageView{
    self.borderImageView.image = [UIImage imageNamed:@"kuang.png"];
    if(self.borderImageView.superview == nil){
        [self.overlayView addSubview:self.borderImageView];
    }
}

-(void) initialDebugLabel{
    self.debugLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    [self.overlayView addSubview:self.debugLabel];
}


-(void) initialBlackOverlayView{
    if(self.blackOverlayView.superview == nil){
        [self.overlayView addSubview:self.blackOverlayView];
    }
    self.blackOverlayView.layer.opacity = 1.0;
    self.blackOverlayView.backgroundColor = [UIColor clearColor];
}

-(BlackOverlayView *) blackOverlayView{
    if(_blackOverlayView == nil){
        _blackOverlayView = [[BlackOverlayView alloc] initWithFrame:CGRectZero];
    }
    return _blackOverlayView;
}

-(void) initialViewPortView{
    self.viewPortView = [[UIView alloc] initWithFrame:CGRectZero];
    CGSize viewPortSize = DefaultViewPortSize;
    self.viewPortView.bounds = CGRectMake(0, 0, viewPortSize.width, viewPortSize.height);
    self.viewPortView.layer.borderColor = [UIColor grayColor].CGColor;
    self.viewPortView.layer.borderWidth = 2.0f;
    if(self.viewPortView.superview == nil){
        [self.overlayView addSubview:self.viewPortView];
    }
}


- (void) resetQRScanner{
    [self viewDidDisappear:YES];
    [self viewDidAppear:YES];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self initialZXing];
    [self.overlayView addSubview:self.borderImageView];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.overlayView removeFromSuperview];
    [self stopCapture];
    [self.borderImageView removeFromSuperview];
}

- (CGImageRef)CGImageRotated90:(CGImageRef)imgRef
{
    CGFloat angleInRadians = -90 * (M_PI / 180);
    CGFloat width = CGImageGetWidth(imgRef);
    CGFloat height = CGImageGetHeight(imgRef);
    
    CGRect imgRect = CGRectMake(0, 0, width, height);
    CGAffineTransform transform = CGAffineTransformMakeRotation(angleInRadians);
    CGRect rotatedRect = CGRectApplyAffineTransform(imgRect, transform);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef bmContext = CGBitmapContextCreate(NULL,
                                                   rotatedRect.size.width,
                                                   rotatedRect.size.height,
                                                   8,
                                                   0,
                                                   colorSpace,
                                                   kCGImageAlphaPremultipliedFirst);
    CGContextSetAllowsAntialiasing(bmContext, FALSE);
    CGContextSetInterpolationQuality(bmContext, kCGInterpolationNone);
    CGColorSpaceRelease(colorSpace);
    CGContextScaleCTM(bmContext, rotatedRect.size.width/rotatedRect.size.height, 1.0);
    CGContextTranslateCTM(bmContext, 0.0, rotatedRect.size.height);
    CGContextRotateCTM(bmContext, angleInRadians);
    CGContextDrawImage(bmContext, CGRectMake(0, 0,
                                             rotatedRect.size.width,
                                             rotatedRect.size.height),
                       imgRef);
    
    CGImageRef rotatedImage = CGBitmapContextCreateImage(bmContext);
    CFRelease(bmContext);
    [(id)rotatedImage autorelease];
    
    return rotatedImage;
}

- (CGImageRef)CGImageRotated180:(CGImageRef)imgRef
{
    CGFloat angleInRadians = M_PI;
    CGFloat width = CGImageGetWidth(imgRef);
    CGFloat height = CGImageGetHeight(imgRef);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef bmContext = CGBitmapContextCreate(NULL,
                                                   width,
                                                   height,
                                                   8,
                                                   0,
                                                   colorSpace,
                                                   kCGImageAlphaPremultipliedFirst);
    CGContextSetAllowsAntialiasing(bmContext, FALSE);
    CGContextSetInterpolationQuality(bmContext, kCGInterpolationNone);
    CGColorSpaceRelease(colorSpace);
    CGContextTranslateCTM(bmContext,
                          +(width/2),
                          +(height/2));
    CGContextRotateCTM(bmContext, angleInRadians);
    CGContextTranslateCTM(bmContext,
                          -(width/2),
                          -(height/2));
    CGContextDrawImage(bmContext, CGRectMake(0, 0, width, height), imgRef);
    
    CGImageRef rotatedImage = CGBitmapContextCreateImage(bmContext);
    CFRelease(bmContext);
    [(id)rotatedImage autorelease];
    
    return rotatedImage;
}

// DecoderDelegate methods

- (void)decoder:(Decoder *)decoder willDecodeImage:(UIImage *)image usingSubset:(UIImage *)subset{
#if ZXING_DEBUG
    NSLog(@"DecoderViewController MessageWhileDecodingWithDimensions: Decoding image (%.0fx%.0f) ...", image.size.width, image.size.height);
#endif
}

- (void)decoder:(Decoder *)decoder
  decodingImage:(UIImage *)image
    usingSubset:(UIImage *)subset {
}

- (void)presentResultForString:(NSString *)resultString {
    self.result = [ResultParser parsedResultForString:resultString];
    if (beepSound != (SystemSoundID)-1) {
        AudioServicesPlaySystemSound(beepSound);
    }
#if ZXING_DEBUG
    NSLog(@"result string = %@", resultString);
#endif
}

- (void)presentResultPoints:(NSArray *)resultPoints
                   forImage:(UIImage *)image
                usingSubset:(UIImage *)subset {
    // simply add the points to the image view
    NSMutableArray *mutableArray = [[NSMutableArray alloc] initWithArray:resultPoints];
    [overlayView setPoints:mutableArray];
    [mutableArray release];
}

- (void)decoder:(Decoder *)decoder didDecodeImage:(UIImage *)image usingSubset:(UIImage *)subset withResult:(TwoDDecoderResult *)twoDResult {
    [self presentResultForString:[twoDResult text]];
    [self presentResultPoints:[twoDResult points] forImage:image usingSubset:subset];
    // now, in a selector, call the delegate to give this overlay time to show the points
    [self performSelector:@selector(notifyDelegate:) withObject:[[twoDResult text] copy] afterDelay:0.0];
    decoder.delegate = nil;
}

- (void)notifyDelegate:(id)text {
    if (!isStatusBarHidden) [[UIApplication sharedApplication] setStatusBarHidden:NO];
    [delegate zxingController:self didScanResult:text];
    [text release];
}

- (void)decoder:(Decoder *)decoder failedToDecodeImage:(UIImage *)image usingSubset:(UIImage *)subset reason:(NSString *)reason {
    decoder.delegate = nil;
    [overlayView setPoints:nil];
}

- (void)decoder:(Decoder *)decoder foundPossibleResultPoint:(CGPoint)point {
    [overlayView setPoint:point];
}

/*
 - (void)stopPreview:(NSNotification*)notification {
 // NSLog(@"stop preview");
 }
 
 - (void)notification:(NSNotification*)notification {
 // NSLog(@"notification %@", notification.name);
 }
 */

#pragma mark -
#pragma mark AVFoundation

#include <sys/types.h>
#include <sys/sysctl.h>

// Gross, I know. But you can't use the device idiom because it's not iPad when running
// in zoomed iphone mode but the camera still acts like an ipad.
#if 0 && HAS_AVFF
static bool isIPad() {
    static int is_ipad = -1;
    if (is_ipad < 0) {
        size_t size;
        sysctlbyname("hw.machine", NULL, &size, NULL, 0); // Get size of data to be returned.
        char *name = malloc(size);
        sysctlbyname("hw.machine", name, &size, NULL, 0);
        NSString *machine = [NSString stringWithCString:name encoding:NSASCIIStringEncoding];
        free(name);
        is_ipad = [machine hasPrefix:@"iPad"];
    }
    return !!is_ipad;
}
#endif

- (void)initCapture {
#if HAS_AVFF
    AVCaptureDevice* inputDevice =
    [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *captureInput =
    [AVCaptureDeviceInput deviceInputWithDevice:inputDevice error:nil];
    AVCaptureVideoDataOutput *captureOutput = [[AVCaptureVideoDataOutput alloc] init];
    captureOutput.alwaysDiscardsLateVideoFrames = YES;
    [captureOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber* value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
    NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:value forKey:key];
    [captureOutput setVideoSettings:videoSettings];
    self.captureSession = [[[AVCaptureSession alloc] init] autorelease];
    
    NSString* preset = 0;
    
#if 0
    // to be deleted when verified ...
    if (isIPad()) {
        if (NSClassFromString(@"NSOrderedSet") && // Proxy for "is this iOS 5" ...
            [UIScreen mainScreen].scale > 1 &&
            [inputDevice
             supportsAVCaptureSessionPreset:AVCaptureSessionPresetiFrame960x540]) {
                preset = AVCaptureSessionPresetiFrame960x540;
            }
        if (false && !preset &&
            [inputDevice supportsAVCaptureSessionPreset:AVCaptureSessionPresetHigh]) {
            preset = AVCaptureSessionPresetHigh;
        }
    }
#endif
    
    if (!preset) {
        preset = AVCaptureSessionPresetMedium;
    }
    self.captureSession.sessionPreset = preset;
    
    [self.captureSession addInput:captureInput];
    [self.captureSession addOutput:captureOutput];
    
    [captureOutput release];
    
    if (!self.prevLayer) {
        self.prevLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    }
    self.prevLayer.frame = self.view.bounds;
    self.prevLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer addSublayer: self.prevLayer];
    
    [self.captureSession startRunning];
#endif
}

#if HAS_AVFF
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    if (!decoding) {
        return;
    }
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    /*Lock the image buffer*/
    CVPixelBufferLockBaseAddress(imageBuffer,0);
    /*Get information about the image*/
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    // NSLog(@"wxh: %lu x %lu", width, height);
    
    uint8_t* baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    void* free_me = 0;
    if (true) { // iOS bug?
        uint8_t* tmp = baseAddress;
        int bytes = bytesPerRow*height;
        free_me = baseAddress = (uint8_t*)malloc(bytes);
        baseAddress[0] = 0xdb;
        memcpy(baseAddress,tmp,bytes);
    }
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef newContext =
    CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace,
                          kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst);
    
    CGImageRef capture = CGBitmapContextCreateImage(newContext);
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    free(free_me);
    
    CGContextRelease(newContext);
    CGColorSpaceRelease(colorSpace);
    
    if (false) {
        CGRect cropRect = [overlayView cropRect];
        if (oneDMode) {
            // let's just give the decoder a vertical band right above the red line
            cropRect.origin.x = cropRect.origin.x + (cropRect.size.width / 2) - (ONE_D_BAND_HEIGHT + 1);
            cropRect.size.width = ONE_D_BAND_HEIGHT;
            // do a rotate
            CGImageRef croppedImg = CGImageCreateWithImageInRect(capture, cropRect);
            CGImageRelease(capture);
            capture = [self CGImageRotated90:croppedImg];
            capture = [self CGImageRotated180:capture];
            //              UIImageWriteToSavedPhotosAlbum([UIImage imageWithCGImage:capture], nil, nil, nil);
            CGImageRelease(croppedImg);
            CGImageRetain(capture);
            cropRect.origin.x = 0.0;
            cropRect.origin.y = 0.0;
            cropRect.size.width = CGImageGetWidth(capture);
            cropRect.size.height = CGImageGetHeight(capture);
        }
        
        // N.B.
        // - Won't work if the overlay becomes uncentered ...
        // - iOS always takes videos in landscape
        // - images are always 4x3; device is not
        // - iOS uses virtual pixels for non-image stuff
        
        {
            float height = CGImageGetHeight(capture);
            float width = CGImageGetWidth(capture);
            
            NSLog(@"%f %f", width, height);
            
            CGRect screen = UIScreen.mainScreen.bounds;
            float tmp = screen.size.width;
            screen.size.width = screen.size.height;;
            screen.size.height = tmp;
            
            cropRect.origin.x = (width-cropRect.size.width)/2;
            cropRect.origin.y = (height-cropRect.size.height)/2;
        }
        
        NSLog(@"sb %@", NSStringFromCGRect(UIScreen.mainScreen.bounds));
        NSLog(@"cr %@", NSStringFromCGRect(cropRect));
        
        CGImageRef newImage = CGImageCreateWithImageInRect(capture, cropRect);
        CGImageRelease(capture);
        capture = newImage;
    }
    
    UIImage* scrn = [[[UIImage alloc] initWithCGImage:capture ] autorelease];
    scrn = [scrn imageRotatedByDegrees:90];
    CGRect cropRectToExactPreview = DefaultCropRectToExactPreview;
    scrn = [scrn cropImagefromRect:cropRectToExactPreview];
    CGRect cropRect = [self cropRectFromCaptuerSize:cropRectToExactPreview.size];
    UIImage *crop = [scrn cropImagefromRect:cropRect];
    scrn = crop;
    
    
    CGImageRelease(capture);
    
    Decoder* d = [[Decoder alloc] init];
    d.readers = readers;
    d.delegate = self;
    
    decoding = [d decodeImage:scrn] == YES ? NO : YES;
    
    [d release];
    
    if (decoding) {
        
        d = [[Decoder alloc] init];
        d.readers = readers;
        d.delegate = self;
        
        scrn = [[[UIImage alloc] initWithCGImage:scrn.CGImage
                                           scale:1.0
                                     orientation:UIImageOrientationLeft] autorelease];
        
        // NSLog(@"^ %@ %f", NSStringFromCGSize([scrn size]), scrn.scale);
        decoding = [d decodeImage:scrn] == YES ? NO : YES;
        
        [d release];
    }
}
-(UIImageView *) borderImageView{
    if(_borderImageView == nil){
        _borderImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    }
    return _borderImageView;
}

-(CGRect) cropRectFromCaptuerSize:(CGSize) captureImageSize{
    CGFloat scale = captureImageSize.width/self.view.bounds.size.width;
    CGSize viewPortSize = DefaultViewPortSize;
    CGFloat scaledViewPortWidth = viewPortSize.width * scale;
    CGPoint centerOfViewPort = CGPointMake(captureImageSize.width/2, captureImageSize.height/2);
    CGPoint origin = CGPointMake(centerOfViewPort.x - scaledViewPortWidth/2, centerOfViewPort.y - scaledViewPortWidth/2);
    return CGRectMake(origin.x, origin.y, scaledViewPortWidth, scaledViewPortWidth);
}

-(void) freezeCapture{
    [captureSession stopRunning];
}

#endif

- (void)stopCapture {
    decoding = NO;
#if HAS_AVFF
    [captureSession stopRunning];
    AVCaptureInput* input = [captureSession.inputs objectAtIndex:0];
    [captureSession removeInput:input];
    AVCaptureVideoDataOutput* output = (AVCaptureVideoDataOutput*)[captureSession.outputs objectAtIndex:0];
    [captureSession removeOutput:output];
    [self.prevLayer removeFromSuperlayer];
    
    self.prevLayer = nil;
    self.captureSession = nil;
#endif
}

#pragma mark - Torch

- (void)setTorch:(BOOL)status {
#if HAS_AVFF
    Class captureDeviceClass = NSClassFromString(@"AVCaptureDevice");
    if (captureDeviceClass != nil) {
        
        AVCaptureDevice *device = [captureDeviceClass defaultDeviceWithMediaType:AVMediaTypeVideo];
        
        [device lockForConfiguration:nil];
        if ( [device hasTorch] ) {
            if ( status ) {
                [device setTorchMode:AVCaptureTorchModeOn];
            } else {
                [device setTorchMode:AVCaptureTorchModeOff];
            }
        }
        [device unlockForConfiguration];
        
    }
#endif
}



- (BOOL)torchIsOn {
#if HAS_AVFF
    Class captureDeviceClass = NSClassFromString(@"AVCaptureDevice");
    if (captureDeviceClass != nil) {
        
        AVCaptureDevice *device = [captureDeviceClass defaultDeviceWithMediaType:AVMediaTypeVideo];
        
        if ( [device hasTorch] ) {
            return [device torchMode] == AVCaptureTorchModeOn;
        }
        [device unlockForConfiguration];
    }
#endif
    return NO;
}

@end
