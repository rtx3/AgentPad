//
//  GameControllerIcon.swift
//  AgentPad
//
//  Created by magicien on 2020/03/07.
//  Copyright © 2020 DarkHorse. All rights reserved.
//

import JoyConSwift

let proconBase = NSImage(named: "procon_base")!
let proconLeftGrip = NSImage(named: "procon_left_grip")!
let proconRightGrip = NSImage(named: "procon_right_grip")!
let proconBody = NSImage(named: "procon_body")!
let proconButton = NSImage(named: "procon_button")!

let joyconLBase = NSImage(named: "joycon_left_base")!
let joyconLBody = NSImage(named: "joycon_left_body")!
let joyconLButton = NSImage(named: "joycon_left_button")!

let joyconRBase = NSImage(named: "joycon_right_base")!
let joyconRBody = NSImage(named: "joycon_right_body")!
let joyconRButton = NSImage(named: "joycon_right_button")!

let famicon_1 = NSImage(named: "famicon_1")!
let famicon_2 = NSImage(named: "famicon_2")!
let snescon = NSImage(named: "snescon")!

let unknownController = NSImage(named: "unknown_controller")!

let batteryFull = NSImage(named: "battery_full")!
let batteryMedium = NSImage(named: "battery_medium")!
let batteryLow = NSImage(named: "battery_low")!
let batteryCritical = NSImage(named: "battery_critical")!
let batteryEmpty = NSImage(named: "battery_empty")!
let batteryCharge = NSImage(named: "battery_charge")!

let stop = NSImage(named: "stop")!

func GameControllerIcon(for controller: GameController) -> NSImage {
    switch(controller.kind) {
    case .proController:
        return createProConIcon(for: controller)
    case .joyConL:
        return createJoyConLIcon(for: controller)
    case .joyConR:
        return createJoyConRIcon(for: controller)
    case .famicomController1:
        return famicon_1
    case .famicomController2:
        return famicon_2
    case .snesController:
        return snescon
    case .dualShock4, .dualSense, .xbox, .mfi, .generic, .unknown:
        // M3 backends don't have body / button colour artwork yet — fall back
        // to the placeholder icon. Battery overlay still draws on top.
        return createGenericIcon(for: controller)
    }
}

private func drawBatteryIcon(for controller: GameController) {
    guard let backend = controller.backend else { return }
    if !backend.supportsBattery { return }
    let iconRect = NSRect(origin: CGPoint.zero, size: batteryFull.size)

    switch(backend.battery) {
    case .full:
        batteryFull.draw(in: iconRect)
    case .medium:
        batteryMedium.draw(in: iconRect)
    case .low:
        batteryLow.draw(in: iconRect)
    case .critical:
        batteryCritical.draw(in: iconRect)
    case .empty:
        batteryEmpty.draw(in: iconRect)
    case .unknown:
        break
    }

    if backend.isCharging {
        batteryCharge.draw(in: iconRect)
    }
}

private func drawStopIcon() {
    let iconRect = NSRect(origin: CGPoint.zero, size: stop.size)
    stop.draw(in: iconRect)
}

private func createProConIcon(for controller: GameController) -> NSImage {
    guard
        let leftGripColor = controller.leftGripColor,
        let rightGripColor = controller.rightGripColor
        else { return unknownController }
    
    guard let icon = proconBase.copy() as? NSImage else { return unknownController }
    let iconRect = NSRect(origin: NSZeroPoint, size: icon.size)

    proconLeftGrip.lockFocus()
    leftGripColor.set()
    iconRect.fill(using: .sourceAtop)
    proconLeftGrip.unlockFocus()
    
    proconRightGrip.lockFocus()
    rightGripColor.set()
    iconRect.fill(using: .sourceAtop)
    proconRightGrip.unlockFocus()

    proconBody.lockFocus()
    controller.bodyColor.set()
    iconRect.fill(using: .sourceAtop)
    proconBody.unlockFocus()
    
    proconButton.lockFocus()
    controller.buttonColor.set()
    iconRect.fill(using: .sourceAtop)
    proconButton.unlockFocus()
    
    icon.lockFocus()
    proconLeftGrip.draw(in: iconRect)
    proconRightGrip.draw(in: iconRect)
    proconBody.draw(in: iconRect)
    proconButton.draw(in: iconRect)
    drawBatteryIcon(for: controller)
    if !controller.isEnabled {
        drawStopIcon()
    }
    icon.unlockFocus()

    return icon
}

private func createJoyConLIcon(for controller: GameController) -> NSImage {
    guard let icon = joyconLBase.copy() as? NSImage else {
        return unknownController
    }
    let iconRect = NSRect(origin: NSZeroPoint, size: icon.size)

    joyconLBody.lockFocus()
    controller.bodyColor.set()
    iconRect.fill(using: .sourceAtop)
    joyconLBody.unlockFocus()
    
    joyconLButton.lockFocus()
    controller.buttonColor.set()
    iconRect.fill(using: .sourceAtop)
    joyconLButton.unlockFocus()
    
    icon.lockFocus()
    joyconLBody.draw(in: iconRect)
    joyconLButton.draw(in: iconRect)
    drawBatteryIcon(for: controller)
    if !controller.isEnabled {
        drawStopIcon()
    }
    icon.unlockFocus()

    return icon
}

private func createJoyConRIcon(for controller: GameController) -> NSImage {
    guard let icon = joyconRBase.copy() as? NSImage else {
        return unknownController
    }
    let iconRect = NSRect(origin: NSZeroPoint, size: icon.size)

    joyconRBody.lockFocus()
    controller.bodyColor.set()
    iconRect.fill(using: .sourceAtop)
    joyconRBody.unlockFocus()

    joyconRButton.lockFocus()
    controller.buttonColor.set()
    iconRect.fill(using: .sourceAtop)
    joyconRButton.unlockFocus()

    icon.lockFocus()
    joyconRBody.draw(in: iconRect)
    joyconRButton.draw(in: iconRect)
    drawBatteryIcon(for: controller)
    if !controller.isEnabled {
        drawStopIcon()
    }
    icon.unlockFocus()

    return icon
}

/// Placeholder for non-Nintendo backends (DualShock4 / DualSense / Xbox /
/// MFi / generic). 用 NSBezierPath 在 128×128 画布上代码绘制矢量手柄：
/// 椭圆主体 + 两个圆形握把 + 两个摇杆 + D-pad + 四个面键。颜色按 kind 切换，
/// 区分 Xbox（深灰）/ DualSense（白）/ generic（中灰）。
/// 电量与 disabled overlay 仍叠加在最上层。
private func createGenericIcon(for controller: GameController) -> NSImage {
    let size = NSSize(width: 128, height: 128)
    let icon = NSImage(size: size, flipped: false) { rect in
        drawVectorGamepad(in: rect, kind: controller.kind)
        return true
    }
    icon.lockFocus()
    drawBatteryIcon(for: controller)
    if !controller.isEnabled {
        drawStopIcon()
    }
    icon.unlockFocus()
    return icon
}

/// 在 `rect` 内绘制一个现代手柄矢量图。所有坐标按 0–1 归一化后乘 rect.size，
/// 因此同一段路径在任何尺寸下都清晰。
private func drawVectorGamepad(in rect: NSRect, kind: ControllerKind) {
    let (bodyColor, accentColor, faceColor): (NSColor, NSColor, NSColor)
    switch kind {
    case .xbox:
        bodyColor = NSColor(red: 0.22, green: 0.22, blue: 0.22, alpha: 1.0)
        accentColor = NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0)
        faceColor = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0)
    case .dualSense, .dualShock4:
        bodyColor = NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
        accentColor = NSColor(red: 0.30, green: 0.30, blue: 0.32, alpha: 1.0)
        faceColor = NSColor(red: 0.30, green: 0.30, blue: 0.32, alpha: 1.0)
    default:
        bodyColor = NSColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1.0)
        accentColor = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0)
        faceColor = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0)
    }

    let w = rect.width
    let h = rect.height
    let cx = rect.midX
    let cy = rect.midY

    // 主体：左右两个圆形握把 + 中间连接矩形，组合成对称手柄轮廓。
    let bodyPath = NSBezierPath()
    let gripRadius = w * 0.28
    let leftGripCenter = NSPoint(x: rect.minX + w * 0.27, y: cy - h * 0.04)
    let rightGripCenter = NSPoint(x: rect.minX + w * 0.73, y: cy - h * 0.04)
    bodyPath.appendOval(in: NSRect(
        x: leftGripCenter.x - gripRadius,
        y: leftGripCenter.y - gripRadius,
        width: gripRadius * 2,
        height: gripRadius * 2
    ))
    bodyPath.appendOval(in: NSRect(
        x: rightGripCenter.x - gripRadius,
        y: rightGripCenter.y - gripRadius,
        width: gripRadius * 2,
        height: gripRadius * 2
    ))
    // 中央肩部矩形（圆角），把两个握把连起来。
    let centerRect = NSRect(
        x: leftGripCenter.x,
        y: cy - h * 0.16,
        width: rightGripCenter.x - leftGripCenter.x,
        height: h * 0.36
    )
    bodyPath.append(NSBezierPath(roundedRect: centerRect, xRadius: h * 0.10, yRadius: h * 0.10))
    bodyColor.setFill()
    bodyPath.fill()

    // 左摇杆（左握把上方略偏内）。
    let lStickRadius = w * 0.085
    let lStickCenter = NSPoint(x: leftGripCenter.x + w * 0.02, y: cy + h * 0.06)
    let lStickRing = NSBezierPath(ovalIn: NSRect(
        x: lStickCenter.x - lStickRadius,
        y: lStickCenter.y - lStickRadius,
        width: lStickRadius * 2,
        height: lStickRadius * 2
    ))
    accentColor.setStroke()
    lStickRing.lineWidth = w * 0.018
    lStickRing.stroke()

    // 右摇杆（与左摇杆对称）。
    let rStickRadius = w * 0.085
    let rStickCenter = NSPoint(x: rightGripCenter.x - w * 0.02, y: cy - h * 0.10)
    let rStickRing = NSBezierPath(ovalIn: NSRect(
        x: rStickCenter.x - rStickRadius,
        y: rStickCenter.y - rStickRadius,
        width: rStickRadius * 2,
        height: rStickRadius * 2
    ))
    rStickRing.lineWidth = w * 0.018
    rStickRing.stroke()

    // D-pad 十字（中央偏左下）。
    let dpadCenter = NSPoint(x: cx - w * 0.13, y: cy - h * 0.10)
    let dpadArm = w * 0.06
    let dpadThickness = w * 0.035
    let dpadH = NSBezierPath(rect: NSRect(
        x: dpadCenter.x - dpadArm,
        y: dpadCenter.y - dpadThickness / 2,
        width: dpadArm * 2,
        height: dpadThickness
    ))
    let dpadV = NSBezierPath(rect: NSRect(
        x: dpadCenter.x - dpadThickness / 2,
        y: dpadCenter.y - dpadArm,
        width: dpadThickness,
        height: dpadArm * 2
    ))
    accentColor.setFill()
    dpadH.fill()
    dpadV.fill()

    // 4 个面键（A/B/X/Y）：右上区域，菱形排列。
    let faceCenter = NSPoint(x: cx + w * 0.13, y: cy + h * 0.06)
    let faceRadius = w * 0.04
    let faceOffset = w * 0.07
    let facePositions: [NSPoint] = [
        NSPoint(x: faceCenter.x, y: faceCenter.y + faceOffset),  // top
        NSPoint(x: faceCenter.x + faceOffset, y: faceCenter.y),  // right
        NSPoint(x: faceCenter.x, y: faceCenter.y - faceOffset),  // bottom
        NSPoint(x: faceCenter.x - faceOffset, y: faceCenter.y),  // left
    ]
    faceColor.setFill()
    for pos in facePositions {
        let circle = NSBezierPath(ovalIn: NSRect(
            x: pos.x - faceRadius,
            y: pos.y - faceRadius,
            width: faceRadius * 2,
            height: faceRadius * 2
        ))
        circle.fill()
    }

    // 中央两颗胶囊键（select / start）。
    let pillW = w * 0.06
    let pillH = h * 0.022
    let pillY = cy + h * 0.02
    for x in [cx - w * 0.045, cx + w * 0.045] {
        let pill = NSBezierPath(roundedRect: NSRect(
            x: x - pillW / 2,
            y: pillY - pillH / 2,
            width: pillW,
            height: pillH
        ), xRadius: pillH / 2, yRadius: pillH / 2)
        accentColor.setFill()
        pill.fill()
    }
}
