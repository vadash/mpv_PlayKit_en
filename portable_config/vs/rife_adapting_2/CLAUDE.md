# RIFE Adapting - Frame Interpolation System

## What This Is

Real-time video frame interpolation using RIFE (Real-Time Intermediate Flow Estimation) with TensorRT acceleration for mpv. Doubles frame rate (24fps → 48fps) with GPU-accelerated optical flow.

**Activation:** `Shift+6` toggles interpolation on/off

## Architecture

Two-component system:
- **`rife_main.lua`** - mpv controller (crop detection, resolution calculation, VPY generation)
- **`rife_processor.py`** - VapourSynth pipeline (RIFE processing via k7sfunc)

```
mpv (Lua) → generates VPY script → VapourSynth (Python) → RIFE → back to mpv
```

## File Locations

```
portable_config/
├── scripts/
│   └── rife_adaptive.lua          # Loader (dofiles rife_main.lua)
└── vs/
    └── rife_adapting_2/
        ├── rife_main.lua          # Main controller
        ├── rife_processor.py      # VapourSynth RIFE pipeline
        └── CLAUDE.md              # This file
```

## Key Configuration

```lua
max_pixels_million = 2.0  -- RIFE input resolution target (higher = quality, slower)
model = 4221              -- RIFE model version (4151, 4221)
gpu_id = 0                -- GPU device
gpu_threads = 2           -- TensorRT streams (higher = smoother, more VRAM)
enable_vsr = true         -- Nvidia VSR upscale to screen height (fullscreen only)
```

## Processing Flow

1. **Crop Detection** - One-time FFmpeg cropdetect for black bars
2. **Resolution Calc** - Downscale to fit `max_pixels_million`, align to 32px
3. **VPY Generation** - Write VapourSynth script to `%TEMP%/rife_adapting_2.vpy`
4. **RIFE Processing** - Crop → Resize+RGB → RIFE 2x → YUV420P10
5. **VSR Upscale** - Nvidia VSR to display height (fullscreen only)

## Design Philosophy

**Simplified System** - This version trades automatic calibration for simplicity: single Lua file, single Python file, fixed `max_pixels_million` target.

**TensorRT Optimization** - Uses static shape engines, ensemble=False turbo mode. First run builds engine (~80s), subsequent runs use cache.

**VSR Conditional Logic** - VSR only applies in fullscreen to avoid unnecessary upscaling in windowed mode.

## Working on This Code

### Reading the Code
- **Lua entry point:** `toggle_rife()`
- **Pipeline generation:** `generate_and_apply_vpy()`
- **Python processing:** `process()`
- **VSR control:** `on_fullscreen_change()`

### Modifying Behavior
- **Resolution logic:** Adjust `max_pixels_million` or calculation
- **RIFE parameters:** Modify vsmlrt.RIFE() call
- **Crop detection:** Tune FFmpeg cropdetect filter
- **VSR scaling:** Change scale calculation

### Testing Changes
```bash
# Watch mpv log for VapourSynth errors
mpv --msg-level=all=trace <video>

# Check generated VPY script
type %TEMP%\rife_adapting_2.vpy
```

### Common Gotchas
- TensorRT engine rebuilds when resolution changes (blank frames ~80s)
- Crop detection requires software decode fallback if hwdec blocks filter
- VSR requires fullscreen + YUV input format
- Model path logic hardcoded for k7sfunc structure

## Dependencies

- **Lua:** mpv's built-in Lua interpreter
- **Python:** VapourSynth, k7sfunc, vsmlrt (TensorRT backend)
- **Runtime:** RIFE ONNX models in `vs-mlrt/models/rife_v2/`

## Reference Materials

For detailed information not needed in every session:
- **Pipeline diagram:** See old CLAUDE.md or draw from code flow above
- **Debugging steps:** Check mpv log (`--msg-level=all=trace`), VPY script in %TEMP%
- **Performance tuning:** Adjust `max_pixels_million` and `gpu_threads` based on GPU power
- **Color matrix handling:** Automatically detected from video props
