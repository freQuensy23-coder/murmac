// murmur_llm.h - C ABI between the app's JNI shim and llama.cpp (pinned in native/llama/versions.env).
//
// One engine = one model + one llama_context, owned by exactly one worker thread in the `:llm`
// process. All calls except mllm_cancel() must come from that thread. mllm_cancel() may be called
// from any thread (it only flips an atomic that llama.cpp's abort callback and the decode loop poll).
// The flag stays set until mllm_cancel_clear(): the owner clears it on the engine thread before each
// request, so a cancel that arrives while the request is still queued is never lost.
//
// Lifecycle used by the app (see docs/research/verify/llm-npu.md section "JNI surface"):
//   mllm_global_init()            once per process, before anything else (sets GGML_HEXAGON_* env,
//                                 loads backend .so files). Process-wide, cannot be undone.
//   mllm_load()                   bubble tap: read GGUF, repack weights for the chosen device.
//   mllm_prefix_set()             right after load: prefill the fixed system prefix, snapshot it.
//   mllm_generate()               per dictation: restore prefix snapshot, prefill suffix, stream.
//   mllm_unload()                 idle timeout; the :llm process is then killed to release DSP maps.
#ifndef MURMUR_LLM_H
#define MURMUR_LLM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MLLM_OK              0
#define MLLM_E_ARG          -1   // bad argument / wrong state
#define MLLM_E_LOAD         -2   // model file unreadable or unsupported architecture
#define MLLM_E_DEVICE       -3   // requested device not available (e.g. no HTP0 registered)
#define MLLM_E_CTX          -4   // context creation failed (OOM, n_ctx too big)
#define MLLM_E_DECODE       -5   // llama_process failed
#define MLLM_E_CANCELLED    -6   // mllm_cancel() was observed
#define MLLM_E_STATE        -7   // prefix snapshot missing or could not be restored
#define MLLM_E_OVERFLOW     -8   // prompt + max_tokens exceeds n_ctx (last-line guard: the app checks the room
                                 // with mllm_tokenize_count first and clamps max_tokens, so it never sees this)
#define MLLM_E_NOMEM        -9   // mllm_load: host memory refused (a CPU buffer allocation or std::bad_alloc during the
                                 // model or context load). Device memory (rpcmem, VTCM, OpenCL) stays E_LOAD / E_CTX.

typedef enum {
    MLLM_DEV_CPU = 0,            // ggml-cpu only
    MLLM_DEV_NPU = 1,            // Hexagon HTP0 (libggml-hexagon + libggml-htp-vNN on the cDSP)
    MLLM_DEV_GPU = 2,            // Adreno via ggml-opencl
} mllm_device;

typedef enum {
    MLLM_PREFIX_RAM    = 0,      // llama_state_seq_get_data -> heap copy -> llama_state_seq_set_data
    MLLM_PREFIX_DEVICE = 1,      // same with LLAMA_STATE_SEQ_FLAGS_ON_DEVICE (copy stays in backend buffers)
    MLLM_PREFIX_SEQCP  = 2,      // keep prefix in seq 0, llama_memory_seq_cp(0 -> 1) per request
    MLLM_PREFIX_NONE   = 3,      // no cache: re-prefill the whole prompt (baseline)
} mllm_prefix_mode;

typedef struct {
    const char * backend_dir;    // dir holding libggml-*.so to dlopen (Android: nativeLibraryDir). NULL = scan default paths
    const char * htp_lib_dir;    // on-disk dir holding libggml-htp-v*.so (sets GGML_HEXAGON_LIBHTP_DIR). NULL = next to libggml-hexagon.so
    const char * hex_power_mode; // GGML_HEXAGON_POWER_MODE: "burst" (default), "sustained_high_performance", "balanced", ...
    int          verbose;        // 0 quiet, 1 info, 2 + GGML_HEXAGON_VERBOSE op placement dump
} mllm_init_params;

typedef enum {
    MLLM_KV_F16  = 0,            // default (HTP flash attention accepts F16 and Q8_0 K/V)
    MLLM_KV_Q8_0 = 1,
} mllm_kv_type;

typedef struct {
    const char * model_path;     // GGUF on local storage
    mllm_device  device;
    int32_t      n_ctx;          // required (catalog LlmTraits.nCtx, e.g. 9216); <= 0 -> MLLM_E_ARG
    int32_t      n_batch;        // prefill chunk; 0 -> 512
    int32_t      n_threads;      // CPU threads for decode; 0 -> 4
    int32_t      n_threads_batch;// CPU threads for prefill; 0 -> n_threads
    int32_t      use_mmap;       // CPU only (Hexagon backend reports mmap_support = false)
    mllm_prefix_mode prefix_mode;
    mllm_kv_type kv_type;        // K and V cache type
} mllm_load_params;

typedef struct {
    double  load_ms;             // model load incl. weight repack/upload
    double  ctx_ms;              // context + compute-buffer creation
    int32_t n_layers;            // model layers
    int32_t n_vocab;
    char    arch[32];            // GGUF general.architecture
    char    device_name[64];     // e.g. "HTP0", "GPUOpenCL", "CPU"
} mllm_load_info;

typedef struct {
    int32_t n_tokens;            // tokens prefilled
    double  prefill_ms;
    double  snapshot_ms;         // state capture after prefill
    size_t  snapshot_bytes;      // 0 for MLLM_PREFIX_DEVICE / SEQCP
} mllm_prefix_info;

typedef struct {
    int32_t      max_tokens;     // hard cap on generated tokens
    float        temperature;    // <= 0 -> greedy
    int32_t      top_k;
    float        top_p;
    float        repeat_penalty; // 1.0 = off; LFM guidance: 1.05
    uint32_t     seed;
    const char * const * stop;   // extra stop strings (EOG tokens always stop)
    int32_t      n_stop;
} mllm_gen_params;

typedef struct {
    int32_t n_prompt;            // suffix tokens prefilled in this call
    int32_t n_gen;               // tokens generated
    double  restore_ms;          // prefix restore
    double  prefill_ms;          // suffix prefill
    double  ttft_ms;             // call start -> first token piece delivered
    double  decode_ms;           // first token -> last token
    double  total_ms;
    int32_t stop_reason;         // 0 eog, 1 max_tokens, 2 stop string, 3 cancelled, 4 callback stop
} mllm_gen_stats;

// Streaming callback: UTF-8 bytes of the next piece (never splits a code point across calls).
// Return non-zero to stop generation. Runs on the engine thread; keep it short (post to Kotlin).
typedef int (*mllm_token_cb)(void * user, const char * piece, int32_t len);

int          mllm_global_init(const mllm_init_params * p);
// "llama.cpp <tag> <commit12> ggml-hexagon <variant>" (compile-time; ProcessProbe fact native.build, ADR-060).
const char * mllm_build_info(void);
// What the backend loader picked, as "cpu_backend=<file>;htp_arch=<vNN>;" (only keys that are known).
// Captured from ggml's log during mllm_global_init. Returns length.
int32_t      mllm_runtime_info(char * buf, int32_t buf_len);
// Lists registered devices as "name|description|type;..." for the hub UI / probe. Returns length.
int32_t      mllm_devices(char * buf, int32_t buf_len);

typedef struct mllm_engine mllm_engine;

int          mllm_load(const mllm_load_params * p, mllm_engine ** out, mllm_load_info * info);
// Prefill `prefix` (raw text, special tokens parsed, no BOS added: the rendered prompt carries it)
// and snapshot the state. Replaces any previous prefix.
int          mllm_prefix_set(mllm_engine * e, const char * prefix, mllm_prefix_info * info);
// Persistence across process restarts. RAM mode: the snapshot itself plus the prefix text ("MLLMST02" file; loading
// maps it read-only, keeps the mapping as the snapshot and restores from it; info->prefill_ms = map + check + restore).
// A loaded state file must only be replaced by rename or deleted, never truncated in place. Other modes:
// llama_state_seq_save_file / _load_file. mllm_prefix_load restores only the exact `prefix` (the text given to
// mllm_prefix_set): a missing, truncated, foreign or mismatching file, or one that holds another prefix, is
// MLLM_E_STATE and leaves no prefix set.
int          mllm_prefix_save(mllm_engine * e, const char * path);
int          mllm_prefix_load(mllm_engine * e, const char * path, const char * prefix, mllm_prefix_info * info);
// Generate a continuation of prefix + suffix. If no prefix is set, `suffix` is the whole prompt.
// Cancelled (also during restore/prefill): returns MLLM_E_CANCELLED with *st filled and st->stop_reason = 3.
int          mllm_generate(mllm_engine * e, const char * suffix, const mllm_gen_params * gp,
                           mllm_token_cb cb, void * user, mllm_gen_stats * st);
void         mllm_cancel(mllm_engine * e);      // any thread
void         mllm_cancel_clear(mllm_engine * e); // engine thread, before a request
int32_t      mllm_tokenize_count(mllm_engine * e, const char * text);
const char * mllm_last_error(const mllm_engine * e);
// ggml device the engine runs on ("CPU", "HTP0", "GPUOpenCL"); same as mllm_load_info.device_name.
const char * mllm_device_name(const mllm_engine * e);
void         mllm_unload(mllm_engine * e);

// Synthetic benchmark for the hub's Benchmark button: pp = prefill of n_prompt random tokens,
// tg = n_gen single-token decodes, median of `reps` (after one warm-up). mllm_cancel() stops it in either phase
// (MLLM_E_CANCELLED). Clears the context memory; the prefix snapshot stays valid (the next generate restores it).
typedef struct {
    double pp_tps, tg_tps;       // tokens per second (median)
    double pp_ms, tg_ms;         // median wall time of one rep
} mllm_bench_result;
int          mllm_bench(mllm_engine * e, int32_t n_prompt, int32_t n_gen, int32_t reps, mllm_bench_result * r);

#ifdef __cplusplus
}
#endif
#endif // MURMUR_LLM_H
