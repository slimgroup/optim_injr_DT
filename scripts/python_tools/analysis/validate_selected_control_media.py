#!/usr/bin/env python3
"""Decode the four selected-control movies on a Slurm compute node."""
from pathlib import Path
import argparse, json, subprocess, os
import imageio_ffmpeg
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('root',type=Path)
parser.add_argument('--frames',type=int,default=1200)
args=parser.parse_args()
root=args.root
assert len(list(root.glob('*.mp4')))==4, 'Expected exactly four selected-control movies'
checks=[]
for path in sorted(root.glob('*.mp4')):
 cmd=[imageio_ffmpeg.get_ffmpeg_exe(),'-hide_banner','-loglevel','error','-threads','2','-i',str(path),'-an','-f','null','-','-progress','pipe:1','-nostats']
 p=subprocess.run(cmd,capture_output=True,text=True)
 progress=dict(line.split('=',1) for line in p.stdout.splitlines() if '=' in line)
 assert p.returncode==0 and int(progress['frame'])==args.frames and progress['progress']=='end',(path,p.stderr,progress)
 checks.append({'file':path.name,'returncode':p.returncode,'decoded_frames':int(progress['frame']),'decoder_errors':p.stderr,'progress':progress})
with (root/'decode_validation.json').open('x') as f:
 json.dump({'validation_slurm_job_id':os.environ.get('SLURM_JOB_ID'),'checks':checks},f,indent=2)
print(f'All four movies decoded successfully; {args.frames} frames each.')
