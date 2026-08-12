#import "JoiLive2DModel.h"

#import <CubismFramework.hpp>
#import <CubismDefaultParameterId.hpp>
#import <CubismModelSettingJson.hpp>
#import <Id/CubismIdManager.hpp>
#import <Model/CubismUserModel.hpp>
#import <Motion/CubismMotion.hpp>
#import <Physics/CubismPhysics.hpp>
#import <Utils/CubismString.hpp>

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

        // Physics and pose are optional; a model without them is valid.
        const Csm::csmChar *physics = _setting->GetPhysicsFileName();
        if (physics != nullptr && strlen(physics) > 0) {
            std::vector<unsigned char> bytes;
            if (readFile(directory + "/" + physics, bytes)) {
                LoadPhysics(bytes.data(), static_cast<Csm::csmSizeInt>(bytes.size()));
            }
        }
        const Csm::csmChar *pose = _setting->GetPoseFileName();
        if (pose != nullptr && strlen(pose) > 0) {
            std::vector<unsigned char> bytes;
            if (readFile(directory + "/" + pose, bytes)) {
                LoadPose(bytes.data(), static_cast<Csm::csmSizeInt>(bytes.size()));
            }
        }
        _model->SaveParameters();
        return true;
    }

    void advance(float seconds) {
        if (_model == nullptr) {
            return;
        }
        _model->LoadParameters();
        if (_motionManager != nullptr) {
            _motionManager->UpdateMotion(_model, seconds);
        }
        _model->SaveParameters();
        if (_physics != nullptr) {
            _physics->Evaluate(_model, seconds);
        }
        if (_pose != nullptr) {
            _pose->UpdateParameters(_model, seconds);
        }
        _model->Update();
    }

    Csm::CubismModel *model() const { return _model; }

    ~JoiModel() override {
        delete _setting;
        _setting = nullptr;
    }

private:
    Csm::ICubismModelSetting *_setting = nullptr;
};

}  // namespace

@implementation JoiLive2DModelFacts

- (instancetype)initWithModel:(Csm::CubismModel *)model {
    self = [super init];
    if (self != nil) {
        _canvasWidth = model->GetCanvasWidth();
        _canvasHeight = model->GetCanvasHeight();
        _pixelsPerUnit = model->GetPixelsPerUnit();
        _parameterCount = model->GetParameterCount();
        _partCount = model->GetPartCount();
        _drawableCount = model->GetDrawableCount();
    }
    return self;
}

@end

@implementation JoiLive2DModel {
    JoiModel *_model;
    BOOL _shutDown;
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
    return [[JoiLive2DModelFacts alloc] initWithModel:_model->model()];
}

- (void)updateWithDelta:(NSTimeInterval)seconds {
    if (_model != nullptr) {
        _model->advance(static_cast<float>(seconds));
    }
}

- (void)shutdown {
    if (_shutDown) {
        return;
    }
    _shutDown = YES;
    delete _model;
    _model = nullptr;
}

- (void)dealloc {
    [self shutdown];
}

@end
