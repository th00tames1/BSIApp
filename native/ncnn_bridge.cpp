#ifdef __APPLE__
#include <ncnn/ncnn/command.h>
#include <ncnn/ncnn/gpu.h>
#include <ncnn/ncnn/net.h>
#else
#include <command.h>
#include <gpu.h>
#include <net.h>
#endif

#ifdef __ANDROID__
#include <android/log.h>
#endif

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <memory>
#include <mutex>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr int inputSize = 640;
constexpr int candidateCount = 300;
constexpr int anchorCount = 8400;
constexpr int maskChannels = 32;
constexpr int prototypeSize = 160;

enum class Model { stem, pole, rescue };

std::mutex inferenceMutex;
bool gpuFailed = false;

int findGpu() {
    static const int device = [] {
        if (ncnn::create_gpu_instance() != 0 || ncnn::get_gpu_count() == 0) return -1;
        const int index = ncnn::get_default_gpu_index();
        if (index < 0 || ncnn::get_gpu_info(index).type() == 3) return -1;
        return index;
    }();
    return device;
}

void check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

void report(const char* message, const std::exception& error) {
#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_WARN, "BsiInference", "%s: %s", message, error.what());
#else
    std::fprintf(stderr, "BSI ncnn %s: %s\n", message, error.what());
#endif
}

// Match the trained YOLO26 heads' two-stage TopK after extracting their raw scores.
void rankDetections(const ncnn::Mat& head, int masks, float* output) {
    const int classes = head.w - 4 - masks;
    check(head.dims == 2 && head.h == anchorCount && classes == 2, "unexpected YOLO26 head");

    for (int row = 0; row < head.h; ++row) {
        const float* values = head.row(row);
        check(std::all_of(values, values + head.w, [](float value) { return std::isfinite(value); }),
              "non-finite YOLO26 output");
    }

    std::array<int, anchorCount> anchors;
    std::array<float, anchorCount> best;
    std::iota(anchors.begin(), anchors.end(), 0);
    for (int i = 0; i < anchorCount; ++i) {
        const float* row = head.row(i);
        best[i] = std::max(row[4], row[5]);
    }
    std::partial_sort(anchors.begin(), anchors.begin() + candidateCount, anchors.end(),
                      [&](int a, int b) { return best[a] == best[b] ? a < b : best[a] > best[b]; });

    std::array<int, candidateCount * 2> pairs;
    std::iota(pairs.begin(), pairs.end(), 0);
    const auto score = [&](int pair) { return head.row(anchors[pair / classes])[4 + pair % classes]; };
    std::partial_sort(pairs.begin(), pairs.begin() + candidateCount, pairs.end(), [&](int a, int b) {
        const float x = score(a);
        const float y = score(b);
        return x == y ? a < b : x > y;
    });

    for (int i = 0; i < candidateCount; ++i) {
        const int pair = pairs[i];
        const float* row = head.row(anchors[pair / classes]);
        float* record = output + i * (6 + masks);
        std::copy_n(row, 4, record);
        record[4] = score(pair);
        record[5] = static_cast<float>(pair % classes);
        std::copy_n(row + 4 + classes, masks, record + 6);
    }
}

ncnn::Mat unpack(const ncnn::Mat& packed) {
    ncnn::Mat result;
    ncnn::convert_packing(packed, result, 1);
    check(!result.empty() && result.elemsize == sizeof(float), "expected an FP32 output");
    return result;
}

class Network {
public:
    explicit Network(int gpu) : gpu_(gpu) {
        auto& options = net_.opt;
        options.num_threads = 4;
        options.use_vulkan_compute = gpu >= 0;
        options.use_fp16_packed = false;
        options.use_fp16_storage = false;
        options.use_fp16_uniform = false;
        options.use_fp16_arithmetic = false;
        options.use_bf16_packed = false;
        options.use_bf16_storage = false;
        options.use_int8_inference = false;

        if (gpu >= 0) {
            net_.set_vulkan_device(gpu);
            auto* device = net_.vulkan_device();
            check(device && device->is_valid(), "Vulkan device unavailable");
            blob_ = device->acquire_blob_allocator();
            staging_ = device->acquire_staging_allocator();
            options.blob_vkallocator = blob_;
            options.workspace_vkallocator = blob_;
            options.staging_vkallocator = staging_;
        }
    }

    ~Network() {
        auto* device = net_.vulkan_device();
        net_.clear();
        if (gpu_ >= 0 && device) {
            if (blob_) device->reclaim_blob_allocator(blob_);
            if (staging_) device->reclaim_staging_allocator(staging_);
        }
    }

    void load(const std::string& base) {
        check(net_.load_param((base + ".param").c_str()) == 0, "could not read model parameters");
        check(net_.load_model((base + ".bin").c_str()) == 0, "could not read model weights");
    }

    void run(Model model, float* input, float* det, float* proto) {
        const int outputs = model == Model::pole ? 1 : 2;
        ncnn::Mat tensor(inputSize, inputSize, 3, input);
        std::array<ncnn::Mat, 2> host;
        auto extractor = net_.create_extractor();
        if (gpu_ >= 0) {
            ncnn::VkMat deviceInput;
            std::array<ncnn::VkMat, 2> deviceOutput;
            ncnn::VkCompute commands(net_.vulkan_device());
            commands.record_upload(tensor, deviceInput, net_.opt);
            check(extractor.input("in0", deviceInput) == 0, "Vulkan input failed");
            for (int i = 0; i < outputs; ++i) {
                check(extractor.extract(i ? "out1" : "out0", deviceOutput[i], commands) == 0
                          && !deviceOutput[i].empty(), "Vulkan inference failed");
            }
            for (int i = 0; i < outputs; ++i) {
                commands.record_download(deviceOutput[i], host[i], net_.opt);
            }
            check(commands.submit_and_wait() == 0, "Vulkan queue failed");
        } else {
            check(extractor.input("in0", tensor) == 0, "CPU input failed");
            for (int i = 0; i < outputs; ++i) {
                check(extractor.extract(i ? "out1" : "out0", host[i]) == 0, "CPU inference failed");
            }
        }

        const ncnn::Mat head = unpack(host[0]);
        if (model == Model::rescue) {
            check(head.dims == 2 && head.h == 38 && head.w == anchorCount, "unexpected rescue head");
            for (int i = 0; i < head.h; ++i) {
                const float* values = head.row(i);
                check(std::all_of(values, values + head.w, [](float value) { return std::isfinite(value); }),
                      "non-finite rescue output");
                std::copy_n(values, head.w, det + i * head.w);
            }
        } else {
            rankDetections(head, model == Model::stem ? maskChannels : 0, det);
        }

        if (outputs == 2) {
            const ncnn::Mat masks = unpack(host[1]);
            check(masks.dims == 3 && masks.c == maskChannels && masks.h == prototypeSize
                      && masks.w == prototypeSize, "unexpected mask prototypes");
            constexpr int area = prototypeSize * prototypeSize;
            for (int i = 0; i < masks.c; ++i) {
                const float* values = masks.channel(i);
                check(std::all_of(values, values + area, [](float value) { return std::isfinite(value); }),
                      "non-finite mask output");
                std::copy_n(values, area, proto + i * area);
            }
        }
    }

    bool isGpu() const { return gpu_ >= 0; }

private:
    ncnn::Net net_;
    int gpu_;
    ncnn::VkAllocator* blob_ = nullptr;
    ncnn::VkAllocator* staging_ = nullptr;
};

struct Session {
    Session(std::string base, Model model) : base(std::move(base)), model(model) {}

    void load(int gpu) {
        auto next = std::make_unique<Network>(gpu);
        next->load(base);
        network = std::move(next);
    }

    std::string base;
    Model model;
    std::unique_ptr<Network> network;
};
}  // namespace

#define BSI_EXPORT extern "C" __attribute__((used, visibility("default")))

BSI_EXPORT void* bsi_ncnn_open(const char* base, int model) {
    std::lock_guard<std::mutex> guard(inferenceMutex);
    try {
        check(base && model >= 0 && model <= 2, "invalid model");
        auto session = std::make_unique<Session>(base, static_cast<Model>(model));
        const int gpu = gpuFailed ? -1 : findGpu();
        if (gpu >= 0) {
            try {
                session->load(gpu);
            } catch (const std::exception& error) {
                gpuFailed = true;
                report("GPU model load failed, using CPU", error);
            }
        }
        if (!session->network) session->load(-1);
        return session.release();
    } catch (const std::exception& error) {
        report("model load failed", error);
        return nullptr;
    }
}

// Returns 1 for Vulkan, 0 for CPU, and -1 if neither path can produce an output.
BSI_EXPORT int bsi_ncnn_run(void* pointer, float* input, float* det, float* proto) {
    std::lock_guard<std::mutex> guard(inferenceMutex);
    try {
        check(pointer && input && det, "invalid inference buffers");
        auto& session = *static_cast<Session*>(pointer);
        check(session.model == Model::pole || proto, "missing prototype buffer");
        if (session.network && session.network->isGpu()) {
            if (!gpuFailed) {
                try {
                    session.network->run(session.model, input, det, proto);
                    return 1;
                } catch (const std::exception& error) {
                    gpuFailed = true;
                    report("GPU inference failed, retrying on CPU", error);
                }
            }
            session.network.reset();
        }
        if (!session.network) session.load(-1);
        session.network->run(session.model, input, det, proto);
        return 0;
    } catch (const std::exception& error) {
        report("inference failed", error);
        return -1;
    }
}

BSI_EXPORT void bsi_ncnn_close(void* pointer) {
    std::lock_guard<std::mutex> guard(inferenceMutex);
    delete static_cast<Session*>(pointer);
}
