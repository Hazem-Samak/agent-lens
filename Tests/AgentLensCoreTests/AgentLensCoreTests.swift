import Testing
@testable import AgentLensCore

// M0: the only requirement is that tests compile and pass (D-012 — tests are the
// definition of done). Real engine tests arrive with the walking skeleton (M1).

@Test func engineNameIsExposed() {
    #expect(AgentLensCore.engineName == "AgentLensCore")
}
