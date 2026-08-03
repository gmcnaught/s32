#!/usr/bin/env python3
"""Compare aligned MAME and RTL SegaSonic frame captures."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops


def compare(
    reference_path: Path,
    rtl_path: Path,
    diff_path: Path | None,
    y_offset: int = 0,
) -> dict:
    reference = Image.open(reference_path).convert("RGB")
    rtl = Image.open(rtl_path).convert("RGB")
    rtl_original_size = rtl.size
    rtl_right_padding_pixels = 0
    if reference.size != rtl.size:
        # The RTL diagnostic always writes a 416-pixel PPM.  In SegaSonic's
        # 320-wide video mode it appends black columns after active video,
        # while MAME changes the PNG width to 320.  Accept only that explicit,
        # all-black right padding; any other geometry mismatch remains an
        # error rather than being silently rescaled or cropped.
        if (
            reference.height == rtl.height
            and reference.width < rtl.width
            and ImageChops.difference(
                rtl.crop((reference.width, 0, rtl.width, rtl.height)),
                Image.new(
                    "RGB",
                    (rtl.width - reference.width, rtl.height),
                    "black",
                ),
            ).getbbox()
            is None
        ):
            rtl_right_padding_pixels = rtl.width - reference.width
            rtl = rtl.crop((0, 0, reference.width, reference.height))
        else:
            raise ValueError(
                f"frame sizes differ: MAME={reference.size}, RTL={rtl.size}"
            )

    if y_offset:
        aligned = Image.new("RGB", reference.size)
        aligned.paste(reference, (0, y_offset))
        reference = aligned

    delta = ImageChops.difference(reference, rtl)
    bbox = delta.getbbox()
    differing = 0
    total_abs_error = 0
    max_channel_error = 0
    raw_delta = delta.tobytes()
    for index in range(0, len(raw_delta), 3):
        pixel = raw_delta[index : index + 3]
        if pixel != b"\x00\x00\x00":
            differing += 1
        total_abs_error += sum(pixel)
        max_channel_error = max(max_channel_error, *pixel)

    if diff_path is not None:
        diff_path.parent.mkdir(parents=True, exist_ok=True)
        # Brighten small errors while preserving exact-zero pixels as black.
        delta.point(lambda value: min(255, value * 4)).save(diff_path)

    width, height = reference.size
    pixels = width * height
    return {
        "mame": str(reference_path),
        "rtl": str(rtl_path),
        "size": [width, height],
        "rtl_original_size": list(rtl_original_size),
        "rtl_right_padding_pixels": rtl_right_padding_pixels,
        "mame_y_offset": y_offset,
        "pixels": pixels,
        "differing_pixels": differing,
        "differing_percent": round(100.0 * differing / pixels, 6),
        "mean_absolute_channel_error": round(
            total_abs_error / (pixels * 3), 6
        ),
        "max_channel_error": max_channel_error,
        "difference_bbox": list(bbox) if bbox is not None else None,
        "exact_match": bbox is None,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mame", type=Path, help="MAME PNG reference")
    parser.add_argument("rtl", type=Path, help="Verilator PPM/PNG capture")
    parser.add_argument("--diff", type=Path, help="write an amplified diff PNG")
    parser.add_argument(
        "--y-offset",
        type=int,
        default=0,
        help="shift the MAME image vertically before comparison",
    )
    args = parser.parse_args()
    result = compare(args.mame, args.rtl, args.diff, args.y_offset)
    print(json.dumps(result, indent=2))
    return 0 if result["exact_match"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
