#import <Foundation/Foundation.h>

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

/// Loads a `.moc3` and its model3 graph from a directory on disk.
/// Returns nil and fills `error` rather than trapping, so an unsupported or
/// corrupt model degrades to the static fallback.
- (nullable instancetype)initWithModelDirectory:(NSString *)directory
                                  model3FileName:(NSString *)model3FileName
                                           error:(NSError **)error;

@property (nonatomic, readonly) JoiLive2DModelFacts *facts;

/// Advances motion, physics and breath by `seconds`.
- (void)updateWithDelta:(NSTimeInterval)seconds;

/// Releases the model and its Core allocation exactly once.
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
