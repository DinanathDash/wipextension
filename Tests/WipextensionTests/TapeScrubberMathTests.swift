//
//  TapeScrubberMathTests.swift
//  WipextensionTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Wipextension

@Suite("Tape Scrubber Math & Layout Tests")
struct TapeScrubberMathTests {
    @Test("TimerTapeScrubber static height matches compact and solo expectations")
    func staticHeightCalculation() {
        let compactHeight = TimerTapeScrubber.height(compact: true)
        let soloHeight = TimerTapeScrubber.height(compact: false)

        #expect(compactHeight > 0)
        #expect(soloHeight > compactHeight)
        // Solo has larger tick height (20 vs 15) and font size
        #expect(soloHeight >= 40)
    }

    @Test("Elastic overscroll clamping dampens movement asymptotically toward cap of 6")
    func elasticClampOverscroll() {
        let lower: CGFloat = 1
        let upper: CGFloat = 30
        let cap: CGFloat = 6

        func elasticClamp(_ raw: CGFloat) -> CGFloat {
            if raw < lower {
                let pull = lower - raw
                return lower - cap * (1 - 1 / (1 + pull * 0.25 / cap))
            }
            if raw > upper {
                let pull = raw - upper
                return upper + cap * (1 - 1 / (1 + pull * 0.25 / cap))
            }
            return raw
        }

        // Within bounds: unchanged
        #expect(elasticClamp(1) == 1)
        #expect(elasticClamp(15) == 15)
        #expect(elasticClamp(30) == 30)

        // Overscroll below lower: damped, never less than lower - cap
        let below = elasticClamp(-100)
        #expect(below < lower)
        #expect(below > lower - cap)

        // Overscroll above upper: damped, never greater than upper + cap
        let above = elasticClamp(100)
        #expect(above > upper)
        #expect(above < upper + cap)
    }

    @Test("Continuous tape position rounding maps accurately to integer minutes")
    func continuousValueRounding() {
        func roundToMinute(_ value: CGFloat, minVal: Int = 1, maxVal: Int = 30) -> Int {
            min(max(Int(value.rounded()), minVal), maxVal)
        }

        #expect(roundToMinute(0.4) == 1)
        #expect(roundToMinute(1.2) == 1)
        #expect(roundToMinute(1.6) == 2)
        #expect(roundToMinute(14.8) == 15)
        #expect(roundToMinute(29.6) == 30)
        #expect(roundToMinute(35.0) == 30)
    }
}
