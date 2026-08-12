#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/// Facts read from a real Cubism model after Core has loaded it. These are
/// measured, not declared: the counts come from the loaded `.moc3`, so a value
/// here is evidence that the native runtime parsed the model.
@interface JoiLive2DModelFacts : NSObject
@property (nonatomic, readonly) float canvasWidth;
@property (nonatomic, readonly) float canvasHeight;
@property (nonatomic, readonly) float pixelsPerUnit;
@property (nonatomic, readonly) NSInteger parameterCount;
@property (nonatomic, readonly) NSInteger partCount;
@property (nonatomic, readonly) NSInteger drawableCount;
@end

/// Thin Objective-C++ boundary over the Cubism Native Framework.
///
/// Cubism owns global, non-thread-safe C++ state, so every entry point here must
/// be reached from one place only. `Live2DNativeStage` confines it to a single
/// actor; nothing in this header is safe to call concurrently.
@interface JoiLive2DModel : NSObject

/// Initialises the Cubism Framework once per process. Safe to call repeatedly.
+ (BOOL)startRuntime;

/// Must be called with the render device before any model is loaded.
+ (void)configureRenderDevice:(id<MTLDevice>)device;

/// Loads a `.moc3` and its model3 graph from a directory on disk.
/// Returns nil and fills `error` rather than trapping, so an unsupported or
/// corrupt model degrades to the static fallback.
- (nullable instancetype)initWithModelDirectory:(NSString *)directory
                                  model3FileName:(NSString *)model3FileName
                                           error:(NSError **)error;

@property (nonatomic, readonly) JoiLive2DModelFacts *facts;

/// Advances motion, physics and breath by `seconds`.
- (void)updateWithDelta:(NSTimeInterval)seconds;

/// Creates the Metal renderer and uploads the model's textures. Returns NO when
/// any texture is missing, so the caller can fall back rather than draw a
/// partially textured model.
///
/// The mask size must be the drawable size in pixels, not the model canvas:
/// sizing it from the canvas leaves clipped parts drawn as opaque quads.
- (BOOL)prepareRendererWithDevice:(id<MTLDevice>)device
                       maskWidth:(NSUInteger)maskWidth
                      maskHeight:(NSUInteger)maskHeight;

/// Draws one frame. `scaleX`/`scaleY` are the model-to-clip scale and
/// `translateY` shifts the framing; the caller owns aspect and framing policy.
- (void)drawWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
         renderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor
                     viewport:(MTLViewport)viewport
                       scaleX:(float)scaleX
                       scaleY:(float)scaleY
                   translateY:(float)translateY;

/// Releases the model and its Core allocation exactly once.
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
