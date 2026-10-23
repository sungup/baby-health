# baby-health (아기 건강)

아기의 **접종 · 병원 방문 · 투약 · 체온** 기록을 모아 보고, 규칙 기반 점검과 LLM 검토로 현황을 확인하는 iPhone/iPad 앱입니다.

- SwiftUI + SwiftData, iOS/iPadOS 17.0+
- 프로젝트는 [XcodeGen](https://github.com/yonaskolb/XcodeGen)으로 생성합니다 (`project.yml`이 원본).

## 시작하기 (맥)

```bash
brew install xcodegen
xcodegen generate
open BabyHealth.xcodeproj
```

Xcode의 Signing & Capabilities에서 Team을 선택한 뒤 실행합니다.
파일을 추가/삭제하거나 `project.yml`을 바꿨다면 `xcodegen generate`를 다시 실행하세요.

## 기능

- 아기 등록 / 수정 / 삭제, 여러 아기 중 선택 (각 탭 왼쪽 위 메뉴)
- 요약: 아기 정보, 최근 체온, 진행 중인 투약(오늘 복용 현황), 다음 접종, 최근 병원 방문
- 체온 입력, 처방(약 이름·용량·횟수·처방일·처방 병원·기간) 입력, 투약 기록 입력
- 접종 / 병원 방문 기록

## LLM 점검

요약 탭의 열쇠 버튼에서 Anthropic API 키를 입력하면 Keychain에 저장되고, "지금 점검하기"에서 사용됩니다.
키가 없어도 규칙 기반 점검(접종 지연, 최근 24시간 발열, 오늘 복용 횟수)은 동작합니다.
LLM에는 월령과 기록만 전송하며 이름·생년월일·병원명은 보내지 않습니다.

> 이 앱의 점검 결과는 참고용이며 의료진 상담을 대체하지 않습니다.

## 구조

```
BabyHealth/
  App/        앱 진입점, 루트 뷰
  Models/     SwiftData 모델
  Services/   스냅샷, 규칙, 프롬프트, LLM/Keychain
  Views/      화면
BabyHealthTests/
project.yml
```

자세한 작업 규칙은 [CLAUDE.md](CLAUDE.md)를 참고하세요.
