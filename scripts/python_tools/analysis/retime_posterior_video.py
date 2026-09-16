#!/usr/bin/env python3
"""Losslessly retime the approved compact posterior MP4 to two-thirds duration.

Only packet timestamps/durations change; no plotting, sample selection, image
processing or H.264 re-encoding. Run the full decoding checks on Slurm.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'plots/posterior_sample_videos/k1_compact_absolute_20260915_v1/with_absolute_pressure/posterior_samples_k1_36s.mp4'
EXPECTED_SHA = '2fb0ec80f6011ad8937db75ebe7b1e5c66226b6de4d62c3e1fdf7617eb78daf7'
EXPECTED_FRAMES = 896
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def metadata(path):
    stream = imageio_ffmpeg.read_frames(str(path), input_params=['-threads', '2'])
    result = next(stream)
    stream.close()
    return result


def video_hash(path, decode):
    command = [FFMPEG, '-nostdin', '-hide_banner', '-loglevel', 'error', '-threads', '2',
               '-i', str(path), '-map', '0:v:0', '-an']
    if decode:
        command += ['-c:v', 'rawvideo', '-pix_fmt', 'yuv420p', '-threads', '2',
                    '-fps_mode', 'passthrough', '-progress', 'pipe:2', '-nostats']
    else:
        command += ['-c:v', 'copy']
    command += ['-f', 'hash', '-hash', 'sha256', '-']
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    count = None
    if decode:
        progress = dict(line.split('=', 1) for line in result.stderr.splitlines() if '=' in line)
        assert progress['progress'] == 'end', progress
        count = int(progress['frame'])
        assert count == EXPECTED_FRAMES, progress
    assert result.stdout.strip().startswith('SHA256='), result.stdout
    return {'sha256': result.stdout.strip().split('=', 1)[1], 'decoded_frames': count}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not os.environ.get('SLURM_JOB_ID'):
        parser.error('Full video validation must run via sbatch or salloc.')
    assert sha(SOURCE) == EXPECTED_SHA, 'Source differs from the approved compact version.'
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    snapshots = out/'provenance'
    snapshots.mkdir()
    shutil.copyfile(Path(__file__), snapshots/Path(__file__).name)
    destination = out/'posterior_samples_k1_24s.mp4'
    command = [FFMPEG, '-nostdin', '-hide_banner', '-loglevel', 'warning', '-n',
               '-i', str(SOURCE), '-map', '0:v:0', '-an', '-c:v', 'copy',
               '-bsf:v', 'setts=pts=PTS*2/3:dts=DTS*2/3:duration=DURATION*2/3',
               '-movflags', '+faststart', str(destination)]
    subprocess.run(command, check=True)
    before, after = metadata(SOURCE), metadata(destination)
    assert before['duration'] == 35.84, before
    assert abs(after['duration'] - before['duration']*2/3) < 0.02, after
    assert after['size'] == before['size'] == (1920, 1080), after
    assert before['codec'] == after['codec'] == 'h264', after
    assert before['pix_fmt'] == after['pix_fmt'], after
    encoded_before, encoded_after = video_hash(SOURCE, False), video_hash(destination, False)
    assert encoded_before == encoded_after, 'Compressed H.264 picture data changed.'
    print('Compressed video data identical; checking every decoded frame.', flush=True)
    pixels_before, pixels_after = video_hash(SOURCE, True), video_hash(destination, True)
    assert pixels_before == pixels_after, 'Decoded frames or frame count changed.'
    assert sha(SOURCE) == EXPECTED_SHA, 'Original input changed.'
    record = {'slurm_job_id': os.environ.get('SLURM_JOB_ID'), 'source': str(SOURCE.relative_to(ROOT)),
              'source_sha256': EXPECTED_SHA, 'output': destination.name, 'output_sha256': sha(destination),
              'speed_multiplier': 1.5, 'duration_multiplier': '2/3',
              'target_duration_seconds': 35.84*2/3, 'metadata_before': before, 'metadata_after': after,
              'compressed_video_payload_identical': True, 'compressed_video_payload_hash': encoded_after,
              'all_decoded_frames_pixel_identical': True, 'decoded_video_hash': pixels_after,
              'sample_ids': list(range(1, 129)), 'command': command,
              'scope': 'Playback timestamps and packet durations only; no frame drops, re-encoding, content or layout changes.'}
    with (out/'retiming_verification.json').open('x') as f:
        json.dump(record, f, indent=2)
        f.write('\n')
    shutil.copyfile(SOURCE.parent/'poster.png', out/'poster.png')
    with (out/'README.md').open('x') as f:
        f.write('# Posterior video at 1.5x speed\n\n'
                '[MP4, approximately 23.89 seconds](posterior_samples_k1_24s.mp4) · [Unchanged poster](poster.png)\n\n'
                'The approved compact three-row video is accelerated from 35.84 seconds to two-thirds its duration. '
                'All 896 video frames (all 128 posterior samples) are retained in the same order. '
                'The compressed H.264 payload and every decoded frame are identical to the source; only timing changes. '
                'Layout, labels, sample pairing and color scales remain as approved. The original video is preserved.\n\n'
                'Full checks and source/output hashes: retiming_verification.json. Original data provenance remains in '
                '../k1_compact_absolute_20260915_v1/provenance.json.\n')
    print(f'COMPLETE: {destination}; duration={after["duration"]}; frames={pixels_after["decoded_frames"]}', flush=True)


if __name__ == '__main__':
    main()
