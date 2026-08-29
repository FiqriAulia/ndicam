#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C++ wrapper over the NDI send API. The implementation is only
/// active when the build defines `NDICAM_HAVE_NDI` and the NDI SDK headers are on
/// the header search path (iphoneos SDK only); otherwise every method is a no-op
/// so the project still builds and runs on the simulator.
@interface NDISenderBridge : NSObject

- (instancetype)initWithName:(NSString *)name NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Frame rate advertised on the NDI stream. Defaults to 30000/1001.
- (void)setFrameRateN:(int)n D:(int)d;

/// Send one BGRA (`kCVPixelFormatType_32BGRA`) pixel buffer. Safe to call from a
/// single dedicated capture queue. Blocks until NDI has consumed the frame.
- (void)send:(CVPixelBufferRef)pixelBuffer timestampNs:(int64_t)timestampNs;

/// Number of receivers currently connected (0 when built without the SDK).
- (NSInteger)connectionCount;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
