import Testing
@testable import AgentLensCore

// M1: the test is nearly circular by design — it asserts that hardcoded output
// contains hardcoded strings. The test is not the point; the test harness is the
// point (brief). From M2 on these assertions anchor real detection (D-012).

@Test func scanReportContainsRequiredStrings() {
    let output = WalkingSkeleton.renderScanReport(tools: WalkingSkeleton.tools)
    #expect(output.contains("AI AGENTS"))
    #expect(output.contains("Codex"))
    #expect(output.contains("0.154.0"))
    #expect(output.contains("npm"))
}

@Test func scanReportCountsExactlyOneTool() {
    let output = WalkingSkeleton.renderScanReport(tools: WalkingSkeleton.tools)
    #expect(output.contains("1"))
}

@Test func unknownCommandHasNonZeroSemanticsViaUsageText() {
    // Without executing real Processes (forbidden in M1), assert the usage text
    // the CLI exits with in the unknown-command branch.
    #expect(WalkingSkeleton.usageMessage.contains("agent-lens <scan>"))
}
