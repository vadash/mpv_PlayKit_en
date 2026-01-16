local lu = require('luaunit')
local core = require('rife_core')

TestTempDir = {}

function TestTempDir:test_uses_TEMP_first()
  local result = core.get_temp_dir_path({TEMP="C:\\Windows\\Temp", TMP="C:\\tmp", TMPDIR="/tmp"})
  lu.assertEquals(result, "C:\\Windows\\Temp")
end

function TestTempDir:test_uses_TMP_when_TEMP_missing()
  local result = core.get_temp_dir_path({TMP="C:\\tmp", TMPDIR="/tmp"})
  lu.assertEquals(result, "C:\\tmp")
end

function TestTempDir:test_uses_TMPDIR_when_TEMP_TMP_missing()
  local result = core.get_temp_dir_path({TMPDIR="/tmp"})
  lu.assertEquals(result, "/tmp")
end

function TestTempDir:test_defaults_to_tmp_when_all_missing()
  local result = core.get_temp_dir_path({})
  lu.assertEquals(result, "/tmp")
end

TestAlignment = {}

function TestAlignment:test_already_aligned()
  lu.assertEquals(core.align_to_multiple(1920, 32), 1920)
  lu.assertEquals(core.align_to_multiple(1024, 32), 1024)
end

function TestAlignment:test_align_down()
  lu.assertEquals(core.align_to_multiple(1919, 32), 1888)
  lu.assertEquals(core.align_to_multiple(533, 32), 512)
  lu.assertEquals(core.align_to_multiple(1281, 32), 1280)
end

function TestAlignment:test_small_values()
  lu.assertEquals(core.align_to_multiple(31, 32), 0)
  lu.assertEquals(core.align_to_multiple(0, 32), 0)
end

function TestAlignment:test_different_multiples()
  lu.assertEquals(core.align_to_multiple(100, 16), 96)
  lu.assertEquals(core.align_to_multiple(100, 10), 100)
end

TestScaleToFit = {}

function TestScaleToFit:test_landscape_constrained_by_width()
  local scale = core.calculate_scale_to_fit(3840, 1600, 2560, 1440)
  lu.assertAlmostEquals(scale, 2560/3840, 0.001)
end

function TestScaleToFit:test_landscape_constrained_by_height()
  local scale = core.calculate_scale_to_fit(1920, 1200, 2560, 1440)
  lu.assertEquals(scale, 1.0)  -- No upscaling
end

function TestScaleToFit:test_portrait_video()
  local scale = core.calculate_scale_to_fit(1080, 1920, 2560, 1440)
  lu.assertAlmostEquals(scale, 1440/1920, 0.001)
end

function TestScaleToFit:test_source_smaller_than_screen()
  local scale = core.calculate_scale_to_fit(1280, 720, 2560, 1440)
  lu.assertEquals(scale, 1.0)  -- No upscaling
end

function TestScaleToFit:test_exact_fit()
  local scale = core.calculate_scale_to_fit(2560, 1440, 2560, 1440)
  lu.assertEquals(scale, 1.0)
end

TestCalculateTargets = {}

function TestCalculateTargets:test_vsr_disabled_uses_vsr_off_budget()
  local opts = {
    enable_vsr = false,
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 2.9,
    min_vsr_mult = 1.5
  }
  local tw, th, vsr, scale = core.calculate_targets(1920, 800, 2560, 1440, opts)

  lu.assertFalse(vsr)
  lu.assertTrue(tw > 0 and th > 0)
  -- Should use 2.9MP budget
  local pixels = tw * th
  lu.assertTrue(pixels <= 2900000)
end

function TestCalculateTargets:test_source_larger_than_screen_clamps_to_screen()
  local opts = {
    enable_vsr = true,
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 2.9,
    min_vsr_mult = 1.5
  }
  -- 4K source on 1440p screen - must never exceed screen dimensions
  local tw, th, vsr, scale = core.calculate_targets(3840, 1600, 2560, 1440, opts)

  lu.assertTrue(tw <= 2560 and th <= 1440)  -- Must fit screen
  -- VSR can activate if downscaled result allows meaningful upscale (ratio >= 1.5)
end

function TestCalculateTargets:test_width_limited_clamps_to_screen_width()
  local opts = {
    enable_vsr = false,  -- Disable VSR to test vsr_off budget clamping
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 3.0,
    min_vsr_mult = 1.5
  }
  -- Ultrawide 4K on 2560x1440 screen - width is limiting factor
  -- Budget (3.0 MP) allows, but screen limits scale to ~0.667
  local tw, th, vsr, scale = core.calculate_targets(3840, 1608, 2560, 1440, opts)

  lu.assertTrue(tw <= 2560)  -- Must not exceed screen width
  lu.assertTrue(th <= 1440)  -- Height must also fit
  lu.assertEquals(tw % 32, 0) -- Must be aligned
end

function TestCalculateTargets:test_height_limited_clamps_to_screen_height()
  local opts = {
    enable_vsr = false,  -- Disable VSR to test vsr_off budget clamping
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 3.0,
    min_vsr_mult = 1.5
  }
  -- Tall content on wide screen - height is limiting factor
  local tw, th, vsr, scale = core.calculate_targets(1920, 2160, 2560, 1440, opts)

  lu.assertTrue(tw <= 2560)
  lu.assertEquals(th, 1440)  -- Must clamp to screen height
end

function TestCalculateTargets:test_budget_used_when_smaller_than_screen()
  local opts = {
    enable_vsr = false,
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 1.0,  -- Very tight budget
    min_vsr_mult = 1.5
  }
  -- 4K source with 1.0 MP budget - budget limits before screen does
  local tw, th, vsr, scale = core.calculate_targets(3840, 2160, 2560, 1440, opts)

  local pixels = tw * th
  lu.assertTrue(pixels <= 1100000)  -- ~1 MP with alignment tolerance
  lu.assertTrue(tw < 2560)  -- Budget limited, not screen limited
end

function TestCalculateTargets:test_vsr_insufficient_ratio_uses_standard_path()
  local opts = {
    enable_vsr = true,
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 2.9,
    min_vsr_mult = 1.5
  }
  -- Small crop where VSR ratio would be < 1.5
  local tw, th, vsr, scale = core.calculate_targets(1920, 1000, 2560, 1440, opts)

  lu.assertFalse(vsr)  -- Ratio insufficient
  local pixels = tw * th
  lu.assertTrue(pixels <= 2900000)  -- Uses vsr_off budget
end

function TestCalculateTargets:test_vsr_path_selected_when_ratio_sufficient()
  local opts = {
    enable_vsr = true,
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 2.9,
    min_vsr_mult = 1.5
  }
  -- 1600x800 crop on 2560x1440 screen - BOTH ratios must be >= 1.5
  -- ratio_w = 2560/1600 = 1.6, ratio_h = 1440/800 = 1.8, min = 1.6 >= 1.5
  local tw, th, vsr, scale = core.calculate_targets(1600, 800, 2560, 1440, opts)

  lu.assertTrue(vsr)  -- Should use VSR path
  local pixels = tw * th
  lu.assertTrue(pixels <= 2000000)  -- Uses vsr_on budget
end

function TestCalculateTargets:test_vsr_uses_min_of_both_ratios()
  local opts = {
    enable_vsr = true,
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 2.9,
    min_vsr_mult = 1.5
  }
  -- Wide content: height ratio good (1.8x) but width ratio bad (1.33x)
  -- 1920x800 on 2560x1440: ratio_w=1.33, ratio_h=1.8, min=1.33 < 1.5
  local tw, th, vsr, scale = core.calculate_targets(1920, 800, 2560, 1440, opts)

  lu.assertFalse(vsr)  -- Width ratio insufficient, should NOT use VSR path
  local pixels = tw * th
  lu.assertTrue(pixels <= 2900000)  -- Uses vsr_off budget instead
end

function TestCalculateTargets:test_aspect_ratio_preserved()
  local opts = {
    enable_vsr = false,
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 2.9,
    min_vsr_mult = 1.5
  }

  local crop_w, crop_h = 1920, 800
  local tw, th = core.calculate_targets(crop_w, crop_h, 2560, 1440, opts)

  local source_ar = crop_w / crop_h
  local target_ar = tw / th

  -- AR should be preserved within alignment tolerance
  lu.assertAlmostEquals(source_ar, target_ar, 0.05)
end

function TestCalculateTargets:test_dimensions_aligned_to_32px()
  local opts = {
    enable_vsr = false,
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 2.9,
    min_vsr_mult = 1.5
  }

  local tw, th = core.calculate_targets(1920, 800, 2560, 1440, opts)

  lu.assertEquals(tw % 32, 0)
  lu.assertEquals(th % 32, 0)
end

function TestCalculateTargets:test_pixel_budget_enforced()
  local opts = {
    enable_vsr = false,
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 2.9,
    min_vsr_mult = 1.5
  }

  -- Large source that needs downscaling
  local tw, th = core.calculate_targets(3840, 2160, 2560, 1440, opts)
  local pixels = tw * th

  lu.assertTrue(pixels <= 2900000)  -- Within budget
end

function TestCalculateTargets:test_no_upscaling_small_source()
  local opts = {
    enable_vsr = false,
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 2.9,
    min_vsr_mult = 1.5
  }

  -- Small source under budget
  local crop_w, crop_h = 1280, 720
  local tw, th, vsr, scale = core.calculate_targets(crop_w, crop_h, 2560, 1440, opts)

  -- Should not upscale
  lu.assertTrue(tw <= crop_w)
  lu.assertTrue(th <= crop_h)
  lu.assertTrue(scale <= 1.0)
end

function TestCalculateTargets:test_extreme_aspect_ratio()
  local opts = {
    enable_vsr = false,
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 2.9,
    min_vsr_mult = 1.5
  }

  -- Ultra-wide 21:9
  local tw, th = core.calculate_targets(2560, 1080, 2560, 1440, opts)

  lu.assertTrue(tw > 0 and th > 0)
  lu.assertEquals(tw % 32, 0)
  lu.assertEquals(th % 32, 0)
end

-- ============================================================================
-- TestAspectRatios - Real-world aspect ratio scenarios
-- ============================================================================

TestAspectRatios = {}

-- Standard settings for these tests
local std_opts = {
  enable_vsr = true,
  max_pixels_vsr_on = 8.0, -- High budget to ensure we test geometry, not pixel limits
  max_pixels_vsr_off = 8.0,
  min_vsr_mult = 1.3       -- Low threshold to allow upscaling
}

function TestAspectRatios:test_4_3_content_on_16_9_screen()
  -- Input: 1440x1080 (Standard 4:3 HD)
  -- Screen: 2560x1440 (1440p)
  -- Algorithm does NOT pre-upscale - VSR handles upscaling to screen
  -- Source fits within screen and budget, so output ~= source (aligned)

  local tw, th, vsr, scale = core.calculate_targets(1440, 1080, 2560, 1440, std_opts)

  -- Height aligns: 1080 -> 1056
  -- Width from aligned height: 1056 * (1440/1080) = 1408
  lu.assertEquals(th, 1056)
  lu.assertEquals(tw, 1408)
  lu.assertTrue(tw < 2560) -- Pillarbox expected
  lu.assertTrue(vsr) -- VSR should activate (scale_screen = 1.33 >= 1.3)
end

function TestAspectRatios:test_ultrawide_content_on_16_9_screen()
  -- Input: 1920x800 (CinemaScope 2.40:1)
  -- Screen: 2560x1440
  -- Algorithm does NOT pre-upscale - keeps source size when fits screen/budget

  local tw, th, vsr, scale = core.calculate_targets(1920, 800, 2560, 1440, std_opts)

  lu.assertEquals(tw, 1920) -- Keep source width (fits screen)
  lu.assertEquals(th, 800)  -- Keep source height (aligned - 800 is divisible by 32)
  lu.assertTrue(th < 1440)  -- Letterbox expected

  -- Check AR preservation: 1920/800 = 2.4
  local result_ar = tw / th
  lu.assertAlmostEquals(result_ar, 2.4, 0.1)
end

function TestAspectRatios:test_vertical_video_on_landscape_screen()
  -- Input: 1080x1920 (Phone recording 9:16)
  -- Screen: 2560x1440
  -- Expectation: Height clamped to screen (1440), Width scales down (~810)

  local tw, th, vsr, scale = core.calculate_targets(1080, 1920, 2560, 1440, std_opts)

  lu.assertEquals(th, 1440) -- Max height
  lu.assertTrue(tw < 1440)  -- Width is small

  -- AR Check: 1080/1920 = 0.5625
  local result_ar = tw / th
  lu.assertAlmostEquals(result_ar, 0.5625, 0.1)
end

function TestAspectRatios:test_weird_crop_input()
  -- Scenario: User cropped asymmetrical black bars manually or via script
  -- Input: 1300x700 (Arbitrary dimensions)
  -- Screen: 1920x1080
  -- Algorithm does NOT pre-upscale - keeps source when fits screen/budget

  local tw, th, vsr, scale = core.calculate_targets(1300, 700, 1920, 1080, std_opts)

  -- Height aligns: 700 -> 672
  -- Width from aligned height: 672 * (1300/700) = 1248
  lu.assertEquals(th, 672)
  lu.assertEquals(tw, 1248)
  lu.assertTrue(tw < 1920)
  lu.assertTrue(th < 1080)
end

function TestAspectRatios:test_ultrawide_on_standard_screen()
  -- Input: 1920x800 (2.4:1 Aspect Ratio)
  -- Screen: 1920x1080 (1.78:1 Aspect Ratio)
  -- The WIDTH matches, but HEIGHT is smaller.
  -- Old logic might have tried to scale height to 1080, making width ~2592 (too big).
  -- New logic should check width limit first.

  local tw, th, vsr, scale = core.calculate_targets(1920, 800, 1920, 1080, std_opts)

  lu.assertEquals(tw, 1920) -- Should be limited by screen width
  lu.assertTrue(th < 1080)  -- Should have letterboxing
  lu.assertAlmostEquals(scale, 1.0, 0.01)
end

function TestAspectRatios:test_vertical_video_on_standard_screen()
  -- Input: 1080x1920 (9:16)
  -- Screen: 1920x1080 (16:9)
  -- HEIGHT matches, WIDTH is smaller.

  local tw, th, vsr, scale = core.calculate_targets(1080, 1920, 1920, 1080, std_opts)

  lu.assertEquals(th, 1056) -- Should be limited by screen height (aligned)
  lu.assertTrue(tw < 1920)  -- Should have pillarboxing

  -- 1080 / 1920 scale factor should be applied
  local expected_scale = 1056 / 1920
  lu.assertAlmostEquals(scale, expected_scale, 0.01)
end

function TestAspectRatios:test_budget_limits_both_dimensions()
  -- Input: 4000x4000 (Square video, high res)
  -- Screen: 5000x5000
  -- Budget: 4MP (2000x2000)

  local opts = {
      enable_vsr = false,
      max_pixels_vsr_on = 4.0,
      max_pixels_vsr_off = 4.0, -- 4MP budget
      min_vsr_mult = 1.5
  }

  local tw, th, vsr, scale = core.calculate_targets(4000, 4000, 5000, 5000, opts)

  -- Should scale down to fit 4MP budget
  -- sqrt(4,000,000 / 16,000,000) = 0.5 scale -> 2000
  -- align(2000, 32) = 1984 (2000/32 = 62.5, floor = 62, 62*32 = 1984)

  lu.assertAlmostEquals(scale, 1984/4000, 0.02)
  lu.assertEquals(tw, 1984) -- 2000 aligned down
  lu.assertEquals(th, 1984)
end

function TestAspectRatios:test_downscale_to_fit_screen()
  -- Input: 3840x2160 (4K)
  -- Screen: 1920x1080 (1080p)
  -- Budget: Huge (allows 4K)
  -- Expectation: Must downscale to fit screen (scale = 0.5)

  local opts = {
      enable_vsr = false,
      max_pixels_vsr_on = 99.0,
      max_pixels_vsr_off = 99.0, -- Huge budget
      min_vsr_mult = 1.0
  }

  local tw, th, vsr, scale = core.calculate_targets(3840, 2160, 1920, 1080, opts)

  -- scale_screen = 0.5, target_h = align(1080) = 1056
  -- target_w = align(1056 * 1.777) = align(1877) = 1856
  lu.assertTrue(tw <= 1920)
  lu.assertTrue(th <= 1080)
  lu.assertEquals(th, 1056)
  lu.assertEquals(tw, 1856) -- Width derived from aligned height
  lu.assertAlmostEquals(scale, 1056/2160, 0.01) -- ~0.489
end

-- ============================================================================
-- TestBoundaryConditions - Alignment and edge cases
-- ============================================================================

TestBoundaryConditions = {}

function TestBoundaryConditions:test_alignment_does_not_exceed_screen()
  -- Scenario: Calculated width is 2550.
  -- Align(2550, 32) -> 2528.
  -- Align(2550 + scale, 32) might jump to 2560.
  -- We want to ensure we never accidentally return 2592 (2560+32) on a 2560 screen.

  local opts = {
    enable_vsr = true,
    max_pixels_vsr_on = 99.0, -- Infinite budget
    max_pixels_vsr_off = 99.0,
    min_vsr_mult = 1.0
  }

  -- Input perfectly matches screen
  local tw, th = core.calculate_targets(2560, 1440, 2560, 1440, opts)
  lu.assertTrue(tw <= 2560)
  lu.assertTrue(th <= 1440)

  -- Input slightly larger (e.g. overscan crop)
  -- 2561 width should be clamped to 2560 (or aligned down to 2560)
  local tw2, th2 = core.calculate_targets(2561, 1441, 2560, 1440, opts)
  lu.assertTrue(tw2 <= 2560)
  lu.assertTrue(th2 <= 1440)
end

function TestBoundaryConditions:test_width_limited_downscale_maximizes_width()
  -- REGRESSION TEST: Real scenario from mpv log
  -- Source: 3840x1608 (ultrawide 4K after crop)
  -- Screen: 2560x1440
  -- Budget: 3.0 MP (allows ~2700x1130 but screen limits first)
  --
  -- Width is limiting: scale_w = 2560/3840 = 0.667
  -- Height allows more: scale_h = 1440/1608 = 0.895
  --
  -- BUG: Old code applies 0.667 scale to HEIGHT first:
  --   target_h = align(1608 * 0.667) = align(1072) = 1056
  --   target_w = align(1056 * 2.388) = align(2522) = 2496  <-- WRONG!
  --
  -- EXPECTED: When width-limited, set width to screen first:
  --   target_w = align(2560) = 2560
  --   target_h = align(2560 / 2.388) = align(1072) = 1056

  local opts = {
    enable_vsr = false,
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 3.0,  -- 3 MP budget
    min_vsr_mult = 1.5
  }

  local tw, th, vsr, scale = core.calculate_targets(3840, 1608, 2560, 1440, opts)

  -- Width MUST reach screen width (aligned) when width is the limiting factor
  lu.assertEquals(tw, 2560, "Width-limited downscale should maximize to screen width")
  lu.assertEquals(th, 1056)  -- Height derived from width, maintaining AR
  lu.assertTrue(tw * th <= 3000000)  -- Must still fit budget
end
