import subprocess, os
SRC='/tmp/baby/mono.wav'
OUT='/home/user/flutter_app/assets/audio'
# ASR segment boundaries (sentence start-end)
segs = {
  'prepare' : (0.18, 0.74),
  'startWork': (1.30, 2.12),
  'startRest': (2.72, 3.58),
  'setRest'  : (4.24, 5.42),
  'lastRound': (6.10, 7.20),
  'finish'   : (7.88, 9.88),
}
PAD=0.06
for key,(a,b) in segs.items():
    s=max(0.0,a-PAD); e=b+PAD
    out=f'{OUT}/st_cute_{key}.wav'
    subprocess.run(['ffmpeg','-v','error','-y','-i',SRC,'-ss',f'{s:.3f}','-to',f'{e:.3f}',
        '-af','afade=t=in:st=0:d=0.006,afade=t=out:st=%.3f:d=0.010'%(e-s-0.010),
        '-ar','22050','-ac','1','-c:a','pcm_s16le',out],check=True)
    print(key, f'{e-s:.2f}s')
