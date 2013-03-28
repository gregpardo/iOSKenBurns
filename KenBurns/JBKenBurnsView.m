//
//  KenBurnsView.m
//  KenBurns
//
//  Created by Javier Berlana on 9/23/11.
//  Copyright (c) 2011, Javier Berlana
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this
//  software and associated documentation files (the "Software"), to deal in the Software
//  without restriction, including without limitation the rights to use, copy, modify, merge,
//  publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
//  to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies
//  or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
//  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
//  PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
//  FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
//  ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

#import "JBKenBurnsView.h"
#include <stdlib.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>

#define enlargeRatio 1.2
#define imageBufer 3

// Private interface
@interface KenBurnsView ()

@property (nonatomic) int currentImage;
@property (nonatomic) BOOL animationInCurse;
@property (nonatomic) int totalImageCount;

- (void) _animate:(NSNumber*)num withImage:(UIImage*)image;
- (void) _startAnimations:(NSArray*)images;
- (void) _startAsynchronousAnimations:(NSArray *)urls;
- (UIImage *) _downloadImageFrom:(NSString *)url;
- (void) _notifyDelegate:(NSNumber *) imageIndex;
@end


@implementation KenBurnsView

@synthesize imagesArray, timeTransition, isLoop, isPortrait;
@synthesize animationInCurse, currentImage, delegate;


-(id)init
{
    self = [super init];
    if (self) {
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (void) animateWithImages:(NSMutableArray *)images transitionDuration:(float)duration loop:(BOOL)shouldLoop isPortrait:(BOOL)isPortrait;
{
    self.imagesArray      = images;
    self.timeTransition   = duration;
    self.isLoop           = shouldLoop;
    self.isPortrait       = isPortrait;
    self.animationInCurse = NO;
    self.totalImageCount  = [images count];
    
    self.layer.masksToBounds = YES;
    
    [NSThread detachNewThreadSelector:@selector(_startAnimations:) toTarget:self withObject:images];
    
}

- (void) animateWithURLs:(NSArray *)urls transitionDuration:(float)duration loop:(BOOL)shouldLoop isPortrait:(BOOL)isPortrait;
{
    self.imagesArray      = [[NSMutableArray alloc] init];
    self.timeTransition   = duration;
    self.isLoop           = shouldLoop;
    self.isPortrait       = isPortrait;
    self.animationInCurse = NO;
    self.totalImageCount  = [urls count];
    
    int bufferSize = (imageBufer < urls.count) ? imageBufer : urls.count;
    __block BOOL busy = YES;
    dispatch_queue_t myQueue = dispatch_queue_create("tbfiBufferImageQueue", 0);
    
    // Fill the buffer.
    dispatch_sync(myQueue, ^{
        for(int i = 0; i < bufferSize; i++) {
            NSString *url = [urls objectAtIndex:i];
            if([url hasPrefix:@"assets"]) {
                ALAssetsLibrary* assetslibrary = [[ALAssetsLibrary alloc] init];
                
                ALAssetsLibraryAssetForURLResultBlock resultblock = ^(ALAsset *myasset) {
                    CGImageRef imageRef = [[myasset defaultRepresentation] fullResolutionImage];
                    UIImage *image = [UIImage imageWithCGImage:imageRef];
                    
                    [self.imagesArray addObject:image];
                    if([self.imagesArray count] == bufferSize) {
                        busy = false;
                    }
                };
                
                [assetslibrary assetForURL:[NSURL URLWithString:url]
                               resultBlock:resultblock
                              failureBlock:^(NSError *error) {
                                  NSLog(@"error couldn't get photo");
                                  busy = false;
                              }];
            } else {
                UIImage *image = [[UIImage alloc] initWithContentsOfFile:url];
                [self.imagesArray addObject:image];
                
                if([self.imagesArray count] == bufferSize) {
                    busy = false;
                }
            }
        }
    });
    
    while(busy) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }
    
    self.layer.masksToBounds = YES;
    
    [NSThread detachNewThreadSelector:@selector(_startAsynchronousAnimations:) toTarget:self withObject:urls];
    
}

- (void) _startAnimations:(NSArray *)images
{
    for (uint i = 0; i < [images count]; i++) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            if([self.delegate respondsToSelector:@selector(willShowImageAtIndex:)]) {
                [self.delegate willShowImageAtIndex:i];
            }
            
            [self _animate:[NSNumber numberWithInt:i]
                 withImage:[images objectAtIndex:i]];
        });
        
        sleep(self.timeTransition);
        
        i = (i == [images count] - 1) && isLoop ? -1 : i;
        
    }
}

- (UIImage *) _downloadImageFrom:(NSString *) url {
    NSURL *imageURL = nil;
    if([url hasPrefix:@"/"] || [url hasPrefix:@"file://"]) {
        imageURL = [NSURL fileURLWithPath:url];
    } else if([url hasPrefix:@"assets-library://"]) {
        ALAssetsLibrary* assetslibrary = [[ALAssetsLibrary alloc] init];
        
        ALAssetsLibraryAssetForURLResultBlock resultblock = ^(ALAsset *myasset) {
            CGImageRef imageRef = [[myasset defaultRepresentation] fullResolutionImage];
            UIImage *image = [UIImage imageWithCGImage:imageRef];
            
            [self.imagesArray addObject:image];
        };
        
        [assetslibrary assetForURL:[NSURL URLWithString:url]
                       resultBlock:resultblock
                      failureBlock:^(NSError *error) {
                          NSLog(@"error couldn't get photo");
                      }];
        return nil;
    } else {
        imageURL = [NSURL URLWithString:url];
    }
    
    UIImage *image = nil;
    
    if(![imageURL isFileURL]) {
        image = [UIImage imageWithData:[NSData dataWithContentsOfURL:imageURL]];
    } else {
        image = [UIImage imageWithData:[NSData dataWithContentsOfFile:url]];
    }
    
    return image;
}

- (void) _startAsynchronousAnimations:(NSArray *)urls
{
    int bufferIndex = [self.imagesArray count];
    
    BOOL preloadImage = YES;
    if([urls count] <= [self.imagesArray count]) {
        preloadImage = NO;
    }
    for (int urlIndex = 0; urlIndex < [urls count]; urlIndex++, bufferIndex++) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            if([self.delegate respondsToSelector:@selector(willShowImageAtIndex:)]) {
                [self.delegate willShowImageAtIndex:urlIndex];
            }
            
            NSUInteger loadingImageIndex = preloadImage ? 0 : urlIndex;
            [self _animate:[NSNumber numberWithInt:urlIndex]
                 withImage:[self.imagesArray objectAtIndex:loadingImageIndex]];
        });
        
        if(preloadImage) {
            [self.imagesArray removeObjectAtIndex:0];
            UIImage *preloadedImage = [self _downloadImageFrom:[urls objectAtIndex: bufferIndex]];
            if(preloadedImage != nil) {
                [self.imagesArray addObject:preloadedImage];
            }
            
            if(bufferIndex == self.totalImageCount - 1) {
                NSLog(@"Wrapping!!");
                bufferIndex = -1;
            }
        }
        
        urlIndex = (urlIndex == [urls count] - 1) && isLoop ? -1 : urlIndex;
        
        sleep(self.timeTransition);
    }

}

- (void) _animate:(NSNumber*)num withImage:(UIImage*)image {
    UIImageView *imageView;
    
    float resizeRatio   = -1;
    float widthDiff     = -1;
    float heightDiff    = -1;
    float originX       = -1;
    float originY       = -1;
    float zoomInX       = -1;
    float zoomInY       = -1;
    float moveX         = -1;
    float moveY         = -1;
    float frameWidth    = isPortrait? self.frame.size.width : self.frame.size.height;
    float frameHeight   = isPortrait? self.frame.size.height : self.frame.size.width;
    
    // Widder than screen
    if (image.size.width > frameWidth)
    {
        widthDiff  = image.size.width - frameWidth;
        
        // Higher than screen
        if (image.size.height > frameHeight)
        {
            heightDiff = image.size.height - frameHeight;
            
            if (widthDiff > heightDiff)
                resizeRatio = frameHeight / image.size.height;
            else
                resizeRatio = frameWidth / image.size.width;
            
            // No higher than screen
        }
        else
        {
            heightDiff = frameHeight - image.size.height;
            
            if (widthDiff > heightDiff)
                resizeRatio = frameWidth / image.size.width;
            else
                resizeRatio = self.bounds.size.height / image.size.height;
        }
        
        // No widder than screen
    }
    else
    {
        widthDiff  = frameWidth - image.size.width;
        
        // Higher than screen
        if (image.size.height > frameHeight)
        {
            heightDiff = image.size.height - frameHeight;
            
            if (widthDiff > heightDiff)
                resizeRatio = image.size.height / frameHeight;
            else
                resizeRatio = frameWidth / image.size.width;
            
            // No higher than screen
        }
        else
        {
            heightDiff = frameHeight - image.size.height;
            
            if (widthDiff > heightDiff)
                resizeRatio = frameWidth / image.size.width;
            else
                resizeRatio = frameHeight / image.size.height;
        }
    }
    
    // Resize the image.
    float optimusWidth  = (image.size.width * resizeRatio) * enlargeRatio;
    float optimusHeight = (image.size.height * resizeRatio) * enlargeRatio;
    imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, optimusWidth, optimusHeight)];
    
    // Calcule the maximum move allowed.
    float maxMoveX = optimusWidth - frameWidth;
    float maxMoveY = optimusHeight - frameHeight;
    
    float rotation = (arc4random() % 9) / 100;
    
    switch (arc4random() % 4) {
        case 0:
            originX = 0;
            originY = 0;
            zoomInX = 1.25;
            zoomInY = 1.25;
            moveX   = -maxMoveX;
            moveY   = -maxMoveY;
            break;
            
        case 1:
            originX = 0;
            originY = frameHeight - optimusHeight;
            zoomInX = 1.10;
            zoomInY = 1.10;
            moveX   = -maxMoveX;
            moveY   = maxMoveY;
            break;
            
            
        case 2:
            originX = frameWidth - optimusWidth;
            originY = 0;
            zoomInX = 1.30;
            zoomInY = 1.30;
            moveX   = maxMoveX;
            moveY   = -maxMoveY;
            break;
            
        case 3:
            originX = frameWidth - optimusWidth;
            originY = frameHeight - optimusHeight;
            zoomInX = 1.20;
            zoomInY = 1.20;
            moveX   = maxMoveX;
            moveY   = maxMoveY;
            break;
            
        default:
            NSLog(@"def");
            break;
    }
    
    CALayer *picLayer    = [CALayer layer];
    picLayer.contents    = (id)image.CGImage;
    picLayer.anchorPoint = CGPointMake(0, 0);
    picLayer.bounds      = CGRectMake(0, 0, optimusWidth, optimusHeight);
    picLayer.position    = CGPointMake(originX, originY);
    
    [imageView.layer addSublayer:picLayer];
    
    CATransition *animation = [CATransition animation];
    [animation setDuration:1];
    [animation setType:kCATransitionFade];
    [[self layer] addAnimation:animation forKey:nil];
    
    // Remove the previous view
    if ([[self subviews] count] > 0){
        [[[self subviews] objectAtIndex:0] removeFromSuperview];
    }
    
    [self addSubview:imageView];
    
    // Generates the animation
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:self.timeTransition + 2];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
    CGAffineTransform rotate    = CGAffineTransformMakeRotation(rotation);
    CGAffineTransform moveRight = CGAffineTransformMakeTranslation(moveX, moveY);
    CGAffineTransform combo1    = CGAffineTransformConcat(rotate, moveRight);
    CGAffineTransform zoomIn    = CGAffineTransformMakeScale(zoomInX, zoomInY);
    CGAffineTransform transform = CGAffineTransformConcat(zoomIn, combo1);
    imageView.transform = transform;
    [UIView commitAnimations];
    
    [self performSelector:@selector(_notifyDelegate:) withObject:num afterDelay:self.timeTransition];
    
}

- (void) _notifyDelegate: (NSNumber *)imageIndex
{
    if (delegate) {
        if([self.delegate respondsToSelector:@selector(didShowImageAtIndex:)]) {
            [self.delegate didShowImageAtIndex:[imageIndex intValue]];
        }
        
        if ([imageIndex intValue] == (self.totalImageCount - 1) &&
            !isLoop &&
            [self.delegate respondsToSelector:@selector(didFinishAllAnimations)]) {
            [self.delegate didFinishAllAnimations];
        } 
    }
    
}

@end
