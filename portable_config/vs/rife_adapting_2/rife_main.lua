--[[
    rife_main.lua - Simplified RIFE controller

    Keybinding: Ctrl+6 to toggle RIFE on/off

    Features:
    - One-time black bar crop detection
    - Resolution downscaling based on GPU power
    - RIFE interpolation via k7sfunc
    - Nvidia VSR upscaling to screen height
]]

local mp = require 'mp'

-- Add script directory to package path for local modules
local script_path = debug.getinfo(1, "S").source:sub(2)  -- Remove @ prefix
local script_dir = script_path:match("(.*/)")  or script_path:match("(.*\\)") or ""
package.path = script_dir .. "?.lua;" .. package.path

local core = require('rife_core')

-----------
-- Configuration
-----------

local opts = {
    max_pixels_vsr_on = 2.0,   -- GPU power when VSR will upscale (RTX 2060S)
    max_pixels_vsr_off = 3.0,  -- GPU power for standard upscale (RTX 2060S)
    model = 4221,              -- RIFE model number
    gpu_id = 0,                -- GPU device
    gpu_threads = 2,           -- GPU threads
    enable_vsr = true,         -- Nvidia VSR upscale to screen height
    min_vsr_mult = 1.5,        -- Minimum display/target ratio for VSR activation
}

-- Log configuration on load
mp.msg.debug("[rife_adaptive][INIT] Configuration loaded: enable_vsr=" .. tostring(opts.enable_vsr) ..
             ", max_pixels_vsr_on=" .. opts.max_pixels_vsr_on ..
             ", max_pixels_vsr_off=" .. opts.max_pixels_vsr_off ..
             ", model=" .. opts.model ..
             ", gpu_id=" .. opts.gpu_id ..
             ", gpu_threads=" .. opts.gpu_threads ..
             ", min_vsr_mult=" .. opts.min_vsr_mult)

-----------
-- State
-----------

local state = {
    rife_active = false,
    current_crop = nil,
    cropdetect_timer = nil,
    is_fullscreen = false,
    target_w = nil,
    target_h = nil,
    vsr_path_active = false,
    pid = mp.get_property_native("pid") or "0",
}

-----------
-- Forward Declarations
-----------

local generate_and_apply_vpy

-----------
-- Helper Functions
-----------

local function get_temp_dir()
    return core.get_temp_dir_path({
        TEMP = os.getenv("TEMP"),
        TMP = os.getenv("TMP"),
        TMPDIR = os.getenv("TMPDIR")
    })
end

local function get_source_dims()
    local w = mp.get_property_native("video-params/w") or 1920
    local h = mp.get_property_native("video-params/h") or 1080
    return w, h
end

local function get_screen_dims()
    local w = mp.get_property_native("display-width") or mp.get_property_native("display-res-x")
    local h = mp.get_property_native("display-height") or mp.get_property_native("display-res-y")
    return w or 2560, h or 1440
end

local function get_container_fps()
    return mp.get_property_number("container-fps") or 24.0
end

local function osd_message(msg, duration)
    duration = duration or 3
    mp.osd_message("[RIFE] " .. msg, duration)
end

local function update_vsr_state()
    mp.msg.debug("[rife_adaptive][VSR] Update requested: rife_active=" .. tostring(state.rife_active) ..
                 ", vsr_path=" .. tostring(state.vsr_path_active) ..
                 ", fullscreen=" .. tostring(state.is_fullscreen) ..
                 ", target=" .. tostring(state.target_w) .. "x" .. tostring(state.target_h))

    if not state.rife_active or not state.vsr_path_active or not state.target_w then
        mp.commandv("vf", "remove", "@rife-vsr")
        mp.msg.debug("[rife_adaptive][VSR] Removed (not in VSR path or RIFE inactive)")
        return
    end

    if state.is_fullscreen then
        local screen_w, screen_h = get_screen_dims()

        mp.msg.debug("[rife_adaptive][VSR] Calculating scale: screen=" .. screen_w .. "x" .. screen_h ..
                     ", target=" .. state.target_w .. "x" .. state.target_h)

        local scale_w = screen_w / state.target_w
        local scale_h = screen_h / state.target_h
        local vsr_scale = math.min(scale_w, scale_h)

        mp.msg.debug("[rife_adaptive][VSR] Scale check: " .. string.format("%.2f", vsr_scale) ..
                     " >= " .. opts.min_vsr_mult)

        if vsr_scale >= opts.min_vsr_mult then
            mp.commandv("vf", "remove", "@rife-vsr")
            mp.command(string.format('vf add @rife-vsr:d3d11vpp:scaling-mode=nvidia:scale=%.10f', vsr_scale))
            mp.msg.debug("[rife_adaptive][VSR] ACTIVATED: scale=" .. string.format("%.2f", vsr_scale))
            osd_message("VSR ON", 2)
            return
        else
            mp.msg.debug("[rife_adaptive][VSR] DEACTIVATED: scale too low (" .. string.format("%.2f", vsr_scale) .. ")")
        end
    end

    mp.commandv("vf", "remove", "@rife-vsr")
    if state.is_fullscreen then
        osd_message("VSR OFF", 2)
    end
end

-----------
-- Crop Detection
-----------

local function finish_crop_detection()
    if state.cropdetect_timer then
        state.cropdetect_timer:kill()
        state.cropdetect_timer = nil
    end

    local meta = mp.get_property_native("vf-metadata/rife-cropdetect") or {}
    mp.commandv("vf", "remove", "@rife-cropdetect")

    local w = tonumber(meta["lavfi.cropdetect.w"])
    local h = tonumber(meta["lavfi.cropdetect.h"])
    local x = tonumber(meta["lavfi.cropdetect.x"])
    local y = tonumber(meta["lavfi.cropdetect.y"])

    mp.msg.debug("[rife_adaptive][CROP] Raw metadata: w=" .. (w or "nil") ..
                 ", h=" .. (h or "nil") ..
                 ", x=" .. (x or "nil") ..
                 ", y=" .. (y or "nil"))

    if w and h and x and y then
        local source_w, source_h = get_source_dims()
        if h < source_h then
            state.current_crop = { w = source_w, h = h, x = 0, y = y }
            local removed_px = source_h - h
            mp.msg.debug("[rife_adaptive][CROP] Result: " .. source_w .. "x" .. h ..
                         " at (0," .. y .. "), removed " .. removed_px .. "px vertical")
            osd_message(string.format("Crop: %dx%d", source_w, h))
        else
            state.current_crop = nil
            mp.msg.debug("[rife_adaptive][CROP] No black bars detected, using full frame " .. source_w .. "x" .. source_h)
            osd_message("No black bars detected")
        end
    else
        state.current_crop = nil
        mp.msg.debug("[rife_adaptive][CROP] Detection failed, metadata incomplete")
        osd_message("Crop detection failed")
    end

    generate_and_apply_vpy()
end

local function start_crop_detection()
    state.current_crop = nil
    mp.msg.debug("[rife_adaptive][CROP] Starting detection (1s timeout)")
    osd_message("Detecting black bars...", 1)

    mp.commandv("vf", "pre", "@rife-cropdetect:lavfi=[cropdetect=limit=24/255:round=2:reset=1]")
    state.cropdetect_timer = mp.add_timeout(1.0, finish_crop_detection)
end

-----------
-- VPY Generation
-----------

-----------
-- Core Resolution Calculation (Unified Logic)
-----------

generate_and_apply_vpy = function()
    local source_w, source_h = get_source_dims()
    local crop_w, crop_h, crop_x, crop_y = source_w, source_h, 0, 0

    -- Use crop if detected
    if state.current_crop then
        crop_w = state.current_crop.w
        crop_h = state.current_crop.h
        crop_x = state.current_crop.x
        crop_y = state.current_crop.y
    end

    mp.msg.debug("[rife_adaptive][VPY] Source: " .. source_w .. "x" .. source_h ..
                 ", Crop: " .. crop_w .. "x" .. crop_h ..
                 " at (" .. crop_x .. "," .. crop_y .. ")")

    -- UNIFIED LOGIC: Calculate targets and determine path in one place
    local screen_w, screen_h = get_screen_dims()
    local target_w, target_h, vsr_active, scale = core.calculate_targets(crop_w, crop_h, screen_w, screen_h, opts)

    -- Store results in state
    state.target_w = target_w
    state.target_h = target_h
    state.vsr_path_active = vsr_active

    mp.msg.debug(string.format("[rife_adaptive][VPY] Resolution: %dx%d -> %dx%d (Scale %.2f) | VSR Path: %s",
        crop_w, crop_h, target_w, target_h, scale, tostring(vsr_active)))

    -- Generate inline VPY content
    -- Get absolute path to rife_adapting_2 directory
    local script_dir = mp.command_native({"expand-path", "~~/vs/rife_adapting_2"})
    local vpy_content = string.format([[
import sys
import os
sys.path.insert(0, r"%s")

import vapoursynth as vs
from vapoursynth import core
from rife_processor import process

clip = video_in

# Process with RIFE
clip = process(
    clip=clip,
    crop_l=%d,
    crop_t=%d,
    crop_w=%d,
    crop_h=%d,
    target_w=%d,
    target_h=%d,
    model=%d,
    gpu_id=%d,
    gpu_t=%d
)

clip.set_output()
]], script_dir, crop_x, crop_y, crop_w, crop_h, target_w, target_h, opts.model, opts.gpu_id, opts.gpu_threads)

    -- Write VPY file (unique per PID to support multiple mpv instances)
    local vpy_path = get_temp_dir() .. "/rife_adapting_2_" .. state.pid .. ".vpy"
    local f = io.open(vpy_path, "w")
    if not f then
        mp.msg.debug("[rife_adaptive][VPY] ERROR: Failed to create VPY file at " .. vpy_path)
        osd_message("Failed to create VPY", 5)
        return
    end
    f:write(vpy_content)
    f:close()

    mp.msg.debug("[rife_adaptive][VPY] Script written to: " .. vpy_path)

    -- Remove our filters (safe if not present)
    mp.commandv("vf", "remove", "@rife-vsr")
    mp.commandv("vf", "remove", "vapoursynth")

    -- Apply vapoursynth filter
    mp.command(string.format('vf add vapoursynth="%s"', vpy_path))
    mp.msg.debug("[rife_adaptive][VPY] VapourSynth filter applied")

    -- Update VSR state
    update_vsr_state()

    -- Show OSD status
    local vsr_status
    if state.vsr_path_active then
        if state.is_fullscreen then
            local _, screen_h = get_screen_dims()
            vsr_status = tostring(screen_h) .. "p (VSR)"
        else
            vsr_status = tostring(target_h) .. "p (VSR ready)"
        end
    else
        vsr_status = tostring(target_h) .. "p"
    end

    local status = string.format("%dx%d -> %dx%d -> %s",
        source_w, source_h,
        target_w, target_h,
        vsr_status)
    osd_message(status, 4)
end

-----------
-- Toggle Handler
-----------

local function toggle_rife()
    if state.rife_active then
        -- Turn off
        mp.msg.debug("[rife_adaptive][TOGGLE] RIFE deactivation requested")

        if state.cropdetect_timer then
            state.cropdetect_timer:kill()
            state.cropdetect_timer = nil
            mp.msg.debug("[rife_adaptive][TOGGLE] Killed pending crop detection timer")
        end

        mp.commandv("vf", "remove", "@rife-vsr")
        mp.commandv("vf", "remove", "vapoursynth")
        state.rife_active = false
        state.current_crop = nil
        state.vsr_path_active = false
        mp.msg.debug("[rife_adaptive][TOGGLE] RIFE deactivated, filters removed, state reset")
        osd_message("OFF")
    else
        -- Turn on
        local fps = get_container_fps()
        mp.msg.debug("[rife_adaptive][TOGGLE] RIFE activation requested, container_fps=" .. fps)

        if fps > 50 then
            mp.msg.debug("[rife_adaptive][TOGGLE] FPS check: " .. fps .. " > 50 = REJECTED")
            osd_message(string.format("Source FPS %.2f too high", fps), 5)
            return
        end

        mp.msg.debug("[rife_adaptive][TOGGLE] FPS check: " .. fps .. " <= 50 = PASSED")
        state.rife_active = true
        start_crop_detection()
    end
end

-----------
-- Fullscreen Observer
-----------

local function on_fullscreen_change(name, value)
    state.is_fullscreen = value or false
    mp.msg.debug("[rife_adaptive][FULLSCREEN] State changed: " .. tostring(state.is_fullscreen) ..
                 ", rife_active=" .. tostring(state.rife_active))
    if state.rife_active then
        update_vsr_state()
    end
end

-----------
-- Keybinding
-----------

-- Bind Shift+6 across different keyboard layouts
-- US QWERTY: ^ | German QWERTZ: & | French AZERTY: ° | Spanish: ^ | Italian: ° | Russian: :
local shift6_keys = {"^", "&", "°", ":"}
for _, key in ipairs(shift6_keys) do
    mp.add_key_binding(key, "toggle-rife-" .. key, toggle_rife)
end

-- Also bind literal Shift+6 (works on some systems)
mp.add_forced_key_binding("Shift+6", "toggle-rife-shift6", toggle_rife)

mp.register_script_message("toggle-adaptive-rife", toggle_rife)

-----------
-- Initialization
-----------

-- Initialize fullscreen state
state.is_fullscreen = mp.get_property_native("fullscreen") or false

-- Observe fullscreen changes
mp.observe_property("fullscreen", "bool", on_fullscreen_change)

-- Show startup message to confirm script loaded
mp.add_timeout(3, function()
    mp.msg.info("RIFE rife_adapting_2 loaded - Press Shift+6 to toggle")
    mp.msg.debug("[rife_adaptive][INIT] Script fully initialized, keybindings registered")
    osd_message("Loaded (Shift+6)", 2)
end)
