# LiteRT-LM Swift on iOS — Integration Gotchas

Four undocumented requirements you must hit to embed [LiteRTLM-Swift](https://github.com/mylovelycodes/LiteRTLM-Swift) (Gemma 4 on-device) into a new iOS app. Each one fails silently with a misleading diagnostic — together they ate about a week of debugging the first time around. Documented here so the next person (or future-you, after `xcodebuild clean`) doesn't repeat it.

## TL;DR — Symptom → Fix

| Symptom at runtime | Root cause | Fix |
|---|---|---|
| `dyld: Library not loaded: @rpath/libGemmaModelConstraintProvider.dylib … code signature invalid (errno=1)` at launch | Xcode's auto-embed-and-sign does not re-sign nested dylibs inside `CLiteRTLM.framework` | Add a Run Script build phase to re-sign + turn **off** `ENABLE_USER_SCRIPT_SANDBOXING` (§1) |
| Engine returns NULL on `load()`, model file is ~4 GB | Default iOS per-app memory cap kills the process before load completes | Add `com.apple.developer.kernel.increased-memory-limit = true` to entitlements (§2) |
| `litert_lm_engine_create returned NULL` even for text-only use | LiteRTLM-Swift v0.10.x bundled binaries are not Gemma-4-compatible | Swap with v0.11.0 binaries from flutter_gemma; pin DerivedData state (§3) |
| `engine.audio(...)` times out / returns nothing on real mic input | Default sample is synthetic sine; audio backend may be nil | Wire `AVAudioRecorder` at 16 kHz mono PCM WAV + verify audio backend is enabled (§4) |

---

## 1. Nested dylib must be re-signed (dyld crash at launch)

`CLiteRTLM.framework/libGemmaModelConstraintProvider.dylib` ships signed with the vendor's team (`3MQGX2H7EF` / DENG JIUHONG). Xcode's automatic embed-and-sign re-signs the outer framework but **not nested dylibs**. The app then fails at launch with a dyld code-signature error.

### Fix

Add a Run Script build phase **after** the "Embed Frameworks" phase:

```bash
find "$CODESIGNING_FOLDER_PATH/Frameworks" -type f -name '*.dylib' \
  | xargs -I {} codesign --force \
                          --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
                          --timestamp=none {}
```

### The silent-failure trap

By default Xcode runs scripts in a sandbox that **cannot write into the built app's `Frameworks/` directory**. The script "succeeds" (exit 0) but the codesign call is blocked. Build completes, vendor signature stays intact, app crashes at launch with the same dyld error.

Required project setting:

```
ENABLE_USER_SCRIPT_SANDBOXING = NO
```

If you skip this line you'll spend hours convinced the script is wrong. It isn't — it's just being silently denied filesystem writes.

---

## 2. Increased-memory entitlement (~4 GB allocation)

Gemma 4 E2B loads ~4 GB into RAM. iOS's default per-app memory cap (roughly 3 GB on most iPads, less on older iPhones) terminates the process during load. The symptom is usually `LiteRTLMEngine.load()` throwing or the app being jetsam-killed mid-load.

### Fix

Add to the app's `.entitlements` file:

```xml
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

Then reference it via the build setting:

```
CODE_SIGN_ENTITLEMENTS = Hearth/Hearth.entitlements
```

Note: this entitlement is allowed for development builds, TestFlight, and ad-hoc distribution out of the box. App Store distribution **requires Apple to approve** the entitlement during review — non-trivial but not blocking for a hackathon.

---

## 3. v0.10.x C binaries are not Gemma-4-compatible

LiteRTLM-Swift's bundled binaries at:

```
LiteRTLM.xcframework/ios-arm64/CLiteRTLM.framework/{CLiteRTLM, libGemmaModelConstraintProvider.dylib}
```

are NOT compatible with Gemma 4 E2B in v0.10.x. The symptom is:

```
litert_lm_engine_create returned NULL
```

at load time. This looks like a memory error (cap not lifted, model corrupted) but isn't — it's a binary-incompatibility error masquerading as one.

### Fix

Replace those two files in the SPM checkout with v0.11.0 binaries from the [flutter_gemma](https://github.com/DenisovAV/flutter_gemma) project. The SPM checkout lives at:

```
~/Library/Developer/Xcode/DerivedData/<project>/SourcePackages/checkouts/LiteRTLM-Swift/Frameworks/...
```

For vision specifically, also enable all three backends inside the package's `LiteRTLMEngine.swift` (otherwise Gemma's vision path errors with *"must have exactly one signature but got 3"*).

If you also target Simulator, repeat the swap for `ios-arm64-simulator`.

### Fragility

This swap lives in **DerivedData** and gets wiped on `xcodebuild clean` or any Swift package re-resolution. Three durable options, in order of preference:

1. **Fork LiteRTLM-Swift**, swap the binaries in the fork, pin `Package.swift` to the fork
2. **Vendor LiteRTLM-Swift as a local package** alongside the app
3. **Run a checkout-patching script** as the first build phase (copies the patched binaries back into place if DerivedData has reset)

Today this project relies on the patched DerivedData copy at:

```
~/Library/Developer/Xcode/DerivedData/gemmaDemo-fxqabynqxhbwfofbnbtznsozzhsl/SourcePackages/checkouts/LiteRTLM-Swift/Frameworks/LiteRTLM.xcframework/ios-arm64/CLiteRTLM.framework/
```

If you wipe DerivedData, you'll need to copy from a known-good location (or rebuild from flutter_gemma) before the app will run again.

---

## 4. Audio input must be real PCM, not synthetic

The default audio sample in LiteRTLM-Swift's examples is a generated sine wave. Passing it to `engine.audio()` times out — the model is looking for speech and there isn't any. Real microphone input also fails by default because the audio backend isn't always non-nil in engine settings.

### Fix

Use `AVAudioRecorder` configured for **16 kHz, mono, PCM, WAV format**:

```swift
let settings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatLinearPCM),
    AVSampleRateKey: 16_000.0,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsBigEndianKey: false,
    AVLinearPCMIsFloatKey: false
]
```

Verify that the audio backend is enabled in `LiteRTLMEngine`'s engine settings (this also affects vision — see §3).

This project's recorder wiring lives in `Hearth/Services/AudioRecorder.swift`. The voice pipeline in `Hearth/Services/HearthGemma.swift` (the `planVoiceAction` function) uses a **2-step approach** — `engine.audio()` for ASR-only with strict transcribe rules, then a separate text-only routing call — because the audio model's chronic problem is filling in sentiment that wasn't said. If you skip the 2-step split, expect transcripts like *"I miss her, please"* when the user said only *"play the show."*

---

## Order of operations for a new iOS app

These don't fail in the order they're listed. They fail in the order you'd hit them, which is:

1. **Set up §1 and §2 BEFORE writing any inference code.** Both fail at app launch / first model load, so without them you can't even test whether your Swift wiring is right.
2. **Verify §3 before invoking the engine.** A clean DerivedData on a fresh machine will give you the misleading NULL-pointer error. Have a recovery script or vendored package ready.
3. **§4 is only needed when you actually call `engine.audio()`** — text-only and vision flows don't trip it.

The Hearth project's `Hearth.xcodeproj` already has §1, §2, and §4 wired correctly. §3 lives outside the project (in DerivedData) and is the most likely thing to break on a teammate's machine.

---

## Why this isn't already in the LiteRT-LM Swift README

These are vendor-package idiosyncrasies — not project-specific. The first two are mandatory for *any* LiteRTLM integration on iOS; §3 and §4 only bite if those modalities are actually used. The package's README documents the happy path; this doc documents the four unhappy paths you'll hit if you don't know about them.

If you find a fifth, add it here.
