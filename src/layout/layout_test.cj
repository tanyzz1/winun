package winun.layout

import std.unittest.*
import std.unittest.testmacro.*
import winun.domain.*

@Test
func testGridTwoColumns() {
    let spec = LayoutSpec()
    spec.kind = LayoutKind.Grid
    spec.columns = 2
    spec.rows = 1
    spec.gap = 0
    spec.margins = Margins()
    let area = Rect(left: 0, top: 0, right: 1000, bottom: 500)
    let ps = solve([WindowId(value: 1), WindowId(value: 2)], spec, area)
    @Expect(ps.size, 2)
    @Expect(ps[0].rect.left, 0)
    @Expect(ps[0].rect.right, 500)
    @Expect(ps[1].rect.left, 500)
    @Expect(ps[1].rect.right, 1000)
    @Expect(ps[0].rect.bottom, 500)
}

@Test
func testGridGapAndMargins() {
    let spec = LayoutSpec()
    spec.kind = LayoutKind.Grid
    spec.columns = 2
    spec.rows = 1
    spec.gap = 20
    spec.margins = Margins(left: 10, top: 10, right: 10, bottom: 10)
    let area = Rect(left: 0, top: 0, right: 1000, bottom: 520)
    let ps = solve([WindowId(value: 1), WindowId(value: 2)], spec, area)
    @Expect(ps[0].rect.left, 10)
    @Expect(ps[0].rect.right, 490)
    @Expect(ps[1].rect.left, 510)
    @Expect(ps[1].rect.right, 990)
    @Expect(ps[0].rect.top, 10)
    @Expect(ps[0].rect.bottom, 510)
}

@Test
func testRatioSplit() {
    let spec = LayoutSpec()
    spec.kind = LayoutKind.Ratio
    spec.ratios = [0.7, 0.3]
    spec.gap = 0
    let area = Rect(left: 0, top: 0, right: 1000, bottom: 400)
    let ps = solve([WindowId(value: 1), WindowId(value: 2)], spec, area)
    @Expect(ps[0].rect.right, 700)
    @Expect(ps[1].rect.left, 700)
    @Expect(ps[1].rect.right, 1000)
}

@Test
func testAnchorLeftHalf() {
    let spec = LayoutSpec()
    spec.kind = LayoutKind.Anchor
    spec.anchor = AnchorKind.Left
    spec.sizePercent = Some(Size(width: 50, height: 100))
    let area = Rect(left: 0, top: 0, right: 1000, bottom: 600)
    let ps = solve([WindowId(value: 7)], spec, area)
    @Expect(ps.size, 1)
    @Expect(ps[0].rect.left, 0)
    @Expect(ps[0].rect.right, 500)
    @Expect(ps[0].rect.bottom, 600)
}

@Test
func testAbsoluteCells() {
    let spec = LayoutSpec()
    spec.kind = LayoutKind.Absolute
    spec.cells = [Rect(left: 0, top: 0, right: 50, bottom: 50), Rect(left: 50, top: 50, right: 100, bottom: 100)]
    let area = Rect(left: 0, top: 0, right: 1000, bottom: 1000)
    let ps = solve([WindowId(value: 1), WindowId(value: 2)], spec, area)
    @Expect(ps[0].rect.right, 500)
    @Expect(ps[1].rect.left, 500)
    @Expect(ps[1].rect.top, 500)
}

@Test
func testOverflowStacksInLastCell() {
    let spec = LayoutSpec()
    spec.kind = LayoutKind.Grid
    spec.columns = 1
    spec.rows = 1
    spec.gap = 0
    spec.overflowOffset = 30
    let area = Rect(left: 0, top: 0, right: 800, bottom: 600)
    let ps = solve([WindowId(value: 1), WindowId(value: 2), WindowId(value: 3)], spec, area)
    @Expect(ps.size, 3)
    @Expect(ps[1].rect.left, 30)
    @Expect(ps[2].rect.left, 60)
}

@Test
func testEmptyWindows() {
    let spec = LayoutSpec()
    let ps = solve(Array<WindowId>(), spec, Rect(left: 0, top: 0, right: 100, bottom: 100))
    @Expect(ps.size, 0)
}
