#import "JoiLive2DModel.h"

#import <MetalKit/MetalKit.h>

#import <CubismFramework.hpp>
#import <CubismDefaultParameterId.hpp>
#import <CubismModelSettingJson.hpp>
#import <Effect/CubismBreath.hpp>
#import <Effect/CubismEyeBlink.hpp>
#import <Id/CubismIdManager.hpp>
#import <Math/CubismMatrix44.hpp>
#import <Model/CubismUserModel.hpp>
#import <Motion/CubismBreathUpdater.hpp>
#import <Motion/CubismEyeBlinkUpdater.hpp>
#import <Motion/CubismExpressionUpdater.hpp>
#import <Motion/CubismMotion.hpp>
#import <Motion/CubismPhysicsUpdater.hpp>
#import <Motion/CubismPoseUpdater.hpp>
#import <Physics/CubismPhysics.hpp>
#import <Rendering/Metal/CubismRenderer_Metal.hpp>
#import <Utils/CubismString.hpp>

#include <map>
#include <string>
#include <vector>

using namespace Live2D::Cubism::Framework;

static NSString *const JoiLive2DErrorDomain = @"com.joi.mobile.live2d";

namespace {

/// Cubism requires an allocator to be supplied by the host. This is the minimal
/// correct implementation; Cubism never frees through any other path.
class JoiAllocator : public Csm::ICubismAllocator {
    void *Allocate(const Csm::csmSizeType size) override { return malloc(size); }
    void Deallocate(void *memory) override { free(memory); }
    void *AllocateAligned(const Csm::csmSizeType size, const Csm::csmUint32 alignment) override {
        void *memory = nullptr;
        // posix_memalign requires a power-of-two multiple of sizeof(void*).
        size_t effective = alignment < sizeof(void *) ? sizeof(void *) : alignment;
        if (posix_memalign(&memory, effective, size) != 0) {
            return nullptr;
        }
        return memory;
    }
    void DeallocateAligned(void *memory) override { free(memory); }
};

JoiAllocator gAllocator;
Csm::CubismFramework::Option gOption;
bool gStarted = false;

/// Reads a whole file into a buffer. Returns false rather than throwing so the
/// caller can report a typed error.
bool readFile(const std::string &path, std::vector<unsigned char> &out) {
    FILE *file = fopen(path.c_str(), "rb");
    if (file == nullptr) {
        return false;
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return false;
    }
    const long size = ftell(file);
    if (size < 0 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return false;
    }
    out.resize(static_cast<size_t>(size));
    const size_t read = size == 0 ? 0 : fread(out.data(), 1, static_cast<size_t>(size), file);
    fclose(file);
    return read == static_cast<size_t>(size);
}

/// Owns one loaded model. Kept in the .mm so no C++ type escapes the header.
class JoiModel : public Csm::CubismUserModel {
public:
    bool load(const std::string &directory, const std::string &model3) {
        std::vector<unsigned char> settingBytes;
        if (!readFile(directory + "/" + model3, settingBytes)) {
            return false;
        }
        _setting = new Csm::CubismModelSettingJson(
            settingBytes.data(), static_cast<Csm::csmSizeInt>(settingBytes.size()));
        if (_setting == nullptr) {
            return false;
        }

        const Csm::csmChar *mocName = _setting->GetModelFileName();
        if (mocName == nullptr || strlen(mocName) == 0) {
            return false;
        }
        std::vector<unsigned char> mocBytes;
        if (!readFile(directory + "/" + mocName, mocBytes)) {
            return false;
        }
        LoadModel(mocBytes.data(), static_cast<Csm::csmSizeInt>(mocBytes.size()));
        if (_model == nullptr) {
            return false;
        }

        _home = directory;
        loadExpressions();
        loadEffects();
        loadIdleMotions();
        // Every updater must be registered before this call; the scheduler runs
        // them in the order Cubism requires rather than the order we added them.
        _updateScheduler.SortUpdatableList();
        _model->SaveParameters();
        return true;
    }

    /// Mirrors the SDK sample's Update: motion drives parameters, the scheduler
    /// then applies eye blink, expression, breath, physics and pose.
    void advance(float seconds) {
        if (_model == nullptr) {
            return;
        }
        _motionUpdated = false;
        _model->LoadParameters();
        if (_motionManager == nullptr || _motionManager->IsFinished()) {
            startRandomIdleMotion();
        } else {
            _motionUpdated = _motionManager->UpdateMotion(_model, seconds);
        }
        _model->SaveParameters();
        _updateScheduler.OnLateUpdate(_model, seconds);
        applyLookAndLipSync();
        _model->Update();
    }

    /// Written every frame from real audio amplitude. Applied after the update
    /// scheduler so nothing else overwrites the mouth within the same frame.
    void setLipSync(float value) {
        _lipSyncValue = value < 0.0f ? 0.0f : (value > 1.0f ? 1.0f : value);
    }

    void setLookTarget(float x, float y) {
        _lookX = x < -1.0f ? -1.0f : (x > 1.0f ? 1.0f : x);
        _lookY = y < -1.0f ? -1.0f : (y > 1.0f ? 1.0f : y);
        _hasLookTarget = true;
    }

    bool startMotion(const std::string &group, Csm::csmInt32 index) {
        if (_setting == nullptr || _motionManager == nullptr) {
            return false;
        }
        const Csm::csmInt32 count = _setting->GetMotionCount(group.c_str());
        if (count <= 0 || index < 0 || index >= count) {
            return false;
        }
        Csm::CubismMotion *motion = loadMotion(group, index);
        if (motion == nullptr) {
            return false;
        }
        // Priority 2 beats the idle rotation started at priority 1, so a gesture
        // interrupts waiting rather than queueing behind it.
        _motionManager->StartMotionPriority(motion, false, 2);
        return true;
    }

    bool hitTest(const std::string &area, float x, float y) {
        if (_setting == nullptr) {
            return false;
        }
        const Csm::csmInt32 count = _setting->GetHitAreasCount();
        for (Csm::csmInt32 i = 0; i < count; ++i) {
            if (strcmp(_setting->GetHitAreaName(i), area.c_str()) == 0) {
                return IsHit(_setting->GetHitAreaId(i), x, y);
            }
        }
        return false;
    }

    Csm::csmInt32 idleMotionCount() const { return _idleMotionCount; }
    bool hasEyeBlink() const { return _eyeBlink != nullptr; }
    bool hasBreath() const { return _breath != nullptr; }
    bool hasPhysics() const { return _physics != nullptr; }
    bool hasPose() const { return _pose != nullptr; }
    Csm::csmInt32 expressionCount() const { return static_cast<Csm::csmInt32>(_expressions.GetSize()); }

private:
    /// Applied after the scheduler: lip sync is additive over whatever the motion
    /// wanted the mouth to do, and look-at is additive over breath's head sway,
    /// so neither fights the animation that produced the pose.
    void applyLookAndLipSync() {
        auto *ids = Csm::CubismFramework::GetIdManager();
        for (Csm::csmUint32 i = 0; i < _lipSyncIds.GetSize(); ++i) {
            _model->AddParameterValue(_lipSyncIds[i], _lipSyncValue, 0.8f);
        }
        if (!_hasLookTarget) {
            return;
        }
        _model->AddParameterValue(ids->GetId(Csm::DefaultParameterId::ParamAngleX), _lookX * 30.0f);
        _model->AddParameterValue(ids->GetId(Csm::DefaultParameterId::ParamAngleY), _lookY * 30.0f);
        _model->AddParameterValue(ids->GetId(Csm::DefaultParameterId::ParamAngleZ), _lookX * _lookY * -30.0f);
        _model->AddParameterValue(ids->GetId(Csm::DefaultParameterId::ParamBodyAngleX), _lookX * 10.0f);
        _model->AddParameterValue(ids->GetId(Csm::DefaultParameterId::ParamEyeBallX), _lookX);
        _model->AddParameterValue(ids->GetId(Csm::DefaultParameterId::ParamEyeBallY), _lookY);
    }

    /// Shared by idle rotation and explicit gestures.
    Csm::CubismMotion *loadMotion(const std::string &group, Csm::csmInt32 index) {
        const Csm::csmChar *file = _setting->GetMotionFileName(group.c_str(), index);
        if (file == nullptr || strlen(file) == 0) {
            return nullptr;
        }
        const std::string key = group + "_" + std::to_string(index);
        auto cached = _motions.find(key);
        if (cached != _motions.end()) {
            return cached->second;
        }
        std::vector<unsigned char> bytes;
        if (!readFile(_home + "/" + file, bytes)) {
            return nullptr;
        }
        auto *motion = static_cast<Csm::CubismMotion *>(
            LoadMotion(bytes.data(), static_cast<Csm::csmSizeInt>(bytes.size()), nullptr));
        if (motion == nullptr) {
            return nullptr;
        }
        // Effect ids let a motion cooperate with automatic blink and lip sync
        // instead of fighting them.
        motion->SetEffectIds(_eyeBlinkIds, _lipSyncIds);
        const Csm::csmFloat32 fade = _setting->GetMotionFadeInTimeValue(group.c_str(), index);
        if (fade >= 0.0f) { motion->SetFadeInTime(fade); }
        const Csm::csmFloat32 fadeOut = _setting->GetMotionFadeOutTimeValue(group.c_str(), index);
        if (fadeOut >= 0.0f) { motion->SetFadeOutTime(fadeOut); }
        _motions[key] = motion;
        return motion;
    }

    void loadExpressions() {
        const Csm::csmInt32 count = _setting->GetExpressionCount();
        for (Csm::csmInt32 index = 0; index < count; ++index) {
            const Csm::csmChar *file = _setting->GetExpressionFileName(index);
            if (file == nullptr || strlen(file) == 0) {
                continue;
            }
            std::vector<unsigned char> bytes;
            if (!readFile(_home + "/" + file, bytes)) {
                continue;
            }
            Csm::ACubismMotion *motion = LoadExpression(
                bytes.data(), static_cast<Csm::csmSizeInt>(bytes.size()),
                _setting->GetExpressionName(index));
            if (motion != nullptr) {
                _expressions.PushBack(motion);
            }
        }
        if (_expressionManager != nullptr) {
            _updateScheduler.AddUpdatableList(CSM_NEW Csm::CubismExpressionUpdater(*_expressionManager));
        }
    }

    void loadEffects() {
        const Csm::csmChar *physics = _setting->GetPhysicsFileName();
        if (physics != nullptr && strlen(physics) > 0) {
            std::vector<unsigned char> bytes;
            if (readFile(_home + "/" + physics, bytes)) {
                LoadPhysics(bytes.data(), static_cast<Csm::csmSizeInt>(bytes.size()));
            }
            if (_physics != nullptr) {
                _updateScheduler.AddUpdatableList(CSM_NEW Csm::CubismPhysicsUpdater(*_physics));
            }
        }

        const Csm::csmChar *pose = _setting->GetPoseFileName();
        if (pose != nullptr && strlen(pose) > 0) {
            std::vector<unsigned char> bytes;
            if (readFile(_home + "/" + pose, bytes)) {
                LoadPose(bytes.data(), static_cast<Csm::csmSizeInt>(bytes.size()));
            }
            if (_pose != nullptr) {
                _updateScheduler.AddUpdatableList(CSM_NEW Csm::CubismPoseUpdater(*_pose));
            }
        }

        if (_setting->GetEyeBlinkParameterCount() > 0) {
            _eyeBlink = Csm::CubismEyeBlink::Create(_setting);
            if (_eyeBlink != nullptr) {
                // The updater reads _motionUpdated so an explicit motion that
                // animates the eyes suppresses automatic blinking.
                _updateScheduler.AddUpdatableList(
                    CSM_NEW Csm::CubismEyeBlinkUpdater(_motionUpdated, *_eyeBlink));
            }
        }
        for (Csm::csmInt32 i = 0; i < _setting->GetEyeBlinkParameterCount(); ++i) {
            _eyeBlinkIds.PushBack(_setting->GetEyeBlinkParameterId(i));
        }
        for (Csm::csmInt32 i = 0; i < _setting->GetLipSyncParameterCount(); ++i) {
            _lipSyncIds.PushBack(_setting->GetLipSyncParameterId(i));
        }

        _breath = Csm::CubismBreath::Create();
        if (_breath != nullptr) {
            auto *ids = Csm::CubismFramework::GetIdManager();
            Csm::csmVector<Csm::CubismBreath::BreathParameterData> parameters;
            parameters.PushBack(Csm::CubismBreath::BreathParameterData(
                ids->GetId(Csm::DefaultParameterId::ParamAngleX), 0.0f, 15.0f, 6.5345f, 0.5f));
            parameters.PushBack(Csm::CubismBreath::BreathParameterData(
                ids->GetId(Csm::DefaultParameterId::ParamAngleY), 0.0f, 8.0f, 3.5345f, 0.5f));
            parameters.PushBack(Csm::CubismBreath::BreathParameterData(
                ids->GetId(Csm::DefaultParameterId::ParamAngleZ), 0.0f, 10.0f, 5.5345f, 0.5f));
            parameters.PushBack(Csm::CubismBreath::BreathParameterData(
                ids->GetId(Csm::DefaultParameterId::ParamBodyAngleX), 0.0f, 4.0f, 15.5345f, 0.5f));
            parameters.PushBack(Csm::CubismBreath::BreathParameterData(
                ids->GetId(Csm::DefaultParameterId::ParamBreath), 0.5f, 0.5f, 3.2345f, 0.5f));
            _breath->SetParameters(parameters);
            _updateScheduler.AddUpdatableList(CSM_NEW Csm::CubismBreathUpdater(*_breath));
        }
    }

    void loadIdleMotions() {
        _idleGroup = _setting->GetMotionGroupName(0) == nullptr ? "Idle" : "Idle";
        _idleMotionCount = _setting->GetMotionCount(_idleGroup.c_str());
        if (_idleMotionCount <= 0) {
            // Some models name the waiting group differently; fall back to the
            // first declared group so the character still moves.
            const Csm::csmChar *first = _setting->GetMotionGroupName(0);
            if (first != nullptr && strlen(first) > 0) {
                _idleGroup = first;
                _idleMotionCount = _setting->GetMotionCount(_idleGroup.c_str());
            }
        }
    }

    void startRandomIdleMotion() {
        if (_idleMotionCount <= 0 || _motionManager == nullptr) {
            return;
        }
        // Deterministic rotation rather than rand(): a repeatable idle sequence
        // is easier to inspect and cannot surprise a test.
        const Csm::csmInt32 index = _nextIdle % _idleMotionCount;
        _nextIdle = (_nextIdle + 1) % (_idleMotionCount == 0 ? 1 : _idleMotionCount);
        Csm::CubismMotion *motion = loadMotion(_idleGroup, index);
        if (motion != nullptr) {
            _motionManager->StartMotionPriority(motion, false, 1);
        }
    }

public:
    Csm::CubismModel *model() const { return _model; }

    Csm::csmInt32 textureCount() const {
        return _setting == nullptr ? 0 : _setting->GetTextureCount();
    }

    const Csm::csmChar *textureName(Csm::csmInt32 index) const {
        return _setting == nullptr ? nullptr : _setting->GetTextureFileName(index);
    }

    /// Exposes the renderer so the Objective-C layer can bind textures and draw
    /// without any Cubism type appearing in the public header.
    Csm::Rendering::CubismRenderer_Metal *metalRenderer() {
        return GetRenderer<Csm::Rendering::CubismRenderer_Metal>();
    }

    /// The mask buffer is sized from the model canvas, so clipping masks match
    /// the model's own resolution rather than the screen's.
    /// The clipping-mask buffer is sized from the drawable, matching the SDK's own
    /// Metal sample. Sizing it from the model canvas instead leaves masked parts
    /// drawn as opaque quads over the model.
    void createRenderer(Csm::csmUint32 width, Csm::csmUint32 height) {
        CreateRenderer(width, height);
    }

    void setMvp(float scaleX, float scaleY, float translateY) {
        Csm::CubismMatrix44 projection;
        projection.Scale(scaleX, scaleY);
        projection.TranslateY(translateY);
        auto *renderer = metalRenderer();
        if (renderer != nullptr) {
            renderer->SetMvpMatrix(&projection);
        }
    }

    ~JoiModel() override {
        for (auto &entry : _motions) {
            Csm::ACubismMotion::Delete(entry.second);
        }
        _motions.clear();
        for (Csm::csmUint32 i = 0; i < _expressions.GetSize(); ++i) {
            Csm::ACubismMotion::Delete(_expressions[i]);
        }
        _expressions.Clear();
        delete _setting;
        _setting = nullptr;
    }

private:
    Csm::ICubismModelSetting *_setting = nullptr;
    std::string _home;
    std::string _idleGroup = "Idle";
    Csm::csmInt32 _idleMotionCount = 0;
    Csm::csmInt32 _nextIdle = 0;
    Csm::csmBool _motionUpdated = false;
    float _lipSyncValue = 0.0f;
    float _lookX = 0.0f;
    float _lookY = 0.0f;
    bool _hasLookTarget = false;
    std::map<std::string, Csm::CubismMotion *> _motions;
    Csm::csmVector<Csm::ACubismMotion *> _expressions;
    Csm::csmVector<Csm::CubismIdHandle> _eyeBlinkIds;
    Csm::csmVector<Csm::CubismIdHandle> _lipSyncIds;
};

}  // namespace

@implementation JoiLive2DModelFacts

- (instancetype)initWithModel:(Csm::CubismModel *)model owner:(JoiModel *)owner {
    self = [super init];
    if (self != nil) {
        _canvasWidth = model->GetCanvasWidth();
        _canvasHeight = model->GetCanvasHeight();
        _pixelsPerUnit = model->GetPixelsPerUnit();
        _parameterCount = model->GetParameterCount();
        _partCount = model->GetPartCount();
        _drawableCount = model->GetDrawableCount();
        _idleMotionCount = owner->idleMotionCount();
        _expressionCount = owner->expressionCount();
        _hasEyeBlink = owner->hasEyeBlink() ? YES : NO;
        _hasBreath = owner->hasBreath() ? YES : NO;
        _hasPhysics = owner->hasPhysics() ? YES : NO;
        _hasPose = owner->hasPose() ? YES : NO;
    }
    return self;
}

@end

@implementation JoiLive2DModel {
    JoiModel *_model;
    BOOL _shutDown;
    NSString *_directory;
    NSMutableArray<id<MTLTexture>> *_textures;
}

+ (void)configureRenderDevice:(id<MTLDevice>)device {
    // Must precede model load: the renderer reads this when it is created.
    Csm::Rendering::CubismRenderer_Metal::SetConstantSettings(device);
}

+ (BOOL)startRuntime {
    if (gStarted) {
        return YES;
    }
    gOption.LogFunction = nullptr;
    gOption.LoggingLevel = Csm::CubismFramework::Option::LogLevel_Off;
    Csm::CubismFramework::StartUp(&gAllocator, &gOption);
    Csm::CubismFramework::Initialize();
    gStarted = Csm::CubismFramework::IsStarted();
    return gStarted ? YES : NO;
}

- (nullable instancetype)initWithModelDirectory:(NSString *)directory
                                  model3FileName:(NSString *)model3FileName
                                           error:(NSError **)error {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    if (![JoiLive2DModel startRuntime]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:JoiLive2DErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"runtime unavailable"}];
        }
        return nil;
    }

    _directory = [directory copy];
    _textures = [NSMutableArray array];
    _model = new JoiModel();
    if (!_model->load(directory.UTF8String, model3FileName.UTF8String)) {
        delete _model;
        _model = nullptr;
        if (error != NULL) {
            *error = [NSError errorWithDomain:JoiLive2DErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"model rejected"}];
        }
        return nil;
    }
    return self;
}

- (JoiLive2DModelFacts *)facts {
    if (_model == nullptr || _model->model() == nullptr) {
        return [[JoiLive2DModelFacts alloc] init];
    }
    return [[JoiLive2DModelFacts alloc] initWithModel:_model->model() owner:_model];
}

- (void)updateWithDelta:(NSTimeInterval)seconds {
    if (_model != nullptr) {
        _model->advance(static_cast<float>(seconds));
    }
}

- (BOOL)prepareRendererWithDevice:(id<MTLDevice>)device
                       maskWidth:(NSUInteger)maskWidth
                      maskHeight:(NSUInteger)maskHeight {
    if (_model == nullptr || _model->model() == nullptr || maskWidth == 0 || maskHeight == 0) {
        return NO;
    }
    _model->createRenderer(static_cast<Csm::csmUint32>(maskWidth),
                           static_cast<Csm::csmUint32>(maskHeight));
    auto *renderer = _model->metalRenderer();
    if (renderer == nullptr) {
        return NO;
    }

    MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:device];
    const Csm::csmInt32 count = _model->textureCount();
    for (Csm::csmInt32 index = 0; index < count; ++index) {
        const Csm::csmChar *name = _model->textureName(index);
        if (name == nullptr || strlen(name) == 0) {
            return NO;
        }
        NSString *path = [_directory stringByAppendingPathComponent:@(name)];
        NSError *error = nil;
        // Cubism's shaders sample textures as linear data, so sRGB conversion
        // must be off or every model renders washed out.
        id<MTLTexture> texture = [loader newTextureWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                            options:@{MTKTextureLoaderOptionSRGB: @NO}
                                                              error:&error];
        if (texture == nil) {
            return NO;
        }
        [_textures addObject:texture];
        renderer->BindTexture(static_cast<Csm::csmUint32>(index), texture);
    }
    // The SDK's own sample leaves this off unless PREMULTIPLIED_ALPHA_ENABLE is
    // defined. Forcing it on renders masked regions as opaque blocks.
    renderer->IsPremultipliedAlpha(false);
    return _textures.count == static_cast<NSUInteger>(count) && count > 0;
}

- (void)drawWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
         renderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor
                     viewport:(MTLViewport)viewport
                       scaleX:(float)scaleX
                       scaleY:(float)scaleY
                   translateY:(float)translateY {
    if (_model == nullptr) {
        return;
    }
    auto *renderer = _model->metalRenderer();
    if (renderer == nullptr) {
        return;
    }
    renderer->SetRenderViewport(viewport);
    _model->setMvp(scaleX, scaleY, translateY);
    renderer->StartFrame(commandBuffer, renderPassDescriptor);
    renderer->DrawModel();
}

- (void)setLipSyncValue:(float)value {
    if (_model != nullptr) {
        _model->setLipSync(value);
    }
}

- (void)setLookTargetX:(float)x y:(float)y {
    if (_model != nullptr) {
        _model->setLookTarget(x, y);
    }
}

- (BOOL)startMotionInGroup:(NSString *)group index:(NSInteger)index {
    if (_model == nullptr || group.length == 0) {
        return NO;
    }
    return _model->startMotion(group.UTF8String, static_cast<Csm::csmInt32>(index)) ? YES : NO;
}

- (BOOL)hitTestArea:(NSString *)area atX:(float)x y:(float)y {
    if (_model == nullptr || area.length == 0) {
        return NO;
    }
    return _model->hitTest(area.UTF8String, x, y) ? YES : NO;
}

- (void)shutdown {
    if (_shutDown) {
        return;
    }
    _shutDown = YES;
    [_textures removeAllObjects];
    delete _model;
    _model = nullptr;
}

- (void)dealloc {
    [self shutdown];
}

@end
