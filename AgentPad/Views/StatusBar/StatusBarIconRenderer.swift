//
//  StatusBarIconRenderer.swift
//  AgentPad
//
//  把 AgentMonitorEvent 渲染成 NSStatusItem.button.image。
//  全部为 NSBezierPath 手绘，10.14 兼容；不依赖 SF Symbol。
//

import AppKit

enum StatusBarIconState: Equatable {
    case empty
    case agents(states: [AgentState], totalCount: Int)
    case pollingFailed
}

enum StatusBarIconRenderer {
    /// 单个状态圆点直径。
    private static let dotSize: CGFloat = 8
    /// 圆点之间留白。
    private static let dotSpacing: CGFloat = 3
    /// 总图标高度（NSStatusItem.button 默认建议 16–22）。
    private static let iconHeight: CGFloat = 16
    /// 两行布局的图标高度。
    private static let twoLineIconHeight: CGFloat = 24
    /// 文本 / 圆点之间留白。
    private static let labelGap: CGFloat = 4
    /// 普通字号。
    private static let labelFontSize: CGFloat = 11
    /// 两行布局字号。
    private static let twoLineFontSize: CGFloat = 10
    /// 1–4 圆点的最大显示数量；超过即折叠。
    static let inlineMaxDots: Int = 4
    /// 折叠模式（5+）下保留前 N 个真实圆点。
    private static let collapsedRealDots: Int = 3

    static func image(for state: StatusBarIconState, showCount: Bool) -> NSImage {
        switch state {
        case .empty:
            return drawEmpty()
        case .pollingFailed:
            return drawFailed()
        case .agents(let states, let total):
            return drawAgents(states: states, totalCount: total, showCount: showCount)
        }
    }

    /// 两行布局：icon (20pt) + 右侧两行文字 R{n} / I{n}。
    /// 边界情况：只有一个非 0 时退化成单行；全 0 时只显示 icon。
    static func twoLineImage(running: Int, idle: Int) -> NSImage {
        let baseIcon = NSImage(named: "menu_icon")

        // 全 0：只显示 icon
        if running == 0 && idle == 0 {
            let img = NSImage(size: NSSize(width: twoLineIconHeight, height: twoLineIconHeight))
            img.lockFocus()
            baseIcon?.draw(in: NSRect(x: 0, y: 0, width: twoLineIconHeight, height: twoLineIconHeight))
            img.unlockFocus()
            img.isTemplate = true
            return img
        }

        // 只有一个非 0：单行布局（icon + 垂直居中文字）
        if running == 0 || idle == 0 {
            let text = running > 0 ? "▶\(running)" : "⏸\(idle)"
            let textSize = sizeOfText(text, fontSize: twoLineFontSize)
            let totalWidth = twoLineIconHeight + labelGap + textSize.width

            let img = NSImage(size: NSSize(width: totalWidth, height: twoLineIconHeight))
            img.lockFocus()

            // icon 垂直居中
            baseIcon?.draw(in: NSRect(x: 0, y: 0, width: twoLineIconHeight, height: twoLineIconHeight))

            // 文字垂直居中
            let textY = (twoLineIconHeight - textSize.height) / 2
            drawText(text, at: NSPoint(x: twoLineIconHeight + labelGap, y: textY),
                    color: .labelColor, fontSize: twoLineFontSize)

            img.unlockFocus()
            img.isTemplate = true
            return img
        }

        // 两行布局
        let runningText = "▶ \(running)"
        let idleText = "⏸ \(idle)"
        let runningSize = sizeOfText(runningText, fontSize: twoLineFontSize)
        let idleSize = sizeOfText(idleText, fontSize: twoLineFontSize)
        let maxTextWidth = max(runningSize.width, idleSize.width)
        let totalWidth = twoLineIconHeight + labelGap + maxTextWidth

        let lineSpacing: CGFloat = 0
        let totalTextHeight = runningSize.height + lineSpacing + idleSize.height
        let totalHeight = max(twoLineIconHeight, totalTextHeight)

        let img = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        img.lockFocus()

        // icon 垂直居中
        let iconY = (totalHeight - twoLineIconHeight) / 2
        baseIcon?.draw(in: NSRect(x: 0, y: iconY, width: twoLineIconHeight, height: twoLineIconHeight))

        // 两行文字垂直居中
        let textBlockY = (totalHeight - totalTextHeight) / 2
        let runningY = textBlockY + idleSize.height + lineSpacing
        let idleY = textBlockY

        drawText(runningText, at: NSPoint(x: twoLineIconHeight + labelGap, y: runningY),
                color: .labelColor, fontSize: twoLineFontSize)
        drawText(idleText, at: NSPoint(x: twoLineIconHeight + labelGap, y: idleY),
                color: .labelColor, fontSize: twoLineFontSize)

        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    // MARK: - Empty (虚线圆圈)

    private static func drawEmpty() -> NSImage {
        let size = NSSize(width: iconHeight, height: iconHeight)
        let img = NSImage(size: size)
        img.lockFocus()
        let circle = NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: iconHeight - 6, height: iconHeight - 6))
        circle.lineWidth = 1.2
        let pattern: [CGFloat] = [2, 2]
        circle.setLineDash(pattern, count: 2, phase: 0)
        NSColor.secondaryLabelColor.setStroke()
        circle.stroke()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    // MARK: - Polling failed (感叹号在圆里)

    private static func drawFailed() -> NSImage {
        let size = NSSize(width: iconHeight, height: iconHeight)
        let img = NSImage(size: size)
        img.lockFocus()
        let outer = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: iconHeight - 4, height: iconHeight - 4))
        outer.lineWidth = 1.2
        NSColor.systemGray.setStroke()
        outer.stroke()
        // 感叹号竖条
        let bar = NSBezierPath(roundedRect: NSRect(x: iconHeight/2 - 0.7, y: 6, width: 1.4, height: 5.2),
                               xRadius: 0.7, yRadius: 0.7)
        NSColor.systemGray.setFill()
        bar.fill()
        // 感叹号点
        let dot = NSBezierPath(ovalIn: NSRect(x: iconHeight/2 - 0.9, y: 3.6, width: 1.8, height: 1.8))
        dot.fill()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    // MARK: - 1..N agents

    private static func drawAgents(states: [AgentState], totalCount: Int, showCount: Bool) -> NSImage {
        let displayDots: [AgentState]
        let plusValue: Int
        if states.count > inlineMaxDots {
            displayDots = Array(states.prefix(collapsedRealDots))
            plusValue = max(0, totalCount - collapsedRealDots)
        } else {
            displayDots = states
            plusValue = 0
        }

        let plusLabel: String? = plusValue > 0 ? "+\(plusValue)" : nil
        let countLabel: String? = showCount ? "\(totalCount)" : nil

        // 计算尺寸
        let plusSize = plusLabel.map { sizeOfPill(text: $0) } ?? .zero
        let countSize = countLabel.map { sizeOfText($0) } ?? .zero

        let dotsWidth: CGFloat = displayDots.isEmpty
            ? 0
            : (CGFloat(displayDots.count) * dotSize + CGFloat(displayDots.count - 1) * dotSpacing)
        var width: CGFloat = dotsWidth
        if plusLabel != nil { width += dotSpacing + plusSize.width }
        if countLabel != nil { width += labelGap + countSize.width }
        width = max(width, dotSize)

        let totalSize = NSSize(width: width, height: iconHeight)
        let img = NSImage(size: totalSize)
        img.lockFocus()

        var x: CGFloat = 0
        let dotY: CGFloat = (iconHeight - dotSize) / 2
        for state in displayDots {
            let rect = NSRect(x: x, y: dotY, width: dotSize, height: dotSize)
            color(for: state).setFill()
            NSBezierPath(ovalIn: rect).fill()
            x += dotSize + dotSpacing
        }
        if let plus = plusLabel {
            // 圆点循环已经在末尾留出一个 dotSpacing，直接用作 +M 胶囊的左边距。
            drawPill(text: plus, at: NSPoint(x: x, y: (iconHeight - plusSize.height) / 2))
            x += plusSize.width
        }
        if let count = countLabel {
            x += labelGap
            drawText(count, at: NSPoint(x: x, y: (iconHeight - countSize.height) / 2),
                     color: .labelColor)
        }

        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    static func color(for state: AgentState) -> NSColor {
        switch state {
        case .working:    return .systemGreen
        case .callingAPI: return .systemOrange
        case .idle:       return .systemGray
        }
    }

    // MARK: - 文本辅助

    private static func labelFont() -> NSFont {
        return NSFont.systemFont(ofSize: labelFontSize, weight: .medium)
    }

    private static func labelFont(size: CGFloat) -> NSFont {
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
    }

    private static func sizeOfText(_ text: String) -> NSSize {
        return (text as NSString).size(withAttributes: [.font: labelFont()])
    }

    private static func sizeOfText(_ text: String, fontSize: CGFloat) -> NSSize {
        return (text as NSString).size(withAttributes: [.font: labelFont(size: fontSize)])
    }

    private static func drawText(_ text: String, at origin: NSPoint, color: NSColor) {
        (text as NSString).draw(at: origin, withAttributes: [
            .font: labelFont(),
            .foregroundColor: color
        ])
    }

    private static func drawText(_ text: String, at origin: NSPoint, color: NSColor, fontSize: CGFloat) {
        (text as NSString).draw(at: origin, withAttributes: [
            .font: labelFont(size: fontSize),
            .foregroundColor: color
        ])
    }

    private static func sizeOfPill(text: String) -> NSSize {
        let s = sizeOfText(text)
        return NSSize(width: ceil(s.width) + 6, height: ceil(s.height) + 1)
    }

    private static func drawPill(text: String, at origin: NSPoint) {
        let size = sizeOfPill(text: text)
        let rect = NSRect(origin: origin, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        NSColor.systemGray.withAlphaComponent(0.25).setFill()
        path.fill()
        let textOrigin = NSPoint(x: rect.minX + 3, y: rect.minY + 0)
        drawText(text, at: textOrigin, color: .labelColor)
    }
}
