#!/usr/bin/env python3
"""
Create videos from existing frames using imageio
"""
import os
import glob
import argparse
import imageio

def create_video_from_frames(frames_dir, output_video, fps=10):
    """Create video from PNG frames"""
    frame_files = sorted(glob.glob(os.path.join(frames_dir, "frame_*.png")))
    if not frame_files:
        print(f"No frames found in {frames_dir}")
        return False
    
    print(f"Found {len(frame_files)} frames in {frames_dir}")
    print(f"Creating video: {output_video}")
    
    # Read frames and write video
    with imageio.get_writer(output_video, fps=fps) as writer:
        for i, frame_file in enumerate(frame_files):
            if (i + 1) % 10 == 0:
                print(f"  Processing frame {i + 1}/{len(frame_files)}")
            image = imageio.imread(frame_file)
            writer.append_data(image)
    
    print(f"Video created: {output_video}")
    return True

def create_gif_from_frames(frames_dir, output_gif, fps=4):
    """Create GIF from PNG frames"""
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

def parse_args():
    parser = argparse.ArgumentParser(description="Create videos from saved frame folders.")
    parser.add_argument(
        "directories",
        nargs="*",
        help="Optional specific output directories to process. If omitted, scan all known DT_control video folders.",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    base_dir = "/storage/coda1/p-fherrmann9/0/hli853/optim_injr_DT/plots/DT_control"

    if args.directories:
        target_dirs = [os.path.abspath(d) for d in args.directories if os.path.isdir(d)]
        video_dirs = [
            d for d in target_dirs
            if os.path.basename(d).startswith(("videos_5cases_", "videos_stat3cases_"))
        ]
        perm_dirs = [
            d for d in target_dirs
            if os.path.basename(d).startswith("video_128perm_")
        ]
    else:
        video_dirs = [
            d for pattern in ("videos_5cases_*", "videos_stat3cases_*")
            for d in glob.glob(os.path.join(base_dir, pattern))
            if os.path.isdir(d)
        ]
        perm_dirs = [
            d for d in glob.glob(os.path.join(base_dir, "video_128perm_*"))
            if os.path.isdir(d)
        ]
    
    print("=" * 60)
    print("Creating videos from existing frames")
    print("=" * 60)
    
    # Process control-case video folders
    for video_dir in video_dirs:
        print(f"\nProcessing: {video_dir}")
        frame_dirs = glob.glob(os.path.join(video_dir, "frames_*"))
        for frames_dir in frame_dirs:
            case_name = os.path.basename(frames_dir).replace("frames_", "")
            output_mp4 = os.path.join(video_dir, f"{case_name}.mp4")
            output_gif = os.path.join(video_dir, f"{case_name}.gif")
            
            # Try MP4 first, fall back to GIF
            try:
                create_video_from_frames(frames_dir, output_mp4, fps=10)
            except Exception as e:
                print(f"MP4 failed: {e}")
                try:
                    create_gif_from_frames(frames_dir, output_gif, fps=10)
                except Exception as e2:
                    print(f"GIF also failed: {e2}")
    
    # Process 128-perm videos
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
