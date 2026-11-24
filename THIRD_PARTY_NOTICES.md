# Third-party notices

Murmur ships these components inside the APKs. Model weights are not bundled: the app downloads
them from their own hosts, under their own licences.

## Native engines (both public and NPU APKs)

| Component | Version | Licence | Source |
| --- | --- | --- | --- |
| llama.cpp / ggml | b12520 (`ff6b8d1`) | MIT | https://github.com/ggml-org/llama.cpp |
| sherpa-onnx | pinned in `native/sherpa/build-android.sh` | Apache-2.0 | https://github.com/k2-fsa/sherpa-onnx |
| ONNX Runtime | 1.32.0 | MIT | https://github.com/microsoft/onnxruntime |

`libmurmur_llm.so`, `libmurmur_llm_jni.so`, `libmurmur-qnn-probe.so`, `libggml-hexagon.so` and
`libggml-htp-v79.so` are built from this repository's sources and the engines above.

## NPU APKs only (`*-npu-*`)

| Component | Version | Licence | Source |
| --- | --- | --- | --- |
| QNN runtime: `libQnnHtp.so`, `libQnnSystem.so`, `libQnnHtpV79Stub.so`, `libQnnHtpV79Skel.so` | 2.52.0 (`com.qualcomm.qti:qnn-runtime`) | Qualcomm AI Hub Model License — https://softwarecenter.qualcomm.com/api/download/software/licenses/ai_model_hub/v1/LICENSE.pdf | Maven Central |
| ONNX Runtime QNN plugin EP: `libonnxruntime_providers_qnn.so` | 2.7.0 (`com.qualcomm.qti:onnxruntime-android-qnn`) | MIT | Maven Central |

The Qualcomm AI Hub Model License grants the right to "distribute and sublicense the Software
solely in object code format and as incorporated in Your software application" and forbids
standalone distribution. Murmur therefore ships these libraries only inside its APKs: no
individual Qualcomm library is offered as a separate download, and the libraries are passed
through byte-for-byte as published in the Maven artifacts (see `docs/DECISIONS.md`, ADR-048).

`libggml-hexagon.so` and `libggml-htp-v79.so` are compiled from llama.cpp's MIT sources; the
Qualcomm Hexagon SDK is used only as a compiler toolbox and contributes no binary to the APK
(`llvm-readelf -d` lists only `libc`, `libgcc`, `liblog`, `libdl`, `libm`, `libc++_shared`).

## App runtime

Kotlin standard library and AndroidX (Apache-2.0), Room, DataStore, Compose (Apache-2.0),
kotlinx-coroutines and kotlinx-serialization (Apache-2.0), Accompanist/Compose multiplatform
components under their respective Apache-2.0 / MIT terms.

## Fonts

Onest (SIL Open Font License 1.1) and JetBrains Mono (SIL Open Font License 1.1). Full texts ship
inside the APK at `assets/licenses/Onest-OFL.txt` and `assets/licenses/JetBrainsMono-OFL.txt`.

## Models (downloaded, not bundled)

GigaAM (MIT), Qwen3/Qwen3.5 and LFM2.5/LFM3 (Apache-2.0 and the LFM Open Licence respectively),
Silero VAD (MIT), PP-OCR (Apache-2.0), T-one, Parakeet and Nemotron under the licences of their
publishers. See the model hub for the exact terms of each artifact.
