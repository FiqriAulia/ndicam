#import "NDISenderBridge.h"
#import <stdlib.h>
#import <string.h>

// `NDICAM_HAVE_NDI` is defined by the build only for the iphoneos SDK (the iOS
// static lib has no arm64-simulator slice). Simulator builds fall through to the
// no-op path so the app still compiles and runs there.
#if defined(NDICAM_HAVE_NDI) && __has_include(<Processing.NDI.Lib.h>)
#import <Processing.NDI.Lib.h>
#define NDICAM_NDI_ACTIVE 1
#else
#define NDICAM_NDI_ACTIVE 0
#endif

@implementation NDISenderBridge {
#if NDICAM_NDI_ACTIVE
    NDIlib_send_instance_t _send;
#endif
    NSString *_name;
    int _fpsN;
    int _fpsD;
    uint8_t *_scratch;      // contiguous NV12 staging buffer, reused across frames
    size_t _scratchCap;
}

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (!self) return nil;
    _name = [name copy];
    _fpsN = 30000;
    _fpsD = 1001;
#if NDICAM_NDI_ACTIVE
    if (!NDIlib_initialize()) {
        NSLog(@"[NDICam] NDIlib_initialize failed (unsupported CPU?)");
        return self;
    }
    NDIlib_send_create_t desc;
    desc.p_ndi_name = _name.UTF8String;
    desc.p_groups = NULL;
    desc.clock_video = true;
    desc.clock_audio = false;
    _send = NDIlib_send_create(&desc);
    if (!_send) {
        NSLog(@"[NDICam] NDIlib_send_create failed");
    } else {
        NSLog(@"[NDICam] NDI sender live: %@", _name);
    }
#else
    NSLog(@"[NDICam] NDISenderBridge built without NDI SDK - no-op");
#endif
    return self;
}

- (void)dealloc {
    free(_scratch);
}

- (void)setFrameRateN:(int)n D:(int)d {
    if (n > 0 && d > 0) { _fpsN = n; _fpsD = d; }
}

- (void)send:(CVPixelBufferRef)pixelBuffer timestampNs:(int64_t)timestampNs {
#if NDICAM_NDI_ACTIVE
    if (!_send || !pixelBuffer) return;
    if (CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) return;

    NDIlib_video_frame_v2_t frame;
    memset(&frame, 0, sizeof(frame));
    frame.xres = (int)CVPixelBufferGetWidth(pixelBuffer);
    frame.yres = (int)CVPixelBufferGetHeight(pixelBuffer);
    frame.frame_rate_N = _fpsN;
    frame.frame_rate_D = _fpsD;
    frame.picture_aspect_ratio = (float)frame.xres / (float)frame.yres;
    frame.frame_format_type = NDIlib_frame_format_type_progressive;
    frame.timecode = timestampNs / 100; // NDI timecode is 100ns units

    const OSType pf = CVPixelBufferGetPixelFormatType(pixelBuffer);
    const BOOL isNV12 = (pf == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
                         pf == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);

    if (isNV12 && CVPixelBufferGetPlaneCount(pixelBuffer) == 2) {
        uint8_t *y  = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        uint8_t *uv = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
        const size_t strideY  = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
        const size_t strideUV = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
        const size_t hY  = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
        const size_t hUV = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);

        frame.FourCC = NDIlib_FourCC_type_NV12;

        const BOOL contiguous = (strideUV == strideY) && (uv == y + strideY * hY);
        if (contiguous) {
            frame.p_data = y;
            frame.line_stride_in_bytes = (int)strideY;
            NDIlib_send_send_video_v2(_send, &frame);
        } else {
            // Stage Y then UV into one buffer with a single (Y) stride.
            const size_t need = strideY * hY + strideY * hUV;
            if (_scratchCap < need) {
                free(_scratch);
                _scratch = (uint8_t *)malloc(need);
                _scratchCap = _scratch ? need : 0;
            }
            if (_scratch) {
                memcpy(_scratch, y, strideY * hY);
                uint8_t *dstUV = _scratch + strideY * hY;
                if (strideUV == strideY) {
                    memcpy(dstUV, uv, strideY * hUV);
                } else {
                    const size_t row = strideUV < strideY ? strideUV : strideY;
                    for (size_t r = 0; r < hUV; r++) {
                        memcpy(dstUV + r * strideY, uv + r * strideUV, row);
                    }
                }
                frame.p_data = _scratch;
                frame.line_stride_in_bytes = (int)strideY;
                NDIlib_send_send_video_v2(_send, &frame);
            }
        }
    } else {
        // Fallback: packed BGRA.
        frame.FourCC = NDIlib_FourCC_type_BGRA;
        frame.line_stride_in_bytes = (int)CVPixelBufferGetBytesPerRow(pixelBuffer);
        frame.p_data = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
        NDIlib_send_send_video_v2(_send, &frame);
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
#else
    (void)pixelBuffer; (void)timestampNs;
#endif
}

- (NSInteger)connectionCount {
#if NDICAM_NDI_ACTIVE
    if (!_send) return 0;
    return NDIlib_send_get_no_connections(_send, 0);
#else
    return 0;
#endif
}

- (void)stop {
#if NDICAM_NDI_ACTIVE
    if (_send) {
        NDIlib_send_destroy(_send);
        _send = NULL;
    }
    NDIlib_destroy();
#endif
}

@end
