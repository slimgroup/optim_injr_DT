#!/usr/bin/env python3
"""Decode the four selected-control movies on a Slurm compute node."""
from pathlib import Path
import json, subprocess, os, sys
import imageio_ffmpeg
root=Path(sys.argv[1])
assert len(list(root.glob('*.mp4')))==4, 'Expected exactly four selected-control movies'
checks=[]
for path in sorted(root.glob('*.mp4')):
 cmd=[imageio_ffmpeg.get_ffmpeg_exe(),'-hide_banner','-loglevel','error','-threads','2','-i',str(path),'-an','-f','null','-','-progress','pipe:1','-nostats']
 p=subprocess.run(cmd,capture_output=True,text=True)
 progress=dict(line.split('=',1) for line in p.stdout.splitlines() if '=' in line)
 assert p.returncode==0 and int(progress['frame'])==1200 and progress['progress']=='end',(path,p.stderr,progress)
 checks.append({'file':path.name,'returncode':p.returncode,'decoded_frames':int(progress['frame']),'decoder_errors':p.stderr,'progress':progress})
with (root/'decode_validation.json').open('x') as f:
 json.dump({'validation_slurm_job_id':os.environ.get('SLURM_JOB_ID'),'checks':checks},f,indent=2)
print('All four movies decoded successfully; 1200 frames each.')
