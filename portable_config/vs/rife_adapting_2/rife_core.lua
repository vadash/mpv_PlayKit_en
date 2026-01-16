-- rife_core.lua - Pure functions for RIFE processing (no mpv/OS dependencies)

local M = {}

-- Get temp directory path from environment variables
-- env_vars: table with TEMP, TMP, TMPDIR keys (may be nil)
-- Returns: string path to temp directory
function M.get_temp_dir_path(env_vars)
    return env_vars.TEMP or env_vars.TMP or env_vars.TMPDIR or "/tmp"
end

-- Align value to nearest lower multiple
-- value: number to align
-- multiple: alignment boundary (e.g., 32 for GPU)
-- Returns: aligned integer
function M.align_to_multiple(value, multiple)
    return math.floor(value / multiple) * multiple
end

-- Calculate scale factor to fit source within max bounds (preserving AR)
-- Does not upscale (returns 1.0 if source smaller than bounds)
-- src_w, src_h: source dimensions
-- max_w, max_h: maximum dimensions
-- Returns: scale factor (0.0-1.0)
function M.calculate_scale_to_fit(src_w, src_h, max_w, max_h)
    local scale_w = max_w / src_w
    local scale_h = max_h / src_h
    local scale = math.min(scale_w, scale_h)

    -- Don't upscale - degrades quality before RIFE
    if scale > 1.0 then
        return 1.0
    end

    return scale
end

-- Calculate target dimensions and determine VSR path
-- This is the core resolution calculation logic (DRY constraint-based approach)
-- crop_w, crop_h: cropped source dimensions
-- screen_w, screen_h: display dimensions
-- opts: configuration table with:
--   - enable_vsr: boolean
--   - max_pixels_vsr_on: megapixels when VSR active
--   - max_pixels_vsr_off: megapixels for standard path
--   - min_vsr_mult: minimum display/target ratio for VSR
-- Returns: target_w, target_h, is_vsr_path, scale_factor
function M.calculate_targets(crop_w, crop_h, screen_w, screen_h, opts)
    -- 1. Determine Geometric Constraints
    -- How much can we scale the source before hitting screen edges?
    -- We check BOTH Width and Height ratios immediately.
    local scale_w = screen_w / crop_w
    local scale_h = screen_h / crop_h
    local scale_screen = math.min(scale_w, scale_h) -- The limiting physical factor

    -- 2. Determine VSR Eligibility & Budget
    -- We assume VSR is beneficial if the screen is significantly larger than source
    local use_vsr_path = false
    local budget_mb = opts.max_pixels_vsr_off

    if opts.enable_vsr then
        -- If we have room to upscale (physically), check if we should enable VSR logic
        if scale_screen >= opts.min_vsr_mult then
            use_vsr_path = true
            budget_mb = opts.max_pixels_vsr_on
        end
    end

    -- 3. Determine Performance Constraints
    -- How much can we scale source before hitting GPU pixel budget?
    local max_pixels = budget_mb * 1000000
    local src_pixels = crop_w * crop_h
    local scale_budget = 1.0

    if src_pixels > max_pixels then
        scale_budget = math.sqrt(max_pixels / src_pixels)
    end

    -- 4. Final Scale Selection
    -- The final scale is the most restrictive of:
    -- A. The Pixel Budget (Performance)
    -- B. The Screen Size (Geometry)
    local final_scale = math.min(scale_budget, scale_screen)

    -- 5. Calculate & Align Dimensions
    -- When screen-limited, align the constraining dimension first to maximize usage.
    -- When budget-limited, align height first then derive width.
    local ar = crop_w / crop_h
    local target_w, target_h

    local is_screen_limited = (scale_screen < scale_budget)
    local is_width_limited = (scale_w < scale_h)

    if is_screen_limited and is_width_limited then
        -- Width is the constraining dimension: set width to screen, derive height
        target_w = M.align_to_multiple(screen_w, 32)
        target_h = M.align_to_multiple(target_w / ar, 32)
        if target_h < 32 then target_h = 32 end
    elseif is_screen_limited and not is_width_limited then
        -- Height is the constraining dimension: set height to screen, derive width
        target_h = M.align_to_multiple(screen_h, 32)
        target_w = M.align_to_multiple(target_h * ar, 32)
    else
        -- Budget-limited: calculate from scale, align height first
        local raw_target_h = math.max(32, crop_h * final_scale)
        target_h = M.align_to_multiple(raw_target_h, 32)
        target_w = M.align_to_multiple(target_h * ar, 32)
    end

    -- 6. Safety Clamp (handles edge cases from alignment rounding)
    if target_w > screen_w then
        target_w = M.align_to_multiple(screen_w, 32)
        target_h = M.align_to_multiple(target_w / ar, 32)
        if target_h < 32 then target_h = 32 end
    end

    if target_h > screen_h then
        target_h = M.align_to_multiple(screen_h, 32)
        target_w = M.align_to_multiple(target_h * ar, 32)
    end

    -- Recalculate actual resulting scale for UI display
    local actual_scale = target_h / crop_h

    return target_w, target_h, use_vsr_path, actual_scale
end

return M
