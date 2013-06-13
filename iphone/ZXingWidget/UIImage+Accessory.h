//
//  UIImage+Accessory.h
//  ZXingWidget
//
//  Created by remy on 6/8/13.
//
//

#import <UIKit/UIKit.h>

@interface UIImage (Accessory)
-(UIImage *)cropImagefromRect:(CGRect)rect;
-(void) toFileWithName:(NSString *) fileName;
+ (UIImage *)imageFromLayer:(CALayer *)layer;
- (UIImage *)imageRotatedByDegrees:(CGFloat)degrees;

    
@end
