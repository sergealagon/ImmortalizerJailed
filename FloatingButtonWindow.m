/* 
    Copyright (C) 2025  Serge Alagon

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>. 
*/
#import "FloatingButtonWindow.h"

@interface FloatingButtonWindow ()
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) UIView *handleView;
@property (nonatomic, assign) BOOL isImmortalized;
@property (nonatomic, assign) BOOL isDocked;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSTimer *dockTimer;
@end

static void vibrateDevice() {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
    [feedback prepare];
    [feedback impactOccurred];
}

@implementation FloatingButtonWindow

+ (instancetype)sharedInstance {
    static FloatingButtonWindow *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[FloatingButtonWindow alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super initWithFrame:UIScreen.mainScreen.bounds];
    if (self) {
        self.isImmortalized = [[NSUserDefaults standardUserDefaults] boolForKey:@"immortalized"];
        [self setupWindow];
        [self updateAndShowToast];
        [self setupButton];
        [self setupHandle];
    }
    return self;
}

- (void)setupWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            self.windowScene = (UIWindowScene *)scene;
            break;
        }
    }
    self.windowLevel = UIWindowLevelAlert + 1;
    self.userInteractionEnabled = YES;
    self.backgroundColor = [UIColor clearColor];
    self.rootViewController = [[UIViewController alloc] init];
    self.rootViewController.view.backgroundColor = [UIColor clearColor];
    self.hidden = YES;
}

- (void)setupButton {
    _floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _floatingButton.frame = CGRectMake(UIScreen.mainScreen.bounds.size.width - 50 - 30, 200, 50, 50);
    _floatingButton.backgroundColor = [UIColor colorWithRed:0.125 green:0.125 blue:0.125 alpha:1.0];
    [self updateButtonColor];
    _floatingButton.layer.cornerRadius = 25;
    _floatingButton.layer.masksToBounds = YES;

    UIImage *icon = [UIImage systemImageNamed:@"hourglass.tophalf.fill"];
    [_floatingButton setImage:icon forState:UIControlStateNormal];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [_floatingButton addGestureRecognizer:pan];
    
    [_floatingButton addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    [self.rootViewController.view addSubview:_floatingButton];
    [self snapButtonToNearestEdge:_floatingButton];
}

- (void)setupHandle {
    _handleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 15, 50)];
    _handleView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.7];
    _handleView.layer.cornerRadius = 6;
    _handleView.layer.masksToBounds = YES;
    _handleView.alpha = 0;
    _handleView.hidden = YES;  

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake((_handleView.frame.size.width - 2)/2, 
                                                          (_handleView.frame.size.height - 30)/2, 
                                                          3, 30)];
    line.backgroundColor = [UIColor whiteColor];
    line.layer.cornerRadius = 1;
    line.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [_handleView addSubview:line];

    UIPanGestureRecognizer *handlePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleHandlePan:)];
    [_handleView addGestureRecognizer:handlePan];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(undockButton)];
    [_handleView addGestureRecognizer:tap];

    [self.rootViewController.view addSubview:_handleView];
}

- (void)makeKeyWindow {
    [super makeKeyWindow];
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication.sharedApplication.windows.firstObject makeKeyWindow];
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    [self resetDockTimer];
    
    CGPoint translation = [gesture translationInView:self];
    
    [UIView animateWithDuration:0.2 animations:^{
        gesture.view.center = CGPointMake(gesture.view.center.x + translation.x,
                                        gesture.view.center.y + translation.y);
        [gesture setTranslation:CGPointZero inView:self];
    }];
    
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self snapButtonToNearestEdge:(UIButton *)gesture.view];
        [self startDockTimer];
    }
}

- (void)handleHandlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self undockButton];
        return;
    }
    
    CGPoint newCenter = CGPointMake(gesture.view.center.x + translation.x,
                                   gesture.view.center.y + translation.y);
    self.floatingButton.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self];
    
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self snapButtonToNearestEdge:self.floatingButton];
        [self startDockTimer];
    }
}

- (void)snapButtonToNearestEdge:(UIButton *)button {
    CGRect buttonFrame = button.frame;
    CGPoint newCenter = button.center;
    CGFloat screenWidth = self.bounds.size.width;
    CGFloat buttonWidth = buttonFrame.size.width;
    
    if (newCenter.x < screenWidth / 2) {
        newCenter.x = buttonWidth / 2;
    } else {
        newCenter.x = screenWidth - buttonWidth / 2;
    }
    
    newCenter.y = MAX(buttonFrame.size.height / 2, MIN(self.bounds.size.height - buttonFrame.size.height / 2, newCenter.y));
    
    [UIView animateWithDuration:0.3 animations:^{
        button.center = newCenter;
    }];
}

- (void)startDockTimer {
    [self.dockTimer invalidate];
    self.dockTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                    target:self
                                                  selector:@selector(dockButton)
                                                  userInfo:nil
                                                   repeats:NO];
}

- (void)resetDockTimer {
    if (self.isDocked) return;
    [self.dockTimer invalidate];
    [self startDockTimer];
}

- (void)dockButton {
    if (self.isDocked) return;
    
    self.isDocked = YES;
    
    CGRect buttonFrame = self.floatingButton.frame;
    CGRect handleFrame = self.handleView.frame;
    
    BOOL isLeftEdge = self.floatingButton.center.x < self.bounds.size.width / 2;
    CGFloat handleX = isLeftEdge ? 0 : self.bounds.size.width - handleFrame.size.width;
    
    handleFrame.origin = CGPointMake(handleX, buttonFrame.origin.y + (buttonFrame.size.height - handleFrame.size.height)/2);
    self.handleView.frame = handleFrame;
    
    [UIView animateWithDuration:0.3 animations:^{
        self.floatingButton.alpha = 0;
        self.floatingButton.transform = CGAffineTransformMakeScale(0.5, 0.5);
    } completion:^(BOOL finished) {
        self.floatingButton.hidden = YES;
        self.handleView.hidden = NO;
        
        [UIView animateWithDuration:0.2 animations:^{
            self.handleView.alpha = 1;
        }];
    }];
}

- (void)undockButton {
    if (!self.isDocked) return;
    
    self.isDocked = NO;
    self.floatingButton.hidden = NO;
    
    BOOL isLeftEdge = self.handleView.frame.origin.x < self.bounds.size.width / 2;
    CGPoint buttonCenter = self.handleView.center;
    buttonCenter.x = isLeftEdge ? self.handleView.frame.size.width + self.floatingButton.frame.size.width/2 : 
                                 self.bounds.size.width - self.handleView.frame.size.width - self.floatingButton.frame.size.width/2;
    
    self.floatingButton.center = buttonCenter;
    
    [UIView animateWithDuration:0.3 animations:^{
        self.handleView.alpha = 0;
        self.floatingButton.alpha = 1;
        self.floatingButton.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        self.handleView.hidden = YES;
        [self startDockTimer];
    }];
}

- (void)showButton {
    self.hidden = NO;
    [self makeKeyAndVisible];
    if (!self.isDocked) {
        [self startDockTimer];
    }
}

- (void)hideButton {
    self.hidden = YES;
    [self.dockTimer invalidate];
}


- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    CGPoint buttonPoint = [self convertPoint:point toView:self.floatingButton];
    if (!self.floatingButton.hidden && [self.floatingButton pointInside:buttonPoint withEvent:event]) {
        return [super hitTest:point withEvent:event];
    }
    
    CGPoint handlePoint = [self convertPoint:point toView:self.handleView];
    if (!self.handleView.hidden && [self.handleView pointInside:handlePoint withEvent:event]) {
        return [super hitTest:point withEvent:event];
    }
    
    return nil;
}

- (void)buttonTapped {
    [UIView animateWithDuration:0.1 animations:^{
        self.floatingButton.transform = CGAffineTransformMakeScale(1.2, 1.2);
        vibrateDevice();
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.1 animations:^{
            self.floatingButton.transform = CGAffineTransformIdentity;
        }];
        [[NSUserDefaults standardUserDefaults] setBool:!self.isImmortalized forKey:@"immortalized"];
        self.isImmortalized = !self.isImmortalized;
        notify_post("com.sergy.immortalizerjailed.updateprefs");
        [self updateButtonColor];
        [self updateAndShowToast];
    }];
}

- (void)updateAndShowToast {
    NSString *subtitle = @"";
    NSString *icon = @"";
    NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];

    if (self.isImmortalized) {
        subtitle = @"Immortalized";
        icon = @"hourglass.bottomhalf.fill";
        [self startTimer];
    } else {
        subtitle = @"At Rest";
        icon = @"arrow.uturn.left.circle.fill";
        [self stopTimer];
    }

    CustomToastView *toastView = [[CustomToastView alloc] initWithTitle:appName subtitle:subtitle 
                                    icon:[UIImage systemImageNamed:icon] autoHide:3.0];

    [toastView presentToastInViewController:self.rootViewController];
}

- (void)updateButtonColor {
    if (self.isImmortalized) {
        self.floatingButton.tintColor = [UIColor systemBlueColor];
    } else {
        self.floatingButton.tintColor = [UIColor systemRedColor];
    }
}

/* dirty trick to stop apps from being killed, don't judge me */
/* you may wonder why tf i need a timer that keeps calling the play method. */
/* well, there are apps that may play audio, and sometimes it can interfere with the playback of this white noise audio were playing here */
/* removed setActive = NO for AVAudioSession so it will never interfere with apps that plays audio */
/* ^^ this solves the hiccups / freezing of some apps */
/* i said i'll add other options for keeping the apps running, but meh, laziness is still sky high */

- (void)startTimer {
    [self.timer invalidate];
    
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(timerFired)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)stopTimer {
    [self stopPlayingSilentAudio];
    [self.timer invalidate];
    self.timer = nil;
}

- (void)timerFired {
    [self startPlayingSilentAudio];
}

- (void)startPlayingSilentAudio {
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];

    NSData *audioData = [[NSData alloc] initWithBase64EncodedString:kBase64Audio options:NSDataBase64DecodingIgnoreUnknownCharacters];

    self.audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil];
    self.audioPlayer.volume = 0.0; /* no sound should be made */
    [self.audioPlayer prepareToPlay];
    self.audioPlayer.numberOfLoops = -1;
    [self.audioPlayer play];
}

- (void)stopPlayingSilentAudio {
    [self.audioPlayer stop];
}

@end