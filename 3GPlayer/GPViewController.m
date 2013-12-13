//
//  GPViewController.m
//

#import "GPViewController.h"
#import "GPDecoder.h"
@import AVFoundation;
@import MediaPlayer;

@interface GPViewController () <AVAudioPlayerDelegate>

@property NSString *baseDir;
@property NSURL *decodedURL;

@property NSMutableArray *fileList;
@property NSMutableArray *history;

@property NSTimer *timer;
@property AVAudioPlayer *audioPlayer;
@property UILabel *elapsedTimeLabel;
@property UISlider *timeSlider;
@property UIButton *playButton;

@property BOOL isPlaying;

@end

@implementation GPViewController

#define kGPViewControllerHistory @"kGPViewControllerHistory"

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"3GP Player";
    
    [self.view setTintColor:[UIColor blueColor]];
    
	// Do any additional setup after loading the view, typically from a nib.
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:(UIBarButtonSystemItemRefresh) target:self action:@selector(clearAll:)];
    
    id history = [[NSUserDefaults standardUserDefaults]objectForKey:kGPViewControllerHistory];
    if(!history || ![history isKindOfClass:[NSMutableArray class]])
    {
        self.history = [NSMutableArray arrayWithCapacity:10];
        [self saveHistory];
    }else{
        self.history = history;
    }
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    self.baseDir = documentsDirectory;
    
    self.decodedURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"decoded.wav"]];
    
    self.fileList = [NSMutableArray arrayWithCapacity:10];
    [self getAllFileNamesInFolder:documentsDirectory];
    
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]initWithTitle:@"[]" style:(UIBarButtonItemStylePlain) target:nil action:nil];
    [self showNumberOfPlayedFile];
    
}
-(void)showNumberOfPlayedFile
{
    NSInteger count = 0;
    for (NSString *fileName in self.history) {
        if([self.fileList indexOfObject:fileName] != NSNotFound)
        {
            count++;
        }
    }
    
    NSString *title = [NSString stringWithFormat:@"[%ld/%lu]",(long)count,(unsigned long)self.fileList.count];
    [self.navigationItem.leftBarButtonItem setTitle:title];
}

-(IBAction)clearAll:(id)sender
{
    [self.history removeAllObjects];
    [self showNumberOfPlayedFile];
    [self saveHistory];
    [self.tableView reloadData];
}
-(void)saveHistory
{
    [[NSUserDefaults standardUserDefaults]setObject:self.history forKey:kGPViewControllerHistory];
    [[NSUserDefaults standardUserDefaults]synchronize];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.fileList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    static NSString *CellIdentifier = @"GPTableCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];

    NSString *fileName = self.fileList[indexPath.row];
    cell.textLabel.text = fileName;
    
    if([self.history indexOfObject:fileName] == NSNotFound)
    {
        cell.backgroundColor = [UIColor whiteColor];
    }else{
        CGFloat color = 233.0/255.0;
        cell.backgroundColor = [UIColor colorWithRed:color green:color blue:color alpha:1.0];
    }
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    NSString *fileName = self.fileList[indexPath.row];
    BOOL playResult = [self playFile:fileName];

    if(playResult)
    {
        if([self.history indexOfObject:fileName] == NSNotFound){
            [self.history addObject:fileName];
            [self saveHistory];
            [self showNumberOfPlayedFile];
            [tableView reloadSections:[[NSIndexSet alloc]initWithIndex:0] withRowAnimation:(UITableViewRowAnimationFade)];
        }
    }else{
        [[[UIAlertView alloc]initWithTitle:@"Error" message:[NSString stringWithFormat:@"[%@] can't play",fileName] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil]show];

    }

}

-(BOOL)loadAudioFile:(NSString *)path
{
    if(self.audioPlayer)
    {
        [self stopTimer];
        [self.audioPlayer stop];
        self.audioPlayer = nil;
        self.isPlaying = NO;
        
        NSError *error;
        [[NSFileManager defaultManager]removeItemAtURL:self.decodedURL error:&error];
        if(error)
        {
            NSLog(@"Remove decoded file error :%@", error);
            return NO;
        }
    }
    ///TODO: Error Handling
    NSError *error;
    if(![self decodeWithPath:[self.baseDir stringByAppendingPathComponent:path]])
    {
        NSLog(@"Decode fail");
        return NO;
    }
    self.audioPlayer = [[AVAudioPlayer alloc]initWithContentsOfURL:self.decodedURL error:&error];
    if(!self.audioPlayer)
    {
        ///TODO: Error Handling
        NSLog(@"Error with creating the player: %@", error);
    }else{
        self.audioPlayer.delegate = self;
        return YES;
    }
    return NO;
}

-(BOOL)playFile:(NSString *)path
{
    if(![self loadAudioFile:path])
    {
        [self.navigationController setToolbarHidden:YES];
        return NO;
    }
    
    if(self.navigationController.toolbarHidden)
    {
        UIButton *playButton = [[UIButton alloc]initWithFrame:CGRectMake(0, 0, 44, 44)];
        
        [playButton addTarget:self action:@selector(playButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [playButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
        
        self.playButton = playButton;
        UIBarButtonItem *playBarButton = [[UIBarButtonItem alloc]initWithCustomView:playButton];
        
        //Slider
        UISlider *timeSlider = [[UISlider alloc]initWithFrame:CGRectMake(0, 0, 180, 44)];
        [timeSlider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
        [timeSlider addTarget:self action:@selector(sliderTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
        self.timeSlider = timeSlider;
        UIBarButtonItem *sliderBarButton = [[UIBarButtonItem alloc]initWithCustomView:timeSlider];
        
        //Label
        UILabel *elapsedTimeLabel = [[UILabel alloc]initWithFrame:CGRectMake(0, 0, 96, 44)];
        elapsedTimeLabel.text = [self formattedAudioTime:0];
        self.elapsedTimeLabel = elapsedTimeLabel;
        UIBarButtonItem *durationBarButton = [[UIBarButtonItem alloc]initWithCustomView:elapsedTimeLabel];
        
        self.toolbarItems = @[playBarButton,sliderBarButton,durationBarButton];
        [self.navigationController setToolbarHidden:NO];
    }
    
    NSString *prompt = [NSString stringWithFormat:@"Duration : [%@]",[self formattedAudioTime:self.audioPlayer.duration]];
    [self.navigationItem setPrompt:prompt];
    self.title = path;
    
    self.timeSlider.minimumValue = 0.0f;
    self.timeSlider.maximumValue = self.audioPlayer.duration;

    [self toggleAudioPlaying];
//    NSLog(@"Play %@",path);
    return YES;
}
#pragma mark - File Utility
-(void)getAllFileNamesInFolder:(NSString *)folderPath
{
    BOOL isDir;
    
    [[NSFileManager defaultManager] fileExistsAtPath:folderPath isDirectory:&isDir];
        
    if(isDir)
    {
        NSArray *contentOfDirectory=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folderPath error:NULL];
        
        NSInteger contentcount = [contentOfDirectory count];
        int i;
        for(i=0;i<contentcount;i++)
        {
            NSString *fileName = [contentOfDirectory objectAtIndex:i];
            NSString *path = [folderPath stringByAppendingPathComponent:fileName];

            [self getAllFileNamesInFolder:path];
        }
    }
    else
    {

        folderPath = [folderPath substringFromIndex:self.baseDir.length + 1];
        if([[folderPath lastPathComponent] hasPrefix:@"."])
        {
            NSLog(@"Hidden File! : %@",folderPath);
            return;
        }
        
        [self.fileList addObject:folderPath];
    }
}
#pragma mark - Enc/Dec

-(NSString *)decodeWithPath:(NSString *)originalPath
{
    NSString *decodedPath = self.decodedURL.path;
    NSDate* methodStart = [NSDate date];  // Capture start time.
    NSLog(@"Start");

    GPDecoder *decoder = [[GPDecoder alloc]init];
    BOOL result = [decoder decodeWith:originalPath To:decodedPath];
    NSLog(@"DEBUG Method %s ran. Elapsed: %f seconds.", __func__, -([methodStart timeIntervalSinceNow]));  // Calculate and report elapsed time.
    if(result){
        return decodedPath;
    }else{
        return nil;
    }
}

-(IBAction)sliderValueChanged:(id)sender
{
    if(self.audioPlayer.isPlaying)
    {
        //Stop
        [self toggleAudioPlaying];
    }
    self.audioPlayer.currentTime = self.timeSlider.value;
    [self updateDisplay];
}
- (IBAction)sliderTouchUpInside:(id)sender
{
    if(!self.audioPlayer.isPlaying)
    {
        //Play
        [self toggleAudioPlaying];
    }
}

-(IBAction)playButtonTapped:(id)sender
{
    [self toggleAudioPlaying];
}

-(void)toggleAudioPlaying
{
    NSLog(@"Toggle Audio Playing");
    if(self.audioPlayer.playing){
        [self pausePlaying];
    }else{
        //Play
        self.timer = [NSTimer
                      scheduledTimerWithTimeInterval:0.1
                      target:self selector:@selector(timerFired:)
                      userInfo:nil repeats:YES];
        [self.audioPlayer play];
        self.isPlaying = YES;
        [self.playButton setTitle:@"◼︎" forState:UIControlStateNormal];
        
    }
}
-(void)pausePlaying
{
    //Pause
    [self stopTimer];
    [self updateDisplay];
    [self.audioPlayer pause];
    [self.playButton setTitle:@"▸" forState:UIControlStateNormal];
    self.isPlaying =NO;
    
}
- (void)timerFired:(NSTimer*)timer
{
    [self updateDisplay];
}

- (void)stopTimer
{
    [self.timer invalidate];
    self.timer = nil;
}

- (void)updateDisplay
{
    NSTimeInterval currentTime = self.audioPlayer.currentTime;
    self.elapsedTimeLabel.text = [self formattedAudioTime:(NSInteger)self.audioPlayer.currentTime];
    self.timeSlider.value = currentTime;
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    [self pausePlaying];
}

-(NSString *)formattedAudioTime:(NSInteger)currentTime
{
    
    if(!self.audioPlayer || self.audioPlayer.duration == 0)
    {
        return @"--:--";
    }
    NSInteger currentMins = (NSInteger)(currentTime/60);
    NSInteger currentSec  = (NSInteger)(currentTime%60);
    
    NSString *formattedTime =
    [NSString stringWithFormat:@"%02ld:%02ld",(long)currentMins,(long)currentSec];
    return formattedTime;
    
}

@end
