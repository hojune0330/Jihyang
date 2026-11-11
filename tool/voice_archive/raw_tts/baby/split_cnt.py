import subprocess
SRC='/tmp/baby/count.wav'; OUT='/home/user/flutter_app/assets/audio'
# ASR word spans; widen slightly to keep the consonant attack
words = {5:(0.08,0.52), 4:(1.08,1.38), 3:(2.10,2.38), 2:(3.00,3.22), 1:(3.80,4.06)}
PRE=0.05; POST=0.09
for n,(a,b) in words.items():
    s=max(0.0,a-PRE); e=b+POST
    out=f'{OUT}/c_cute_{n}.wav'
    subprocess.run(['ffmpeg','-v','error','-y','-i',SRC,'-ss',f'{s:.3f}','-to',f'{e:.3f}',
      '-af','afade=t=in:st=0:d=0.005,afade=t=out:st=%.3f:d=0.012'%(e-s-0.012),
      '-ar','22050','-ac','1','-c:a','pcm_s16le',out],check=True)
    print(n, round(e-s,3))
