//
//  WYVideoCaptureController.m
//  WYAVFoundation
//
//  Created by 王俨 on 15/12/31.
//  Copyright © 2015年 wangyan. All rights reserved.
//

#import "WYVideoCaptureController.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>
#import "WYTopImgBtn.h"
#import "UIView+Extension.h"
#import "WYVideoTimeView.h"
#import "NSTimer+Addtion.h"
#import "ProgressView.h"
#import "UIView+AutoLayoutViews.h"

typedef void(^PropertyChangeBlock)(AVCaptureDevice *captureDevice);
#define kAnimationDuration 0.2
#define kTimeChangeDuration 0.1
#define kVideoTotalTime 9
#define kVideoLimit 10
#define iOS8Later ([UIDevice currentDevice].systemVersion.floatValue >= 8.0f)

@interface WYVideoCaptureController ()<AVCaptureFileOutputRecordingDelegate>
{
    CGRect _leftBtnFrame;
    CGRect _centerBtnFrame;
    CGRect _rightBtnFrame;
    ///  视频录制到第几秒
    CGFloat _currentTime;
    
    AVPlayer *_player;
    AVPlayerLayer *_playerLayer;
    
    BOOL _isPhoto;
}
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UIButton *toggleBtn;
@property (nonatomic, strong) WYVideoTimeView *videoTimeView;
@property (nonatomic, strong) UIView *viewContainer;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) ProgressView *progressView;
@property (nonatomic, strong) UILabel *dotLabel;
@property (nonatomic, strong) UIButton *leftBtn;
@property (nonatomic, strong) UIButton *centerBtn;
@property (nonatomic, strong) UIButton *rightBtn;

@property (nonatomic, strong) UIButton *cameraBtn;
@property (nonatomic, strong) WYTopImgBtn *importBtn;
@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, strong) UIView *completeView;
@property (nonatomic, strong) UIButton *retakeBtn;
@property (nonatomic, strong) UIButton *submitBtn;

/// 负责输入和输出设备之间数据传递
@property (nonatomic, strong) AVCaptureSession *captureSession;
/// 负责从AVCaptureDevice获取数据
@property (nonatomic, strong) AVCaptureDeviceInput *captureDeviceInput;
/// 视频输出流
@property (nonatomic, strong) AVCaptureMovieFileOutput *captureMovieFileOutput;
/// 照片输出流
@property (nonatomic, strong) AVCaptureStillImageOutput *captureStillImageOutput;
/// 相机拍摄预览层
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;
/// 是否允许旋转 (注意在旋转过程中禁止屏幕旋转)
@property (nonatomic, assign, getter=isEnableRotation) BOOL enableRotation;
/// 旋转前的屏幕大小
@property (nonatomic, assign) CGRect lastBounds;
/// 后台任务标识
@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTaskIndentifier;

@property (nonatomic, assign) NSInteger filepathSuff;

@property (nonatomic, strong) NSURL *videoUrl;

@end

@implementation WYVideoCaptureController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.filepathSuff = 0;
    [self setupUI];
    [self ChangeToPhoto:YES];
    [self setupCaptureView];
    self.view.backgroundColor = RGB(0x16161b);
    
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_captureSession startRunning];
    [self addOwnTimer];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_captureSession stopRunning];
    [self removeOwnTimer];
}

- (void)dealloc {
    NSLog(@"我是拍照控制器,我被销毁了");
}

- (void)setupCaptureView {
    // 1.初始化会话
    _captureSession = [[AVCaptureSession alloc] init];
    if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        [_captureSession setSessionPreset:AVCaptureSessionPreset1280x720]; // 设置分辨率
    }
    // 2.获得输入设备
    AVCaptureDevice *captureDevice = [self getCameraDeviceWithPosition:AVCaptureDevicePositionBack];
    if (captureDevice == nil) {
        NSLog(@"获取输入设备失败");
        return;
    }
    // 3.添加一个音频输入设备
    AVCaptureDevice *audioCaptureDevice = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio].firstObject;
    // 4.根据输入设备初始化设备输入对象,用于获得输入数据
    NSError *error = nil;
    _captureDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];
    AVCaptureDeviceInput *audioCaptureDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioCaptureDevice error:&error];
    if (error) {
        NSLog(@"创建设备输入对象失败 -- error = %@", error);
        return;
    }
    // 5.初始化视频设备输出对象,用于获得输出数据
    _captureMovieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
    // 初始化图片设备输出对象
    _captureStillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    _captureStillImageOutput.outputSettings = @{AVVideoCodecKey: AVVideoCodecJPEG}; // 输出设置
    // 6.将设备添加到会话中
    if ([_captureSession canAddInput:_captureDeviceInput]) {
        [_captureSession addInput:_captureDeviceInput];
        [_captureSession addInput:audioCaptureDeviceInput];
        AVCaptureConnection *captureConnection = [_captureMovieFileOutput connectionWithMediaType:AVMediaTypeVideo];
        if ([captureConnection isVideoStabilizationSupported]) {
            captureConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
        }
    }
    // 7.将设备输出添加到会话中
    if ([_captureSession canAddOutput:_captureMovieFileOutput]) {
        [_captureSession addOutput:_captureMovieFileOutput];
    }
    if ([_captureSession canAddOutput:_captureStillImageOutput]) {
        [_captureSession addOutput:_captureStillImageOutput];
    }
    // 8.创建视频预览层
    _captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
    CALayer *layer = _viewContainer.layer;
    layer.masksToBounds = YES;
    _captureVideoPreviewLayer.frame = layer.bounds;
    _captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [layer insertSublayer:_captureVideoPreviewLayer atIndex:0];
    [self addNotificationToCaptureDevice:captureDevice];
}

#pragma mark - CaptureMethod
- (AVCaptureDevice *)getCameraDeviceWithPosition:(AVCaptureDevicePosition)position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *captureDevice in devices) {
        if (captureDevice.position == position) {
            return captureDevice;
        }
    }
    return nil;
}

/// 改变设备属性的统一方法
///
/// @param propertyChange 属性改变操作
- (void)changeDeviceProperty:(PropertyChangeBlock)propertyChange {
    AVCaptureDevice *captureDevice = _captureDeviceInput.device;
    NSError *error = nil;
    // 注意:在改变属性之前一定要先调用lockForConfiguration;调用完成之后使用unlockForConfiguration方法解锁
    if ([captureDevice lockForConfiguration:&error]) {
        propertyChange(captureDevice);
        [captureDevice unlockForConfiguration];
    } else {
        NSLog(@"更改设备属性错误 -- error = %@", error);
    }
}

#pragma mark - Timer 
- (void)addOwnTimer {
    _timer = [NSTimer scheduledTimerWithTimeInterval:kTimeChangeDuration target:self selector:@selector(videoTimeChanged:) userInfo:nil repeats:YES];
    [_timer pauseTimer];
}
- (void)removeOwnTimer {
    [_timer invalidate];
    _timer = nil;
}

- (void)videoTimeChanged:(NSTimer *)timer {
    _currentTime += kTimeChangeDuration;
    _cameraBtn.enabled = YES;
    if (_currentTime < 3) {
        _cameraBtn.enabled = NO;
    }
    
    if (_currentTime > kVideoTotalTime) {
        if ([_captureMovieFileOutput isRecording]) {
            [_captureMovieFileOutput stopRecording];
        }
        return;
    }
    _progressView.currentTime = _currentTime;
    _videoTimeView.videoTime = _currentTime;
}

#pragma mark - Notification
/// 给输入设备添加通知
- (void)addNotificationToCaptureDevice:(AVCaptureDevice *)captureDevie {
    // 注意添加区域改变捕获通知必须首先设置设备允许捕获
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        captureDevice.subjectAreaChangeMonitoringEnabled = YES;
    }];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(areaChanged:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevie];
}
/// 移除设备通知
- (void)removeNotificationFromCaptureDevice:(AVCaptureDevice *)captureDevice {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
}

- (void)areaChanged:(NSNotification *)n {
    
}

#pragma mark - SuperMethod
- (BOOL)shouldAutorotate {
    return self.isEnableRotation;
}
/// 屏幕旋转时调整视频预览图层的方向
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    AVCaptureConnection *captureConnection = [_captureVideoPreviewLayer connection];
    captureConnection.videoOrientation = (AVCaptureVideoOrientation)toInterfaceOrientation;
}
/// 旋转后重新设置大小
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    _captureVideoPreviewLayer.frame = _viewContainer.bounds;
}

#pragma mark - AVCaptureFileOutputRecordingDelegate
- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections {
    NSLog(@"视频开始录制");
    [self startVideoRecord];
}
- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error {
    NSLog(@"视频录制完成");
    [self endVideoRecord:outputFileURL];
    self.videoUrl = outputFileURL;
    
//    NSString* filename = [NSString stringWithFormat:@"maimai%ld.mp4", _filepathSuff];
//    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
//    NSData *data = [NSData dataWithContentsOfFile:path];
//    NSInteger length = data.length / (1024 * 1024);
//    NSLog(@"daxiao----%ld", length);
//    
//    NSFileManager *fileManager = [NSFileManager defaultManager];
//    if ([fileManager fileExistsAtPath:path]){
//        _filepathSuff++;
//        filename = [NSString stringWithFormat:@"maimai%ld.mp4", _filepathSuff];
//        path = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
//        [fileManager removeItemAtPath:path error:nil];
//    }
    
    
    
    
    //BOOL iOS8Later = ([UIDevice currentDevice].systemVersion.floatValue >= 8.0f);
    
    
    

}
- (long long)fileSizeAtPath:(NSString*) filePath{
    NSFileManager* manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:filePath]){
        return [[manager attributesOfItemAtPath:filePath error:nil] fileSize];
    }
    return 0;
}

#pragma mark - 视频录制
/// 开始录制视频
- (void)startVideoRecord {
    [_cameraBtn setImage:[UIImage imageNamed:@"stopRecord"] forState:UIControlStateNormal];
    _videoTimeView.videoTime = 0;
    _currentTime = 0;
    _videoTimeView.hidden = NO;
    _toggleBtn.hidden = YES;
    [_timer resumeTimerAfterTimeInterval:kTimeChangeDuration];
}
/// 结束录制视频
///
/// @param outputFileURL 录制完成的视频的URL
- (void)endVideoRecord:(NSURL *)outputFileURL {
    BOOL canPreview = _currentTime >= 10;
    [self resetVideoRecordCanPreview:canPreview];
    
    AVAsset *asset = [AVAsset assetWithURL:outputFileURL];
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
    _player = [AVPlayer playerWithPlayerItem:playerItem];
    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
    _playerLayer.frame = _viewContainer.bounds;
    _playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [_viewContainer.layer addSublayer:_playerLayer];
    [_player play];
    _completeView.hidden = NO;
    _importBtn.alpha = 1;
    _retakeBtn.alpha = 1;
}

- (void)resetVideoRecordCanPreview:(BOOL)canPreview {
    [_timer pauseTimer];
    [_cameraBtn setImage:[UIImage imageNamed:@"videoPlaying"] forState:UIControlStateNormal];
    _videoTimeView.hidden = YES;
    _currentTime = 0;
    _toggleBtn.hidden = canPreview;
    if (!canPreview) {
        [self videoTimeChanged:nil];
    }
}

#pragma mark - UI设计
- (void)setupUI {
    [self prepareUI];
    //[self prepareCompleteView];
    
    [self.view addSubview:_closeBtn];
    [self.view addSubview:_toggleBtn];
    [self.view addSubview:_videoTimeView];
    [self.view addSubview:_viewContainer];
    [_viewContainer addSubview:_imageView];
    [self.view addSubview:_progressView];
    [self.view addSubview:_dotLabel];
    [self.view addSubview:_leftBtn];
    [self.view addSubview:_centerBtn];
    [self.view addSubview:_rightBtn];
    [self.view addSubview:_cameraBtn];
    [self.view addSubview:_importBtn];
    [self.view addSubview:_retakeBtn];
    
    //[self.view addSubview:_completeView];
    
    _closeBtn.frame = CGRectMake(0, 20, 60, 44);
    _closeBtn.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 15);
    _toggleBtn.frame = CGRectMake(APP_WIDTH - 60, 20, 60, 44);
    _videoTimeView.frame = CGRectMake((APP_WIDTH - 50) * 0.5, 15, 50, 24);
    _viewContainer.frame = CGRectMake(0, 64, APP_WIDTH, APP_WIDTH * 1.10);
    _imageView.frame = _viewContainer.bounds;
    _progressView.frame = CGRectMake(0, CGRectGetMaxY(_viewContainer.frame), APP_WIDTH, 5);
    _completeView.frame = CGRectMake(0, CGRectGetMaxY(_progressView.frame), APP_WIDTH, APP_HEIGHT - CGRectGetMaxY(_progressView.frame));
    //_dotLabel.frame = CGRectMake((APP_WIDTH - 5) * 0.5, APP_WIDTH + 60 , 5, 5);
    CGFloat btnW = 40;
    CGFloat leftBtnX = (APP_WIDTH - 3 * btnW - 2 * 32) *0.5;
    CGFloat leftBtnY = APP_WIDTH * 1.10 + 80;//CGRectGetMaxY(_dotLabel.frame) + 6;
    
    _leftBtnFrame = CGRectMake(leftBtnX, leftBtnY, btnW, btnW);
    _centerBtnFrame = CGRectOffset(_leftBtnFrame, 32 + btnW, 0);
    _rightBtnFrame = CGRectOffset(_centerBtnFrame, 32 + btnW, 0);
    [self restoreBtn];
    _cameraBtn.frame = CGRectMake((APP_WIDTH - 67) * 0.5, CGRectGetMaxY(_centerBtnFrame) + 20, 67, 67);
    _importBtn.frame = CGRectMake(CGRectGetMaxX(_cameraBtn.frame) + 25, _cameraBtn.y, 100, 60);
    _retakeBtn.frame = CGRectMake(CGRectGetMaxX(_cameraBtn.frame) - 25, _cameraBtn.y, 100, 60);
}
- (void)prepareUI {
    _closeBtn = [[UIButton alloc] init];
    [_closeBtn setImage:[UIImage imageNamed:@"button_camera_close"] forState:UIControlStateNormal];
    [_closeBtn addTarget:self action:@selector(closeBtnClick) forControlEvents:UIControlEventTouchUpInside];
    
    _toggleBtn = [[UIButton alloc] init];
    [_toggleBtn setImage:[UIImage imageNamed:@"button_camera_CUT"] forState:UIControlStateNormal];
    [_toggleBtn addTarget:self action:@selector(toggleBtnClick) forControlEvents:UIControlEventTouchUpInside];
    
    _videoTimeView = [[WYVideoTimeView alloc] init];
    _videoTimeView.hidden = YES;
    
    _viewContainer = [[UIView alloc] init];
    _imageView = [[UIImageView alloc] init];
    _imageView.hidden = YES;
    
    _progressView = [[ProgressView alloc] initWithFrame:CGRectMake(0, APP_WIDTH + 44, APP_WIDTH, 5)];
    _progressView.totalTime = kVideoTotalTime;
    
    _dotLabel = [UILabel new];  // 5 - 5
    _dotLabel.layer.cornerRadius = 2.5;
    _dotLabel.clipsToBounds = YES;
    _dotLabel.backgroundColor = RGB(0xffc437);
    
    _leftBtn = [UIButton new];
    [_leftBtn setTitle:@"照片" forState:UIControlStateNormal];
    [_leftBtn setTitleColor:RGB(0xfefeff) forState:UIControlStateNormal];
    _leftBtn.titleLabel.font = [UIFont systemFontOfSize:15.0];
    [_leftBtn addTarget:self action:@selector(leftBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    _centerBtn = [UIButton new];
    [_centerBtn setTitleColor:RGB(0x7ED321) forState:UIControlStateNormal];
    [_centerBtn setTitle:@"照片" forState:UIControlStateNormal];
    _centerBtn.titleLabel.font = [UIFont systemFontOfSize:15.0];
    _rightBtn = [UIButton new];
    [_rightBtn setTitle:@"视频" forState:UIControlStateNormal];
    [_rightBtn setTitleColor:RGB(0xfefeff) forState:UIControlStateNormal];
    _rightBtn.titleLabel.font = [UIFont systemFontOfSize:15.0];
    [_rightBtn addTarget:self action:@selector(rightBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    
    _cameraBtn = [UIButton new];
    [_cameraBtn setImage:[UIImage imageNamed:@"videoPlaying"] forState:UIControlStateNormal];
    [_cameraBtn addTarget:self action:@selector(cameraBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    
    _importBtn = [[WYTopImgBtn alloc] init];
    [_importBtn setImage:[UIImage imageNamed:@"enterSave"] forState:UIControlStateNormal];
    _importBtn.alpha = 0;
    [_importBtn addTarget:self action:@selector(importBtnClick) forControlEvents:UIControlEventTouchUpInside];
    
    _retakeBtn = [UIButton new];
    [_retakeBtn setImage:[UIImage imageNamed:@"cancelSave"] forState:UIControlStateNormal];
    [_retakeBtn addTarget:self action:@selector(retakeBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    _retakeBtn.alpha = 0;
    
}

- (void)prepareCompleteView {
    _completeView = [UIView new];
    _completeView.backgroundColor = RGB(0x16161b);
    _completeView.hidden = YES; // 默认隐藏
    
    
    _retakeBtn = [UIButton new];
    [_retakeBtn setImage:[UIImage imageNamed:@"cancelSave"] forState:UIControlStateNormal];
    [_retakeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _retakeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
    [_retakeBtn addTarget:self action:@selector(retakeBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    
    _submitBtn = [UIButton new];
    [_submitBtn setImage:[UIImage imageNamed:@"button_screen_complete_submit"] forState:UIControlStateNormal];
    [_submitBtn setImage:[UIImage imageNamed:@"button_screen_complete_submit_click"] forState:UIControlStateHighlighted];
    [_submitBtn addTarget:self action:@selector(submitBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    
    [_completeView addSubview:_retakeBtn];
    [_completeView addSubview:_submitBtn];
    
    [_submitBtn lx_InnerLayoutForType:LXLayoutInnerTypeCenter referedView:_completeView offset:CGPointZero];
    [_retakeBtn lx_InnerLayoutForType:LXLayoutInnerTypeLeftCenter referedView:_completeView size:CGSizeMake(60, 44) offset:CGPointMake(50, 0)];
}

#pragma mark - ButtonClick
- (void)retakeBtnClick:(UIButton *)btn {
    [_playerLayer removeFromSuperlayer];
    [_player pause];
    _player = nil;
    _completeView.hidden = YES;
    _toggleBtn.hidden = NO;
    [self videoTimeChanged:nil];
}
- (void)submitBtnClick:(UIButton *)btn {
    [self closeBtnClick];
}

- (void)closeBtnClick {
    [self dismissViewControllerAnimated:YES completion:nil];
}
/// 切换前后摄像头
- (void)toggleBtnClick {
    AVCaptureDevice *currentDevice = [_captureDeviceInput device];
    AVCaptureDevicePosition currentPosition = currentDevice.position;
    [self removeNotificationFromCaptureDevice:currentDevice];
    AVCaptureDevice *toChangeDevice;
    AVCaptureDevicePosition toChangeDevicePosition = AVCaptureDevicePositionBack;
    if (currentPosition == AVCaptureDevicePositionUnspecified || currentPosition == toChangeDevicePosition) {
        toChangeDevicePosition = AVCaptureDevicePositionFront;
    }
    // 1.获得要调整的设备输入对象
    toChangeDevice = [self getCameraDeviceWithPosition:toChangeDevicePosition];
    AVCaptureDeviceInput *captureDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:toChangeDevice error:nil];
    // 2.改变会话配置前一定要先开启配置,配置完成后提交配置改变
    [_captureSession beginConfiguration];
    // 3.移除原有的输入对象
    [_captureSession removeInput:_captureDeviceInput];
    // 4.添加新的输入对象
    if ([_captureSession canAddInput:captureDeviceInput]) {
        [_captureSession addInput:captureDeviceInput];
        _captureDeviceInput = captureDeviceInput;
    }
    // 5.提交会话配置
    [_captureSession commitConfiguration];
}
- (void)leftBtnClick:(UIButton *)btn {
    [_centerBtn setTitleColor:RGB(0xfefeff) forState:UIControlStateNormal];
    _dotLabel.hidden = YES;
    [UIView animateWithDuration:kAnimationDuration animations:^{
        _leftBtn.frame = _centerBtnFrame;
        _centerBtn.frame = _rightBtnFrame;
    } completion:^(BOOL finished) {
        [self ChangeToPhoto:YES];
    }];
}
- (void)rightBtnClick:(UIButton *)btn {
    [_centerBtn setTitleColor:RGB(0xfefeff) forState:UIControlStateNormal];
    _dotLabel.hidden = YES;
    [UIView animateWithDuration:kAnimationDuration animations:^{
        _rightBtn.frame = _centerBtnFrame;
        _centerBtn.frame = _leftBtnFrame;
    } completion:^(BOOL finished) {
        [self ChangeToPhoto:NO];
    }];
}
- (void)cameraBtnClick:(UIButton *)btn {
    if (_isPhoto) { /// 拍照
        // 1.根据设备输出获得链接
        AVCaptureConnection *captureConnection = [_captureStillImageOutput connectionWithMediaType:AVMediaTypeVideo];
        // 2.根据链接取得设备输出的数据
        [_captureStillImageOutput captureStillImageAsynchronouslyFromConnection:captureConnection completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
            NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
            UIImage *image = [UIImage imageWithData:imageData];
            _imageView.image = [UIImage imageWithCGImage:[self handleImage:image]];
            _imageView.hidden = NO;
        }];
        return;
    }
    /// 视频
    // 1.根据设备输出获得连接
    AVCaptureConnection *captureConnection = [_captureMovieFileOutput connectionWithMediaType:AVMediaTypeVideo];
    // 2.根据连接取得设备输出的数据
    if (![_captureMovieFileOutput isRecording]) {
        _enableRotation = NO;
        // 2.1如果支持多任务则开始多任务
        if ([[UIDevice currentDevice] isMultitaskingSupported]) {
            _backgroundTaskIndentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
        }
        // 2.2预览图层和视屏方向保持一致
        captureConnection.videoOrientation = [_captureVideoPreviewLayer connection].videoOrientation;
        NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"MaiMovie.mp4"];
        NSURL *fileURL = [NSURL fileURLWithPath:outputFilePath];
        self.fileU = fileURL;
        [_captureMovieFileOutput startRecordingToOutputFileURL:fileURL recordingDelegate:self];
    } else {
        [_captureMovieFileOutput stopRecording];

    }
}



- (void)importBtnClick {
    if (_isPhoto) {
        [self loadImageFinished:_imageView.image];
    } else {
        if (!iOS8Later) {
            
            ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
            [library writeVideoAtPathToSavedPhotosAlbum:self.videoUrl completionBlock:^(NSURL *assetURL, NSError *error){
                NSLog(@"save completed");
                //[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
                
            }];
        } else {
            
            __block NSString *createdAssetID =nil;//唯一标识，可以用于图片资源获取
            NSError *errorr =nil;
            [[PHPhotoLibrary sharedPhotoLibrary]performChangesAndWait:^{
                createdAssetID = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:self.videoUrl].placeholderForCreatedAsset.localIdentifier;
                NSLog(@"complete");
                
            } error:&errorr];
        }
    }
    
    
}




// 视频保存回调

- (void)video:(NSString *)videoPath didFinishSavingWithError:(NSError *)error contextInfo: (void *)contextInfo {
    
    NSLog(@"video===%@",videoPath);
    
    NSLog(@"%@",error);
    
}

- (void)loadImageFinished:(UIImage *)image
{
    UIImageWriteToSavedPhotosAlbum(image, self, @selector(image:didFinishSavingWithError:contextInfo:), (__bridge void *)self);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    
    NSLog(@"image = %@, error = %@, contextInfo = %@", image, error, contextInfo);
}

#pragma mark - private
- (void)restoreBtn {
    _leftBtn.frame = _leftBtnFrame;
    _centerBtn.frame = _centerBtnFrame;
    _rightBtn.frame = _rightBtnFrame;
    _dotLabel.hidden = NO;
    [_centerBtn setTitleColor:RGB(0x7ed321) forState:UIControlStateNormal];
}
/// 切换拍照和视频录制
///
/// @param isPhoto YES->拍照  NO->视频录制
- (void)ChangeToPhoto:(BOOL)isPhoto {
    [self restoreBtn];
    _isPhoto = isPhoto;
    NSString *centerTitle = isPhoto ? @"照片" : @"视频";
    [_centerBtn setTitle:centerTitle forState:UIControlStateNormal];
    _leftBtn.hidden = isPhoto;
    _rightBtn.hidden = !isPhoto;
    _progressView.hidden = isPhoto;
    //_importBtn.hidden = NO;
    
    UIImage *photoImage = [UIImage imageNamed:@"videoPlaying"];
    UIImage *mvImage = [UIImage imageNamed:@"videoPlaying"];
    UIImage *cameraImage = isPhoto ? photoImage : mvImage;
    [_cameraBtn setImage:cameraImage forState:UIControlStateNormal];
}

- (CGImageRef)handleImage:(UIImage *)image {
    UIGraphicsBeginImageContextWithOptions(self.view.size, NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, self.view.width, self.view.height)];
    CGImageRef imageRef = UIGraphicsGetImageFromCurrentImageContext().CGImage;
    CGImageRef subRef = CGImageCreateWithImageInRect(imageRef, CGRectOffset(_viewContainer.frame, 0, 88));
    return subRef;
}


@end
