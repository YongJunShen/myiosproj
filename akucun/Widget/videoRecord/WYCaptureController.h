//
//  WYCapture.h
//  WYAVFoundation
//
//  Created by 王俨 on 15/12/30.
//  Copyright © 2015年 wangyan. All rights reserved.
//

#import <UIKit/UIKit.h>
#define wy_RGB(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16)) / 255.0 green:((float)((rgbValue & 0xFF00) >> 8)) / 255.0 blue:((float)(rgbValue & 0xFF)) / 255.0 alpha:1.0]
#define APP_WIDTH [UIScreen mainScreen].bounds.size.width
#define APP_HEIGHT [UIScreen mainScreen].bounds.size.height

@interface WYCaptureController : UIViewController

@end
