package winun.layout

import std.collection.*
import winun.domain.*

// 布局解算：纯函数，输入窗口序列 + 布局声明 + 目标工作区，输出每个窗口的目标矩形
public func solve(windows: Array<WindowId>, spec: LayoutSpec, area: Rect): Array<Placement> {
    let out = ArrayList<Placement>()
    if (windows.size == 0) {
        return out.toArray()
    }
    let inner = applyMargins(area, spec.margins)
    if (inner.isEmpty()) {
        return out.toArray()
    }
    let slots = slotsFor(spec, inner, windows.size)
    if (slots.size == 0) {
        return out.toArray()
    }
    for (i in 0..windows.size) {
        var r = slots[if (i < slots.size) { i } else { slots.size - 1 }]
        if (i >= slots.size) {
            let k = Int32(i - slots.size + 1) * spec.overflowOffset
            r = Rect(left: r.left + k, top: r.top + k, right: r.right, bottom: r.bottom)
        }
        out.add(Placement(window: windows[i], rect: r, state: WindowState.Normal))
    }
    return out.toArray()
}

public func slotsFor(spec: LayoutSpec, inner: Rect, count: Int64): ArrayList<Rect> {
    match (spec.kind) {
        case LayoutKind.Grid => gridSlots(spec, inner, count)
        case LayoutKind.Ratio => ratioSlots(spec, inner, count)
        case LayoutKind.Absolute => absoluteSlots(spec, inner)
        case LayoutKind.Anchor => anchorSlots(spec, inner, count)
    }
}

func applyMargins(area: Rect, m: Margins): Rect {
    return Rect(left: area.left + m.left, top: area.top + m.top,
        right: area.right - m.right, bottom: area.bottom - m.bottom)
}

func gridSlots(spec: LayoutSpec, inner: Rect, count: Int64): ArrayList<Rect> {
    let out = ArrayList<Rect>()
    var cols = if (spec.columns > 0) { spec.columns } else { 1 }
    if (cols > count) { cols = count }
    if (cols < 1) { cols = 1 }
    var rows = spec.rows
    if (rows <= 0) {
        rows = (count + cols - 1) / cols
    }
    if (rows < 1) { rows = 1 }
    let gap = spec.gap
    let totalW = inner.width() - gap * Int32(cols - 1)
    let totalH = inner.height() - gap * Int32(rows - 1)
    let cellW = totalW / Int32(cols)
    let cellH = totalH / Int32(rows)
    for (row in 0..rows) {
        for (col in 0..cols) {
            let left = inner.left + (cellW + gap) * Int32(col)
            let top = inner.top + (cellH + gap) * Int32(row)
            out.add(Rect(left: left, top: top, right: left + cellW, bottom: top + cellH))
        }
    }
    return out
}

func ratioSlots(spec: LayoutSpec, inner: Rect, count: Int64): ArrayList<Rect> {
    let out = ArrayList<Rect>()
    let n = if (count > 0) { count } else { 1 }
    let weights = ArrayList<Float64>()
    if (spec.ratios.size >= Int64(n)) {
        for (i in 0..Int64(n)) {
            weights.add(spec.ratios[i])
        }
    } else {
        for (_ in 0..n) {
            weights.add(1.0 / Float64(n))
        }
    }
    var sum: Float64 = 0.0
    for (w in weights) {
        sum = sum + w
    }
    if (sum <= 0.0) {
        sum = Float64(n)
    }
    let gap = spec.gap
    let usable = Float64(inner.width() - gap * Int32(n - 1))
    var x = Float64(inner.left)
    for (i in 0..n) {
        let w = usable * (weights[i] / sum)
        let left = Int32(x)
        let right = if (i == n - 1) { inner.right } else { Int32(x + w) }
        out.add(Rect(left: left, top: inner.top, right: right, bottom: inner.bottom))
        x = x + w + Float64(gap)
    }
    return out
}

func absoluteSlots(spec: LayoutSpec, inner: Rect): ArrayList<Rect> {
    let out = ArrayList<Rect>()
    for (c in spec.cells) {
        let left = inner.left + inner.width() * c.left / 100
        let top = inner.top + inner.height() * c.top / 100
        let right = inner.left + inner.width() * c.right / 100
        let bottom = inner.top + inner.height() * c.bottom / 100
        out.add(Rect(left: left, top: top, right: right, bottom: bottom))
    }
    return out
}

func anchorSlots(spec: LayoutSpec, inner: Rect, count: Int64): ArrayList<Rect> {
    let out = ArrayList<Rect>()
    let s = anchorSize(spec)
    let w = Int32(Int64(inner.width()) * Int64(s.width) / 100)
    let h = Int32(Int64(inner.height()) * Int64(s.height) / 100)
    var left = inner.left
    var top = inner.top
    match (spec.anchor) {
        case AnchorKind.Left => left = inner.left
        case AnchorKind.Right => left = inner.right - w
        case AnchorKind.Top => top = inner.top
        case AnchorKind.Bottom => top = inner.bottom - h
        case AnchorKind.TopLeft =>
            left = inner.left
            top = inner.top
        case AnchorKind.TopRight =>
            left = inner.right - w
            top = inner.top
        case AnchorKind.BottomLeft =>
            left = inner.left
            top = inner.bottom - h
        case AnchorKind.BottomRight =>
            left = inner.right - w
            top = inner.bottom - h
        case AnchorKind.Center =>
            left = inner.left + (inner.width() - w) / 2
            top = inner.top + (inner.height() - h) / 2
    }
    let r = Rect(left: left, top: top, right: left + w, bottom: top + h)
    for (_ in 0..count) {
        out.add(r)
    }
    return out
}

func anchorSize(spec: LayoutSpec): Size {
    match (spec.sizePercent) {
        case Some(s) => s
        case None =>
            match (spec.anchor) {
                case AnchorKind.Left | AnchorKind.Right => Size(width: 50, height: 100)
                case AnchorKind.Top | AnchorKind.Bottom => Size(width: 100, height: 50)
                case AnchorKind.Center => Size(width: 60, height: 60)
                case _ => Size(width: 50, height: 50)
            }
    }
}

public func describePlacements(ps: Array<Placement>): String {
    var s = ""
    var i: Int64 = 0
    for (p in ps) {
        s = s + "  [" + i.toString() + "] " + p.window.describe() + " -> " + p.rect.describe() + "\n"
        i = i + 1
    }
    return s
}
