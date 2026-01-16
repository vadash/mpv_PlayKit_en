"""
rife_processor.py - Optimized RIFE pipeline
"""

import os
import fractions
import vapoursynth as vs
from k7sfunc._external import vsmlrt

core = vs.core

def process(
    clip: vs.VideoNode,
    crop_l: int,
    crop_t: int,
    crop_w: int,
    crop_h: int,
    target_w: int,
    target_h: int,
    model: int,
    gpu_id: int,
    gpu_t: int,
) -> vs.VideoNode:
    
    # 1. Apply Crop
    # We do this first so we don't process pixels we are about to throw away
    if crop_w > 0 and crop_h > 0:
        if crop_w != clip.width or crop_h != clip.height:
            clip = core.std.CropRel(clip, left=crop_l, top=crop_t, right=clip.width - crop_w - crop_l, bottom=clip.height - crop_h - crop_t)

    # 2. Prepare for AI (Single Pass: Resize + Format Convert)
    # RIFE requires RGB input (RGBH is best for TensorRT FP16)
    
    # Detect Color Matrix (Keep 709 as safe default)
    matrix_val = clip.get_frame(0).props.get("_Matrix", 1)
    matrix_str = {1: "709", 5: "470bg", 6: "601"}.get(matrix_val, "709")

    # Determine final dimensions
    # If target_w is 0 (native res), use current width
    dest_w = target_w if target_w > 0 else clip.width
    dest_h = target_h if target_h > 0 else clip.height

    # ONE RESIZE TO RULE THEM ALL:
    # Changes Size AND Format (YUV -> RGBH) in one optimized step
    clip_rgb = core.resize.Spline36(
        clip, 
        width=dest_w, 
        height=dest_h, 
        format=vs.RGBH, 
        matrix_in_s=matrix_str
    )

    # 3. Model Path Logic
    plg_dir = os.path.dirname(core.trt.Version()["path"]).decode()
    mdl_pname = "rife_v2/"
    mdl_fname = {
        4151: "rife_v4.15_lite",
        4221: "rife_v4.22_lite",
    }.get(model, "rife_v4.15")
    mdl_pth = plg_dir + "/models/" + mdl_pname + mdl_fname + ".onnx"

    if not os.path.exists(mdl_pth):
        raise vs.Error(f"RIFE model not found: {mdl_pth}")

    # 4. RIFE Execution
    clip_rife = vsmlrt.RIFE(
        clip=clip_rgb,
        multi=fractions.Fraction(2, 1),
        scale=1,
        model=model,
        ensemble=False,
        _implementation=2,
        video_player=True,
        backend=vsmlrt.BackendV2.TRT(
            num_streams=gpu_t,
            int8=False,
            fp16=True,
            output_format=1,
            workspace=256,
            use_cuda_graph=True,
            use_cublas=True,
            use_cudnn=True,
            static_shape=True,
            min_shapes=[0, 0],
            opt_shapes=None,
            max_shapes=None,
            device_id=gpu_id,
            short_path=True
        )
    )

    # 5. Output Conversion (RGBH -> YUV420P10)
    # We must convert back to YUV for MPV/Display:
    # Nvidia VSR requires YUV (NV12/P010) input and solves banding
    clip_out = core.resize.Spline36(
        clip=clip_rife,
        format=vs.YUV420P10,
        matrix_s=matrix_str
    )

    return clip_out
