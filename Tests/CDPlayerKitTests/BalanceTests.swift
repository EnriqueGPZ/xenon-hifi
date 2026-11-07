import Testing
@testable import CDPlayerKit

struct BalanceTests {
    @Test func centreKeepsBothSidesFull() {
        #expect(Balance.gains(0) == (1, 1))
        #expect(Balance.label(0) == "CENTRO")
    }

    @Test func turningFadesOnlyTheOtherSide() {
        #expect(Balance.gains(-0.5) == (1, 0.5))
        #expect(Balance.gains(1) == (0, 1))
        #expect(Balance.label(-0.2) == "L 20")
        #expect(Balance.label(1) == "R 100")
    }

    @Test func clicksIntoTheCentreAndStopsAtTheEnds() {
        #expect(Balance.clamp(0.03) == 0)
        #expect(Balance.clamp(-0.05) == -0.05)
        #expect(Balance.clamp(1.4) == 1)
        #expect(Balance.clamp(-3) == -1)
    }
}
