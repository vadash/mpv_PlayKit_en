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

-----------
-- Configuration
-----------

local opts = {
    max_pixels_million = 2.8,  -- GPU power: 2.0 (rife 4221, VSR ON) / 2.8 (rife 4221, VSR OFF) for RTX 2060S
    model = 4221,              -- RIFE model number
    gpu_id = 0,                -- GPU device
    gpu_threads = 2,           -- GPU threads
    enable_vsr = true,         -- Nvidia VSR upscale to screen height
    min_vsr_mult = 1.5,        -- Minimum display/target ratio for VSR activation
}

-----------
-- State
-----------

local state = {
    rife_active = false,
    current_crop = nil,
    cropdetect_timer = nil,
    crop_samples = {},
    crop_log_handler = nil,
    is_fullscreen = false,
    target_w = nil,  -- Track target dimensions for VSR calculation
    target_h = nil,
}

-----------
-- Forward Declarations
-----------

local generate_and_apply_vpy

-----------
-- Helper Functions
-----------

local function get_source_dims()
    local w = mp.get_property_native("video-params/w") or 1920
    local h = mp.get_property_native("video-params/h") or 1080
    return w, h
end

local function get_display_height()
    return mp.get_property_native("display-height") or 2160
end

local function get_container_fps()
    return mp.get_property_number("container-fps") or 24.0
end

local function osd_message(msg, duration)
    duration = duration or 3
    mp.osd_message("[RIFE] " .. msg, duration)
end

local function apply_vsr_filter()
    if not opts.enable_vsr or not state.target_w or not state.target_h then
        return
    end

    local display_w = mp.get_property_native("display-width") or 3840
    local display_h = get_display_height()

    local scale_w = display_w / state.target_w
    local scale_h = display_h / state.target_h

    -- Use smaller scale to fit within display bounds
    local vsr_scale = math.min(scale_w, scale_h)

    if vsr_scale >= opts.min_vsr_mult then
        mp.command(string.format('vf add @rife-vsr:d3d11vpp:scaling-mode=nvidia:scale=%.10f', vsr_scale))
        osd_message("VSR enabled", 2)
    end
end

local function remove_vsr_filter()
    -- Try to remove the filter (no error if it doesn't exist)
    mp.commandv("vf", "remove", "@rife-vsr")
    osd_message("VSR disabled", 2)
end

-----------
-- Crop Detection
-----------

local function finish_crop_detection()
    -- Stop timer
    if state.cropdetect_timer then
        state.cropdetect_timer:kill()
        state.cropdetect_timer = nil
    end

    -- Remove cropdetect filter
    local filters = mp.get_property_native("vf")
    for i, f in ipairs(filters) do
        if f.label == "rife-cropdetect" then
            mp.commandv("vf", "remove", "@rife-cropdetect")
            break
        end
    end

    -- Unregister log handler
    if state.crop_log_handler then
        mp.unregister_event(state.crop_log_handler)
        state.crop_log_handler = nil
    end

    -- Analyze collected crops - find most common
    if #state.crop_samples == 0 then
        state.current_crop = nil
        osd_message("No black bars detected")
        generate_and_apply_vpy()
        return
    end

    -- Count occurrences
    local crop_counts = {}
    for _, c in ipairs(state.crop_samples) do
        local key = string.format("%d:%d:%d:%d", c.w, c.h, c.x, c.y)
        crop_counts[key] = (crop_counts[key] or 0) + 1
    end

    -- Find most common
    local best_key = nil
    local best_count = 0
    for key, count in pairs(crop_counts) do
        if count > best_count then
            best_key = key
            best_count = count
        end
    end

    if best_key then
        local w, h, x, y = best_key:match("(%d+):(%d+):(%d+):(%d+)")
        local source_w, source_h = get_source_dims()

        -- Only crop top/bottom (no left/right bars assumed)
        state.current_crop = {
            w = source_w,
            h = tonumber(h),
            x = 0,
            y = tonumber(y)
        }

        -- Only use if actually cropping
        if state.current_crop.h >= source_h then
            state.current_crop = nil
            osd_message("No black bars detected")
        else
            osd_message(string.format("Crop: %dx%d", state.current_crop.w, state.current_crop.h))
        end
    end

    state.crop_samples = {}
    generate_and_apply_vpy()
end

local function start_crop_detection()
    state.crop_samples = {}
    state.current_crop = nil
    osd_message("Detecting black bars...", 1)

    -- Register log handler
    mp.enable_messages('v')
    state.crop_log_handler = function(event)
        if event.prefix ~= "ffmpeg" or event.level ~= "v" then
            return
        end

        -- Parse: "x1:0 x2:1919 y1:138 y2:941 w:1920 h:800 x:0 y:140 pts:..."
        local w = event.text:match("w:(%d+)")
        local h = event.text:match("h:(%d+)")
        local x = event.text:match("x:(%d+)")
        local y = event.text:match("y:(%d+)")

        if w and h and x and y then
            table.insert(state.crop_samples, {
                w = tonumber(w),
                h = tonumber(h),
                x = tonumber(x),
                y = tonumber(y)
            })

            osd_message(string.format("Detecting... [%d]", #state.crop_samples), 1)

            -- Enough samples
            if #state.crop_samples >= 10 then
                finish_crop_detection()
            end
        end
    end
    mp.register_event("log-message", state.crop_log_handler)

    -- Add cropdetect filter
    local success = mp.commandv("vf", "pre", "@rife-cropdetect:lavfi=[cropdetect=limit=24/255:round=2:reset=1]")

    if not success then
        -- Fallback: try auto-copy decode
        mp.set_property("hwdec", "auto-copy")
        success = mp.commandv("vf", "pre", "@rife-cropdetect:lavfi=[cropdetect=limit=24/255:round=2:reset=1]")
    end

    if not success then
        osd_message("Crop detection failed", 5)
        finish_crop_detection()  -- Continue without crop
        return
    end

    -- Timeout after 1 second
    state.cropdetect_timer = mp.add_timeout(1.0, function()
        finish_crop_detection()
    end)
end

-----------
-- VPY Generation
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

    -- Calculate target resolution (downscale if needed)
    local current_pixels = crop_w * crop_h
    local max_pixels = opts.max_pixels_million * 1000000
    local scale = 1.0

    if current_pixels > max_pixels then
        scale = math.sqrt(max_pixels / current_pixels)
    end

    -- Align to 32 for TensorRT efficiency
    local target_w = math.floor((crop_w * scale) / 32) * 32
    local target_h = math.floor((crop_h * scale) / 32) * 32

    -- Store target dimensions for VSR
    state.target_w = target_w
    state.target_h = target_h

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

    -- Write VPY file
    local vpy_path = os.getenv("TEMP") .. "/rife_adapting_2.vpy"
    local f = io.open(vpy_path, "w")
    if not f then
        osd_message("Failed to create VPY", 5)
        return
    end
    f:write(vpy_content)
    f:close()

    -- Clear existing filters
    mp.command('vf set ""')

    -- Apply vapoursynth filter
    mp.command(string.format('vf set vapoursynth="%s"', vpy_path))

    -- Apply VSR upscale only when fullscreen
    if state.is_fullscreen then
        apply_vsr_filter()
    end

    -- Show OSD status
    local vsr_status = (opts.enable_vsr and state.is_fullscreen) and tostring(get_display_height()) .. "p (VSR)" or tostring(target_h) .. "p"
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
        if state.cropdetect_timer then
            state.cropdetect_timer:kill()
            state.cropdetect_timer = nil
        end
        if state.crop_log_handler then
            mp.unregister_event(state.crop_log_handler)
            state.crop_log_handler = nil
        end

        mp.command('vf set ""')
        state.rife_active = false
        state.current_crop = nil
        osd_message("OFF")
    else
        -- Turn on
        local fps = get_container_fps()
        if fps > 50 then
            osd_message(string.format("Source FPS %.2f too high", fps), 5)
            return
        end

        state.rife_active = true
        start_crop_detection()
    end
end

-----------
-- Fullscreen Observer
-----------

local function on_fullscreen_change(name, value)
    state.is_fullscreen = value or false

    -- Only toggle VSR if RIFE is currently active
    if not state.rife_active then
        return
    end

    if state.is_fullscreen then
        apply_vsr_filter()
    else
        remove_vsr_filter()
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
    osd_message("Loaded (Shift+6)", 2)
end)
