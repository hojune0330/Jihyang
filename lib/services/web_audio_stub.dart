/// 웹이 아닌 플랫폼용 스텁.
///
/// 모바일/데스크톱에서는 audioplayers 경로를 그대로 쓰므로
/// 이 클래스의 모든 메서드는 "지원 안 함" 만 알려준다.
class WebAudio {
  const WebAudio();

  /// 웹 브리지를 쓸 수 있는가
  bool get available => false;

  /// 오디오 잠금이 해제됐는가
  bool get unlocked => false;

  /// 사용자 제스처에서 호출 — 잠금 해제
  Future<bool> unlock() async => false;

  /// 자산 미리 받기 + 디코딩
  Future<int> preload(List<String> assets) async => 0;

  /// 이미 디코딩되어 바로 재생 가능한가
  bool isReady(String asset) => false;

  /// 재생. 성공 여부를 돌려준다.
  bool play(
    String asset, {
    required String role,
    double volume = 1.0,
    int offsetMs = 0,
    int whenMs = 0,
    bool interrupt = true,
  }) => false;

  /// 특정 역할의 소리를 멈춘다
  void stopRole(String role) {}

  /// 전부 멈춘다
  void stopAll() {}

  /// 진단용 상태
  Map<String, Object?> status() => const {'supported': false};
}
