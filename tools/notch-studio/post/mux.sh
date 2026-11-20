#!/bin/bash
# post/mux.sh <name> <poster-seconds>: out/notch-<name>.mp4 + out/notch-<name>.wav -> out/final-<name>.mp4
# Frame 0 is the poster (what a feed shows before play); the rest of the take follows from frame 1.
set -euo pipefail
cd "$(dirname "$0")/.."
n=$1; p=$2
ffmpeg -v error -y -ss "$p" -i "out/notch-$n.mp4" -frames:v 1 "out/poster-$n.png"
ffmpeg -v error -y -loop 1 -framerate 30 -t 0.0333 -i "out/poster-$n.png" -i "out/notch-$n.mp4" -i "out/notch-$n.wav" \
  -filter_complex "[1:v]trim=start_frame=1,setpts=PTS-STARTPTS[v1];[0:v][v1]concat=n=2:v=1,format=yuv420p[v];[2:a]loudnorm=I=-14:TP=-1.5:LRA=11,alimiter=limit=0.84:level=false[a]" \
  -map "[v]" -map "[a]" -r 30 -c:v libx264 -preset slow -crf 16 -c:a aac -b:a 192k -shortest -movflags +faststart "out/final-$n.mp4"
ffprobe -v error -count_frames -show_entries stream=codec_type,nb_read_frames,duration -of csv=p=0 "out/final-$n.mp4"
