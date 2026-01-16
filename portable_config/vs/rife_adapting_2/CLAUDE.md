# RIFE Adapting - Frame Interpolation for mpv

Real-time 2x frame rate interpolation using RIFE + TensorRT. Toggled with `Shift+6`.

## Architecture

```
mpv (Lua) → generates VPY → VapourSynth (Python) → RIFE → back to mpv
```

## Key Files

| File | Purpose |
|------|---------|
| `rife_main.lua` | mpv controller, VPY generation |
| `rife_processor.py` | VapourSynth RIFE pipeline |
| `rife_core.lua` | Pure testable functions (resolution logic) |
| `tests/test_rife_core.lua` | Unit tests |

## Commands

**Run tests:**
```bash
cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua
```

**Parse logs:**
JUST RUN IT. Never read the file first unless you need to change it.
Bash(cd mpv-lazy/portable_config/vs/rife_adapting_2 && python mpv_log_reader.py)

## Modifying Code

- Resolution logic → `calculate_targets()` in `rife_core.lua`
- RIFE params → `vsmlrt.RIFE()` call in `rife_processor.py`
- Config defaults → top of `rife_main.lua`

## Gotchas

- TensorRT rebuilds engine on resolution change (~80s blank frames)
- First run per resolution is slow (engine compilation)
- VSR only works in fullscreen
- Temp files: `%TEMP%\rife_adapting_2_<PID>.vpy`
