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
- **처방전 인식**: 투약 탭 `+` → "처방전 촬영·인식". 카메라(문서 스캐너)로 촬영하거나 사진을 골라 Gemini로 분석하고,
  약마다 다른 복용 시점·횟수·일수를 검토/수정한 뒤 저장합니다. (이미지는 앱에 저장하지 않음)
- **모델 선택**: 요약 탭 열쇠 버튼(연동 설정)에서 처방전 인식(Gemini)·현황 점검(Anthropic) 모델을 따로 고르고,
  "사용 가능한 모델 불러오기"로 현재 계정/키로 쓸 수 있는 목록을 조회하거나 모델 ID를 직접 입력할 수 있습니다.

- **식사 시간 · 알람**: 요약 탭 종 버튼(알람 설정)에서 아침/점심/저녁/취침 시간을 입력하고 식사 알람·투약 알람을 켜고 끕니다.
  알람은 처방의 **복용 기간 동안에만** 울리며, 투약 알람에는 시간대별 약 이름·용량과 다음 투약이 함께 표시됩니다.
- **복용 스케줄**: 처방전의 "아침·저녁 식후 30분" 같은 문구를 해석해 식사 기준 슬롯으로 바꿉니다. 식사 기준이 없으면
  **최초 투약 시간**(기본: 지금 시각을 10분 단위로 올림)과 간격으로 정시 알람을 만듭니다. "필요 시" 약은 알람이 없습니다.
- **투약 시작 시점 보정**: 처방일이 오늘보다 앞서면 "처방일부터 / 오늘부터 / 직접 선택"으로 실제 투약 시작 시점을 고릅니다.
  종료일은 실제 시작일 기준으로 계산되고, 지난 투약을 복용 기록으로 채울지 선택할 수 있습니다.
- **공유**: 알림의 "공유" 동작, 요약 탭 "오늘의 투약 일정", 알람 설정의 미리보기에서 투약 정보를 다른 앱으로 공유합니다.
  (iOS 제한으로 가까운 알람 최대 60개까지만 예약하고, 앱을 열 때마다 다시 채웁니다.)

## Google 계정 연동 설정 (처방전 인식)

1. [Google Cloud Console](https://console.cloud.google.com)에서 프로젝트를 만들고 **Generative Language API**를 사용 설정합니다.
2. **Google Auth Platform**에서 OAuth 동의 화면을 구성합니다. 사용자 유형은 *외부*, 본인 계정을 **테스트 사용자**로 추가합니다.
   (테스트 모드에서는 "확인되지 않은 앱" 경고가 뜨는데 정상입니다.)
3. **클라이언트 만들기** → 유형 **iOS**, 번들 ID `com.sungup.babyhealth` → 발급된 **클라이언트 ID**를 복사합니다.
4. 앱의 연동 설정에서 클라이언트 ID(선택: Cloud 프로젝트 ID)를 입력하고 **Google 계정 연결**을 누릅니다.

> 요청 scope는 `generative-language.retriever`(Gemini API OAuth 문서 기준)이며 `GoogleOAuthConfig.defaultScopes`에서 바꿀 수 있습니다.
> 이 scope로 `generateContent`가 허용되는지는 계정/프로젝트 설정에 따라 다를 수 있습니다. 403이 나면 **Gemini API 키**를 함께 저장해 두세요.
> 앱은 Google 계정 → API 키 순으로 시도하고, 401/403이면 자동으로 다음 방법으로 넘어갑니다.
>
> 기본 모델/엔드포인트: `gemini-3.8-flash`, `generateContent` (Gemini 문서에서 Legacy로 표시됨 — `GeminiPrescriptionReader`만 바꾸면 Interactions API로 이전 가능).

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
