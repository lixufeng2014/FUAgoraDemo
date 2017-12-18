//
//  FUManager.m
//  FULiveDemo
//
//  Created by 刘洋 on 2017/8/18.
//  Copyright © 2017年 刘洋. All rights reserved.
//

#import "FUManager.h"
#import "FURenderer.h"
#import "authpack-RTC2017.h"

@interface FUManager ()
{
    //MARK: Faceunity
    int items[3];
    int frameID;
}
@end

static FUManager *shareManager = NULL;

@implementation FUManager

+ (FUManager *)shareManager
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shareManager = [[FUManager alloc] init];
    });
    
    return shareManager;
}

- (instancetype)init
{
    if (self = [super init]) {
        
        //TODO: 调用FURenderer单例的setupWithDataPath: authPackage: authSize:方法，对 FaceunitySDK 初始化
        NSString *path = [[NSBundle mainBundle] pathForResource:@"v3.bundle" ofType:nil];
        
        [[FURenderer shareRenderer] setupWithDataPath:path authPackage:&g_auth_package authSize:sizeof(g_auth_package) shouldCreateContext:YES];
        
        /**开启多脸识别（最高可设为8，不过考虑到性能问题建议设为4以内*/
        [FURenderer setMaxFaces:4];
        
        /*列举道具资源*/
        self.itemsDataSource = @[@"noitem", @"lixiaolong", @"chibi_reimu", @"mask_liudehua", @"yuguan", @"gradient", @"Mood", @"bg_seg"];
        
        /*列举滤镜名称*/
        self.filtersDataSource = @[@"nature", @"delta", @"electric", @"slowlived", @"tokyo", @"warm"];

        /*设置默认参数*/
        [self setDefaultParameters];
    }
    
    return self;
}

/*设置默认参数*/
- (void)setDefaultParameters
{
    self.selectedItem = self.itemsDataSource[4]; //贴纸道具
    self.selectedFilter = self.filtersDataSource[0]; //滤镜效果
    self.selectedBlur = 6; //磨皮程度
    self.beautyLevel = 0.2; //美白程度
    self.redLevel = 0.5; //红润程度
    self.thinningLevel = 1.0; //瘦脸程度
    self.enlargingLevel = 0.5; //大眼程度
    self.faceShapeLevel = 0.5; //美型程度
    self.faceShape = 3; //美型类型
}

- (void)loadItems
{
    /**加载普通道具*/
    [self loadItem:self.selectedItem];
    
    //TODO: 调用loadFilter，加载美颜道具
    [self loadFilter];
}

/**销毁全部道具*/
- (void)destoryItems
{
    /**销毁道具前，为保证道具在被销毁时被使用而导致问题，需要先将int数组中的元素都设为0*/
    for (int i = 0; i < sizeof(items) / sizeof(int); i++) {
        items[i] = 0;
    }
    
    [FURenderer destroyAllItems];
    
    /**销毁道具后，清除context缓存*/
    [FURenderer OnDeviceLost];

    /**销毁道具后，重置人脸检测*/
    [FURenderer onCameraChange];
    
    /**销毁道具后，重置默认参数*/
    [self setDefaultParameters];
}

#pragma -Faceunity Load Data
/**
 加载普通道具
 - 先创建再释放可以有效缓解切换道具卡顿问题
 */
- (void)loadItem:(NSString *)itemName
{
    /**如果取消了道具的选择，直接销毁道具*/
    if ([itemName isEqual: @"noitem"] || itemName == nil)
    {
        if (items[0] != 0) {
            
            NSLog(@"faceunity: destroy item");
            [FURenderer destroyItem:items[0]];
            
            /**为避免道具句柄被销毁会后仍被使用导致程序出错，这里需要将存放道具句柄的items[0]设为0*/
            items[0] = 0;
        }
        
        return;
    }
    
    /**先创建道具句柄*/
    NSString *path = [[NSBundle mainBundle] pathForResource:[itemName stringByAppendingString:@".bundle"] ofType:nil];
    int itemHandle = [FURenderer itemWithContentsOfFile:path];
    
    /**销毁老的道具句柄*/
    if (items[0] != 0) {
        NSLog(@"faceunity: destroy item");
        [FURenderer destroyItem:items[0]];
    }
    
    /**将刚刚创建的句柄存放在items[0]中*/
    items[0] = itemHandle;
    
    NSLog(@"faceunity: load item %@",itemName);
}

/**加载美颜道具*/
- (void)loadFilter
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"face_beautification.bundle" ofType:nil];
    
    items[1] = [FURenderer itemWithContentsOfFile:path];
}

/**设置美颜参数*/
- (void)setBeautyParams
{
    /*设置美颜效果（滤镜、磨皮、美白、红润、瘦脸、大眼....）*/
    [FURenderer itemSetParam:items[1] withName:@"filter_name" value:self.selectedFilter]; //滤镜名称
    [FURenderer itemSetParam:items[1] withName:@"blur_level" value:@(self.selectedBlur)]; //磨皮 (0、1、2、3、4、5、6)
    [FURenderer itemSetParam:items[1] withName:@"color_level" value:@(self.beautyLevel)]; //美白 (0~1)
    [FURenderer itemSetParam:items[1] withName:@"red_level" value:@(self.redLevel)]; //红润 (0~1)
    [FURenderer itemSetParam:items[1] withName:@"face_shape" value:@(self.faceShape)]; //美型类型 (0、1、2、3) 默认：3，女神：0，网红：1，自然：2
    [FURenderer itemSetParam:items[1] withName:@"face_shape_level" value:@(self.faceShapeLevel)]; //美型等级 (0~1)
    [FURenderer itemSetParam:items[1] withName:@"eye_enlarging" value:@(self.enlargingLevel)]; //大眼 (0~1)
    [FURenderer itemSetParam:items[1] withName:@"cheek_thinning" value:@(self.thinningLevel)]; //瘦脸 (0~1)
    
}

/**将道具绘制到YUVFrame*/
- (void)renderItemsToYUVFrame:(void*)y u:(void*)u v:(void*)v ystride:(int)ystride ustride:(int)ustride vstride:(int)vstride width:(int)width height:(int)height
{
    /**设置美颜参数*/
    [self setBeautyParams];
    
    /*将道具及美颜效果绘制到YUVFrame中*/
    [[FURenderer shareRenderer] renderFrame:y u:u v:v ystride:ystride ustride:ustride vstride:vstride width:width height:height frameId:frameID items:items itemCount:3 flipx:NO];//flipx 参数设为YES可以使道具做水平方向的镜像翻转
    frameID += 1;
}

@end
