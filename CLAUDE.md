# 아기 건강 (BabyHealth)

아기의 접종, 병원 방문, 투약, 체온 기록을 모아 보고, LLM으로 현황을 점검·검증하는 iPhone/iPad 앱.

## 환경
- 타깃: iOS/iPadOS 17.0+, SwiftUI + SwiftData, iPhone·iPad 모두 지원
- 프로젝트 생성: **XcodeGen** (`project.yml` 이 원본). `.xcodeproj` 는 커밋하지 않는다.
- 빌드/실행은 **맥에서만** 가능 (Xcode 필요). 클라우드 세션(리눅스)에서는 컴파일 검증이 안 되므로 코드를 작성하되 문법·타입에 특히 주의한다.

## 맥에서 처음 시작하기
```bash
brew install xcodegen
xcodegen generate
open BabyHealth.xcodeproj   # Signing & Capabilities 에서 Team 선택
```
`project.yml` 을 수정하거나 파일을 추가/삭제하면 `xcodegen generate` 를 다시 실행한다.

## 디렉터리 구조
- `BabyHealth/App` — 앱 진입점, 루트 뷰
- `BabyHealth/Models` — SwiftData 모델
- `BabyHealth/Services` — LLM 클라이언트, 검증 로직, Keychain
- `BabyHealth/Views` — 화면
- `BabyHealthTests` — 단위 테스트

## 코딩 규칙
- UI 문자열은 한국어. 코드 식별자와 주석은 영어/한국어 혼용 가능하나 일관되게.
- 뷰에 비즈니스 로직을 넣지 않는다. 검증·요약 로직은 `Services` 에 두고 테스트한다.
- 모델 변경 시 SwiftData 마이그레이션 영향을 먼저 검토한다.
- 새 서비스는 프로토콜로 추상화해 테스트에서 목(mock)으로 교체할 수 있게 한다.

## 보안 / 개인정보 (중요)
- 아기의 건강 정보는 민감한 개인정보다. 로그·크래시 리포트·커밋에 실제 데이터를 넣지 않는다.
- API 키는 코드/저장소에 절대 넣지 않는다. 앱 안에서 입력받아 **Keychain** 에 저장한다.
- LLM으로 보내는 데이터는 필요한 최소 항목만 포함하고, 이름 등 식별 정보는 보내지 않는다 (`HealthSummaryBuilder` 참고).
- LLM 출력은 의료 진단이 아니다. 화면에 "참고용이며 의료진 상담을 대체하지 않습니다" 문구를 항상 표시한다.

## 작업 방식
- 기능별 브랜치(`feature/...`)에서 작업하고, 맥에서 빌드·테스트 확인 후 `main` 에 머지한다.
- 기기를 바꾸기 전에 반드시 커밋·푸시, 시작할 때 pull.
