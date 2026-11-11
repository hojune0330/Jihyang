음성 보관 폴더 (삭제 금지 — 로컬 재생성의 원본)

current_assets/ : 재생성 전 assets/audio/ 의 wav 전체 사본 (이전 버전)
raw_tts/        : 음성 API 가 받은 원본 mp3/wav 와 분할 메타 (/tmp 에서 복사)
                  tts3, tts4, cd5, baby, babyv2 + voice_*_meta.json

재생성 파이프라인은 /tmp 가 아니라 이 폴더를 읽도록 경로를 바꾼다.
음성 API 호출(크레딧 발생)은 이 폴더에 원본이 없을 때만 한다.
