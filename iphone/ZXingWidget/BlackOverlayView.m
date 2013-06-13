//
//  BlackOverlayView.m
//  ZXingWidget
//
//  Created by remy on 6/9/13.
//
//

#import "BlackOverlayView.h"

@implementation BlackOverlayView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
    }
    return self;
}

// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
//    CGContextRef context = UIGraphicsGetCurrentContext();
//    CGContextAddRect(context, self.transparentRect);
//    CGContextClip(context);
//    [[UIColor redColor] setFill];
//    CGContextFillRect(context, self.bounds);
    
//    [[UIColor blackColor] setFill];
    [[UIColor colorWithRed:0 green:0 blue:0 alpha:0.8] setFill];
    UIRectFill( rect );
    
    // Assume that there's an ivar somewhere called holeRect of type CGRect
    // We could just fill holeRect, but it's more efficient to only fill the
    // area we're being asked to draw.
    CGRect holeRectIntersection = CGRectIntersection( self.transparentRect, rect );
    
    [[UIColor clearColor] setFill];
    UIRectFill( holeRectIntersection );
}

@end
