import subprocess
OUT='/home/user/flutter_app/assets/audio'

def cut(src, s, e, out, fade_in=0.006, fade_out=0.012):
    dur = e - s
    subprocess.run(['ffmpeg','-v','error','-y','-i',src,
        '-ss',f'{s:.3f}','-to',f'{e:.3f}',
        '-af',f'afade=t=in:st=0:d={fade_in},afade=t=out:st={dur-fade_out:.3f}:d={fade_out}',
        '-ar','22050','-ac','1','-c:a','pcm_s16le',out], check=True)

# --- 아기 상태 안내 ---
PAD=0.06
baby = {
  'prepare' : (0.18, 0.74),
  'startWork': (1.30, 2.12),
  'startRest': (2.72, 3.58),
  'setRest'  : (4.24, 5.42),
  'lastRound': (6.10, 7.20),
  'finish'   : (7.88, 9.88),
}
for k,(a,b) in baby.items():
    cut('/tmp/baby/mono_backup.wav', max(0,a-PAD), b+PAD, f'{OUT}/st_cute_{k}.wav')
    print('st_cute_'+k)

# --- 아기 카운트다운 ---
cnt = {5:(0.08,0.52), 4:(1.08,1.38), 3:(2.10,2.38), 2:(3.00,3.22), 1:(3.80,4.06)}
PRE, POST = 0.05, 0.09
for n,(a,b) in cnt.items():
    cut('/tmp/baby/count_backup.wav', max(0,a-PRE), b+POST, f'{OUT}/c_cute_{n}.wav', 0.005, 0.012)
    print('c_cute_'+str(n))
