// murmur-llm-bench: exercises murmur_llm.h exactly as the app will (load -> prefix_set -> N x generate)
// and prints one JSON object per measurement on stdout (human-readable notes go to stderr).
//
//   murmur-llm-bench -m model.gguf --prefix-file sys.txt --suffix-file user.txt
//                    [--device cpu|npu|gpu] [-t 4] [--modes ram,device,seqcp,none] [--reps 3]
//                    [--max-tokens 128] [--ctx 9216 (catalog nCtx)] [--batch 512] [--pp 512 --tg 64]
//                    [--backend-dir DIR] [--htp-dir DIR] [--power burst] [-v|-vv] [--print-output]
//                    [--no-mmap]             (CPU: read weights instead of mmap; NPU never mmaps)
//                    [--prefix-cache FILE]   (load prefix snapshot from FILE if it exists, else prefill and save it)
#include "murmur_llm.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

static std::string read_file(const std::string & p) {
    std::ifstream f(p, std::ios::binary);
    if (!f) { fprintf(stderr, "cannot read %s\n", p.c_str()); exit(2); }
    std::stringstream ss; ss << f.rdbuf();
    std::string s = ss.str();
    return s;
}

static std::string json_esc(const std::string & s) {
    std::string o;
    for (unsigned char c : s) {
        if (c == '"' || c == '\\') { o += '\\'; o += (char) c; }
        else if (c == '\n') o += "\\n";
        else if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); o += b; }
        else o += (char) c;
    }
    return o;
}

// kB value of `key` in a /proc file (Linux/Android), -1 if unavailable.
static long proc_kb(const char * path, const char * key) {
    std::ifstream f(path);
    std::string line;
    const size_t kl = strlen(key);
    while (std::getline(f, line)) {
        if (line.compare(0, kl, key) == 0) return atol(line.c_str() + kl);
    }
    return -1;
}

static int collect(void * user, const char * piece, int32_t len) {
    static_cast<std::string *>(user)->append(piece, (size_t) len);
    return 0;
}

static double median(std::vector<double> v) {
    if (v.empty()) return 0;
    std::sort(v.begin(), v.end());
    return v[v.size() / 2];
}

int main(int argc, char ** argv) {
    std::string model, prefix_file, suffix_file, backend_dir, htp_dir, power, prefix_cache, modes = "ram,seqcp,none";
    std::string device = "cpu";
    int threads = 4, reps = 3, max_tokens = 128, n_ctx = 9216, n_batch = 512, pp = 0, tg = 0, verbose = 0;
    bool print_output = false;
    int use_mmap = 1;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string { if (i + 1 >= argc) { fprintf(stderr, "missing value for %s\n", a.c_str()); exit(2); } return argv[++i]; };
        if (a == "-m") model = next();
        else if (a == "--prefix-file") prefix_file = next();
        else if (a == "--suffix-file") suffix_file = next();
        else if (a == "--device") device = next();
        else if (a == "-t") threads = atoi(next().c_str());
        else if (a == "--modes") modes = next();
        else if (a == "--reps") reps = atoi(next().c_str());
        else if (a == "--max-tokens") max_tokens = atoi(next().c_str());
        else if (a == "--ctx") n_ctx = atoi(next().c_str());
        else if (a == "--batch") n_batch = atoi(next().c_str());
        else if (a == "--pp") pp = atoi(next().c_str());
        else if (a == "--tg") tg = atoi(next().c_str());
        else if (a == "--backend-dir") backend_dir = next();
        else if (a == "--htp-dir") htp_dir = next();
        else if (a == "--power") power = next();
        else if (a == "-v") verbose = 1;
        else if (a == "-vv") verbose = 2;
        else if (a == "--print-output") print_output = true;
        else if (a == "--prefix-cache") prefix_cache = next();
        else if (a == "--no-mmap") use_mmap = 0;
        else { fprintf(stderr, "unknown arg %s\n", a.c_str()); return 2; }
    }
    if (model.empty()) { fprintf(stderr, "usage: see header of murmur_llm_bench.cpp\n"); return 2; }

    mllm_init_params ip {};
    ip.backend_dir    = backend_dir.empty() ? nullptr : backend_dir.c_str();
    ip.htp_lib_dir    = htp_dir.empty() ? nullptr : htp_dir.c_str();
    ip.hex_power_mode = power.empty() ? nullptr : power.c_str();
    ip.verbose        = verbose;
    if (mllm_global_init(&ip) != MLLM_OK) { printf("{\"event\":\"error\",\"what\":\"no backends\"}\n"); return 1; }
    char devs[2048];
    mllm_devices(devs, sizeof devs);
    printf("{\"event\":\"devices\",\"list\":\"%s\"}\n", json_esc(devs).c_str());

    const mllm_device dev = device == "npu" ? MLLM_DEV_NPU : device == "gpu" ? MLLM_DEV_GPU : MLLM_DEV_CPU;
    const std::string prefix = prefix_file.empty() ? "" : read_file(prefix_file);
    const std::string suffix = suffix_file.empty() ? "" : read_file(suffix_file);

    std::vector<std::string> mode_list;
    { std::stringstream ss(modes); std::string m; while (std::getline(ss, m, ',')) if (!m.empty()) mode_list.push_back(m); }
    if (suffix.empty()) mode_list.clear();

    std::string reference_output;
    bool first_mode = true;
    int exit_code = 0;
    auto run_one = [&](const std::string & mode_name, mllm_prefix_mode mode, bool do_bench) -> int {
        mllm_load_params lp {};
        lp.model_path = model.c_str();
        lp.device = dev; lp.n_ctx = n_ctx; lp.n_batch = n_batch; lp.n_threads = threads; lp.n_threads_batch = threads;
        lp.use_mmap = use_mmap; lp.prefix_mode = mode;
        mllm_engine * e = nullptr;
        mllm_load_info li {};
        const long avail0 = proc_kb("/proc/meminfo", "MemAvailable:");
        int rc = mllm_load(&lp, &e, &li);
        if (rc != MLLM_OK) { printf("{\"event\":\"error\",\"what\":\"load\",\"rc\":%d}\n", rc); return rc; }
        // RSS misses DSP-mapped rpcmem/dma-buf on some kernels, so also report the system-wide MemAvailable drop.
        printf("{\"event\":\"mem_after_load\",\"mode\":\"%s\",\"rss_kb\":%ld,\"hwm_kb\":%ld,\"memavailable_drop_kb\":%ld}\n",
               mode_name.c_str(), proc_kb("/proc/self/status", "VmRSS:"), proc_kb("/proc/self/status", "VmHWM:"),
               avail0 >= 0 ? avail0 - proc_kb("/proc/meminfo", "MemAvailable:") : -1);
        printf("{\"event\":\"load\",\"mode\":\"%s\",\"device\":\"%s\",\"arch\":\"%s\",\"threads\":%d,\"load_ms\":%.1f,\"ctx_ms\":%.1f,\"n_layers\":%d}\n",
               mode_name.c_str(), li.device_name, li.arch, threads, li.load_ms, li.ctx_ms, li.n_layers);
        fflush(stdout);
        if (!suffix.empty()) {
            mllm_prefix_info pi {};
            if (!prefix.empty()) {
                // --prefix-cache FILE: load the snapshot from disk if present (cold-start path), else prefill + save it
                FILE * pc = prefix_cache.empty() ? nullptr : fopen(prefix_cache.c_str(), "rb");
                if (pc) {
                    fclose(pc);
                    rc = mllm_prefix_load(e, prefix_cache.c_str(), prefix.c_str(), &pi);
                    printf("{\"event\":\"prefix_load\",\"mode\":\"%s\",\"rc\":%d,\"n_tokens\":%d,\"load_ms\":%.1f}\n", mode_name.c_str(), rc, pi.n_tokens, pi.prefill_ms);
                } else {
                    rc = mllm_prefix_set(e, prefix.c_str(), &pi);
                    if (rc == MLLM_OK && !prefix_cache.empty()) {
                        const auto t0 = std::chrono::steady_clock::now();
                        const int src = mllm_prefix_save(e, prefix_cache.c_str());
                        printf("{\"event\":\"prefix_save\",\"mode\":\"%s\",\"rc\":%d,\"save_ms\":%.1f}\n", mode_name.c_str(), src,
                               std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count());
                    }
                }
                if (rc != MLLM_OK) { printf("{\"event\":\"error\",\"what\":\"prefix_set\",\"rc\":%d,\"msg\":\"%s\"}\n", rc, json_esc(mllm_last_error(e)).c_str()); mllm_unload(e); return rc; }
            }
            printf("{\"event\":\"prefix\",\"mode\":\"%s\",\"n_tokens\":%d,\"prefill_ms\":%.1f,\"snapshot_ms\":%.2f,\"snapshot_bytes\":%zu}\n",
                   mode_name.c_str(), pi.n_tokens, pi.prefill_ms, pi.snapshot_ms, pi.snapshot_bytes);
            mllm_gen_params gp {};
            gp.max_tokens = max_tokens; gp.temperature = 0.f; gp.repeat_penalty = 1.0f;
            std::vector<double> ttft, restore, prefill, dec_tps;
            std::string out0;
            mllm_gen_stats st {};
            for (int r = 0; r < reps; ++r) {
                std::string out;
                rc = mllm_generate(e, suffix.c_str(), &gp, collect, &out, &st);
                if (rc != MLLM_OK) { printf("{\"event\":\"error\",\"what\":\"generate\",\"rc\":%d,\"msg\":\"%s\"}\n", rc, json_esc(mllm_last_error(e)).c_str()); break; }
                if (r == 0) out0 = out;
                else if (out != out0) printf("{\"event\":\"warning\",\"what\":\"non-deterministic output across reps\",\"mode\":\"%s\"}\n", mode_name.c_str());
                ttft.push_back(st.ttft_ms); restore.push_back(st.restore_ms); prefill.push_back(st.prefill_ms);
                if (st.n_gen > 1 && st.decode_ms > 0) dec_tps.push_back(1000.0 * (st.n_gen - 1) / st.decode_ms);
                printf("{\"event\":\"generate\",\"mode\":\"%s\",\"rep\":%d,\"n_prompt\":%d,\"n_gen\":%d,\"restore_ms\":%.2f,\"prefill_ms\":%.1f,\"ttft_ms\":%.1f,\"decode_ms\":%.1f,\"total_ms\":%.1f,\"stop\":%d}\n",
                       mode_name.c_str(), r, st.n_prompt, st.n_gen, st.restore_ms, st.prefill_ms, st.ttft_ms, st.decode_ms, st.total_ms, st.stop_reason);
                fflush(stdout);
            }
            const bool same = first_mode || out0 == reference_output;
            if (first_mode) { reference_output = out0; first_mode = false; }
            printf("{\"event\":\"summary\",\"mode\":\"%s\",\"device\":\"%s\",\"threads\":%d,\"prefix_tokens\":%d,\"suffix_tokens\":%d,\"ttft_ms_median\":%.1f,\"restore_ms_median\":%.2f,\"suffix_prefill_ms_median\":%.1f,\"decode_tps_median\":%.2f,\"n_gen\":%d,\"output_matches_first_mode\":%s,\"output_head\":\"%s\"}\n",
                   mode_name.c_str(), li.device_name, threads, pi.n_tokens, st.n_prompt, median(ttft), median(restore), median(prefill), median(dec_tps), st.n_gen,
                   same ? "true" : "false", json_esc(out0.substr(0, 160)).c_str());
            if (!same) exit_code = 3;
            if (print_output) fprintf(stderr, "---- output (%s) ----\n%s\n-------------\n", mode_name.c_str(), out0.c_str());
        }
        if (do_bench && pp > 0 && tg > 0) {
            mllm_bench_result br {};
            rc = mllm_bench(e, pp, tg, reps, &br);
            if (rc == MLLM_OK)
                printf("{\"event\":\"bench\",\"device\":\"%s\",\"threads\":%d,\"pp\":%d,\"tg\":%d,\"pp_tps\":%.1f,\"tg_tps\":%.2f}\n",
                       li.device_name, threads, pp, tg, br.pp_tps, br.tg_tps);
            else printf("{\"event\":\"error\",\"what\":\"bench\",\"rc\":%d}\n", rc);
        }
        printf("{\"event\":\"mem_end\",\"mode\":\"%s\",\"rss_kb\":%ld,\"hwm_kb\":%ld,\"memavailable_drop_kb\":%ld}\n",
               mode_name.c_str(), proc_kb("/proc/self/status", "VmRSS:"), proc_kb("/proc/self/status", "VmHWM:"),
               avail0 >= 0 ? avail0 - proc_kb("/proc/meminfo", "MemAvailable:") : -1);
        fflush(stdout);
        mllm_unload(e);
        return MLLM_OK;
    };

    bool benched = false;
    for (const auto & m : mode_list) {
        const mllm_prefix_mode mode = m == "ram" ? MLLM_PREFIX_RAM : m == "device" ? MLLM_PREFIX_DEVICE : m == "seqcp" ? MLLM_PREFIX_SEQCP : MLLM_PREFIX_NONE;
        run_one(m, mode, !benched);
        benched = true;
    }
    if (!benched && pp > 0) run_one("bench", MLLM_PREFIX_NONE, true);
    return exit_code;
}
