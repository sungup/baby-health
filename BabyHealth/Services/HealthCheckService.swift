import Foundation

struct HealthCheckResult {
    let findings: [HealthFinding]
    let llmReview: String?
    let llmError: String?
}

/// 규칙 기반 점검은 항상 수행하고, LLM 클라이언트가 있으면 추가 검토를 요청한다.
/// LLM 호출이 실패해도 규칙 기반 결과는 그대로 돌려준다.
struct HealthCheckService {
    let client: LLMClient?

    func run(snapshot: HealthSnapshot) async -> HealthCheckResult {
        let findings = HealthRules.findings(for: snapshot)

        guard let client else {
            return HealthCheckResult(findings: findings, llmReview: nil, llmError: LLMError.missingAPIKey.errorDescription)
        }

        do {
            let review = try await client.complete(
                system: HealthSummaryBuilder.systemPrompt,
                user: HealthSummaryBuilder.userPrompt(for: snapshot)
            )
            return HealthCheckResult(findings: findings, llmReview: review, llmError: nil)
        } catch {
            return HealthCheckResult(findings: findings, llmReview: nil, llmError: error.localizedDescription)
        }
    }
}
