#!/usr/bin/env python3
"""Create videos from existing frames using imageio."""

from __future__ import annotations

import argparse
import glob
import os

import imageio

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DT_CONTROL = os.path.join(REPO_ROOT, "plots", "DT_control")


def create_video_from_frames(frames_dir, output_video, fps=10):
    frame_files = sorted(glob.glob(os.path.join(frames_dir, "frame_*.png")))
    if not frame_files:
        print(f"No frames found in {frames_dir}")
        return False

    print(f"Found {len(frame_files)} frames in {frames_dir}")
    print(f"Creating video: {output_video}")

    with imageio.get_writer(output_video, fps=fps) as writer:
        for i, frame_file in enumerate(frame_files):
            if (i + 1) % 10 == 0:
                print(f"  Processing frame {i + 1}/{len(frame_files)}")
            writer.append_data(imageio.imread(frame_file))

    print(f"Video created: {output_video}")
    return True


def create_gif_from_frames(frames_dir, output_gif, fps=4):
    frame_files = sorted(glob.glob(os.path.join(frames_dir, "frame_*.png")))
    if not frame_files:
        print(f"No frames found in {frames_dir}")
        return False

    print(f"Found {len(frame_files)} frames in {frames_dir}")
    print(f"Creating GIF: {output_gif}")

    images = []
    for i, frame_file in enumerate(frame_files):
        if (i + 1) % 20 == 0:
            print(f"  Loading frame {i + 1}/{len(frame_files)}")
        images.append(imageio.imread(frame_file))

    imageio.mimsave(output_gif, images, fps=fps)
    print(f"GIF created: {output_gif}")
    return True


def _glob_dirs(*patterns: str) -> list[str]:
    out: list[str] = []
    for pattern in patterns:
        out.extend(d for d in glob.glob(pattern) if os.path.isdir(d))
    return sorted(set(out))


def discover_video_dirs(base_dir: str) -> list[str]:
    return _glob_dirs(
        os.path.join(base_dir, "videos", "5cases", "videos_5cases_*"),
        os.path.join(base_dir, "videos", "5cases", "videos_stat3cases_*"),
        os.path.join(base_dir, "videos_5cases_*"),
        os.path.join(base_dir, "videos_stat3cases_*"),
    )


def discover_perm_dirs(base_dir: str) -> list[str]:
    return _glob_dirs(
        os.path.join(base_dir, "videos", "128perm", "video_128perm_*"),
        os.path.join(base_dir, "video_128perm_*"),
    )


def parse_args():
    parser = argparse.ArgumentParser(description="Create videos from saved frame folders.")
    parser.add_argument(
        "directories",
        nargs="*",
        help="Optional specific output directories to process. If omitted, scan DT_control video folders.",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    base_dir = DT_CONTROL

    if args.directories:
        target_dirs = [os.path.abspath(d) for d in args.directories if os.path.isdir(d)]
        video_dirs = [
            d for d in target_dirs
            if os.path.basename(d).startswith(("videos_5cases_", "videos_stat3cases_"))
        ]
        perm_dirs = [d for d in target_dirs if os.path.basename(d).startswith("video_128perm_")]
    else:
        video_dirs = discover_video_dirs(base_dir)
        perm_dirs = discover_perm_dirs(base_dir)

    print("=" * 60)
    print("Creating videos from existing frames")
    print("=" * 60)

    for video_dir in video_dirs:
        print(f"\nProcessing: {video_dir}")
        frame_dirs = glob.glob(os.path.join(video_dir, "frames_*"))
        for frames_dir in frame_dirs:
            case_name = os.path.basename(frames_dir).replace("frames_", "")
            output_mp4 = os.path.join(video_dir, f"{case_name}.mp4")
            output_gif = os.path.join(video_dir, f"{case_name}.gif")
            try:
                create_video_from_frames(frames_dir, output_mp4, fps=10)
            except Exception as e:
                print(f"MP4 failed: {e}")
                try:
                    create_gif_from_frames(frames_dir, output_gif, fps=10)
                except Exception as e2:
                    print(f"GIF also failed: {e2}")

    for perm_dir in perm_dirs:
        print(f"\nProcessing: {perm_dir}")
        frames_dir = os.path.join(perm_dir, "frames")
        if os.path.isdir(frames_dir):
            output_mp4 = os.path.join(perm_dir, "128_permeability_samples.mp4")
            output_gif = os.path.join(perm_dir, "128_permeability_samples.gif")
            try:
                create_video_from_frames(frames_dir, output_mp4, fps=4)
            except Exception as e:
                print(f"MP4 failed: {e}")
                try:
                    create_gif_from_frames(frames_dir, output_gif, fps=4)
                except Exception as e2:
                    print(f"GIF also failed: {e2}")

    print("\n" + "=" * 60)
    print("Done!")
    print("=" * 60)


if __name__ == "__main__":
    main()
