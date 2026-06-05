//
//  AccessibilityOnboardingWindowController.swift
//  AgentPad
//

import AppKit

final class AccessibilityOnboardingWindowController: NSWindowController, NSWindowDelegate {

    private var currentStep: Int = 0
    private let totalSteps: Int = 3

    private let pageContainerView = NSView()
    private let page0View = NSView()
    private let page1View = NSView()
    private let page2View = NSView()

    private let page0ImageView = NSImageView()
    private let page0TitleLabel = NSTextField(labelWithString: "")
    private let page0BodyLabel = NSTextField(labelWithString: "")

    private let page1ImageView = NSImageView()
    private let page1ImageViewRight = NSImageView()
    private let page1TitleLabel = NSTextField(labelWithString: "")
    private let page1BodyLabel = NSTextField(labelWithString: "")
    private let page1MappingLabel = NSTextField(labelWithString: "")

    private let page2ImageView = NSImageView()
    private let page2TitleLabel = NSTextField(labelWithString: "")
    private let page2BodyLabel = NSTextField(labelWithString: "")

    private let dontShowAgainButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    private let pageIndicatorView = NSStackView()
    private var pageIndicatorDots: [NSView] = []

    private let skipButton = NSButton(title: "", target: nil, action: nil)
    private let backButton = NSButton(title: "", target: nil, action: nil)
    private let nextButton = NSButton(title: "", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Accessibility access", comment: "Onboarding window title")
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.delegate = self
        self.buildLayout()
        self.applyLocalizedStrings()
        self.showStep(0)
    }

    private func buildLayout() {
        guard let contentView = self.window?.contentView else { return }

        pageContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pageContainerView)

        buildPage0()
        buildPage1()
        buildPage2()

        pageContainerView.addSubview(page0View)
        pageContainerView.addSubview(page1View)
        pageContainerView.addSubview(page2View)

        for _ in 0..<totalSteps {
            let dot = NSView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 4
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 8),
                dot.heightAnchor.constraint(equalToConstant: 8)
            ])
            pageIndicatorDots.append(dot)
            pageIndicatorView.addArrangedSubview(dot)
        }
        pageIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        pageIndicatorView.orientation = .horizontal
        pageIndicatorView.spacing = 8
        contentView.addSubview(pageIndicatorView)

        dontShowAgainButton.translatesAutoresizingMaskIntoConstraints = false
        dontShowAgainButton.state = .off
        contentView.addSubview(dontShowAgainButton)

        skipButton.translatesAutoresizingMaskIntoConstraints = false
        skipButton.bezelStyle = .rounded
        skipButton.target = self
        skipButton.action = #selector(didTapSkip(_:))
        contentView.addSubview(skipButton)

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.bezelStyle = .rounded
        backButton.target = self
        backButton.action = #selector(didTapBack(_:))
        contentView.addSubview(backButton)

        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"
        nextButton.target = self
        nextButton.action = #selector(didTapNext(_:))
        contentView.addSubview(nextButton)

        let pad: CGFloat = 24
        NSLayoutConstraint.activate([
            pageContainerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: pad),
            pageContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),
            pageContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),
            pageContainerView.bottomAnchor.constraint(equalTo: pageIndicatorView.topAnchor, constant: -16),

            page0View.topAnchor.constraint(equalTo: pageContainerView.topAnchor),
            page0View.leadingAnchor.constraint(equalTo: pageContainerView.leadingAnchor),
            page0View.trailingAnchor.constraint(equalTo: pageContainerView.trailingAnchor),
            page0View.bottomAnchor.constraint(equalTo: pageContainerView.bottomAnchor),

            page1View.topAnchor.constraint(equalTo: pageContainerView.topAnchor),
            page1View.leadingAnchor.constraint(equalTo: pageContainerView.leadingAnchor),
            page1View.trailingAnchor.constraint(equalTo: pageContainerView.trailingAnchor),
            page1View.bottomAnchor.constraint(equalTo: pageContainerView.bottomAnchor),

            page2View.topAnchor.constraint(equalTo: pageContainerView.topAnchor),
            page2View.leadingAnchor.constraint(equalTo: pageContainerView.leadingAnchor),
            page2View.trailingAnchor.constraint(equalTo: pageContainerView.trailingAnchor),
            page2View.bottomAnchor.constraint(equalTo: pageContainerView.bottomAnchor),

            pageIndicatorView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pageIndicatorView.bottomAnchor.constraint(equalTo: dontShowAgainButton.topAnchor, constant: -12),

            dontShowAgainButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -pad),
            dontShowAgainButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: pad),

            skipButton.centerYAnchor.constraint(equalTo: dontShowAgainButton.centerYAnchor),
            skipButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -pad),

            backButton.centerYAnchor.constraint(equalTo: dontShowAgainButton.centerYAnchor),
            backButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -12),

            nextButton.centerYAnchor.constraint(equalTo: dontShowAgainButton.centerYAnchor),
            nextButton.trailingAnchor.constraint(equalTo: skipButton.leadingAnchor, constant: -12),
        ])
    }

    private func buildPage0() {
        page0View.translatesAutoresizingMaskIntoConstraints = false

        page0ImageView.translatesAutoresizingMaskIntoConstraints = false
        page0ImageView.imageScaling = .scaleProportionallyDown
        page0ImageView.image = NSImage(named: "onboarding_monitor")

        page0TitleLabel.translatesAutoresizingMaskIntoConstraints = false
        page0TitleLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize + 4)
        page0TitleLabel.alignment = .center
        page0TitleLabel.lineBreakMode = .byWordWrapping
        page0TitleLabel.maximumNumberOfLines = 0

        page0BodyLabel.translatesAutoresizingMaskIntoConstraints = false
        page0BodyLabel.alignment = .center
        page0BodyLabel.lineBreakMode = .byWordWrapping
        page0BodyLabel.maximumNumberOfLines = 0
        page0BodyLabel.preferredMaxLayoutWidth = 480

        page0View.addSubview(page0ImageView)
        page0View.addSubview(page0TitleLabel)
        page0View.addSubview(page0BodyLabel)

        NSLayoutConstraint.activate([
            page0TitleLabel.topAnchor.constraint(equalTo: page0View.topAnchor),
            page0TitleLabel.leadingAnchor.constraint(equalTo: page0View.leadingAnchor),
            page0TitleLabel.trailingAnchor.constraint(equalTo: page0View.trailingAnchor),

            page0BodyLabel.topAnchor.constraint(equalTo: page0TitleLabel.bottomAnchor, constant: 8),
            page0BodyLabel.leadingAnchor.constraint(equalTo: page0View.leadingAnchor),
            page0BodyLabel.trailingAnchor.constraint(equalTo: page0View.trailingAnchor),

            page0ImageView.topAnchor.constraint(equalTo: page0BodyLabel.bottomAnchor, constant: 16),
            page0ImageView.centerXAnchor.constraint(equalTo: page0View.centerXAnchor),
            page0ImageView.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
            page0ImageView.heightAnchor.constraint(lessThanOrEqualToConstant: 200),
        ])
    }

    private func buildPage1() {
        page1View.translatesAutoresizingMaskIntoConstraints = false

        page1TitleLabel.translatesAutoresizingMaskIntoConstraints = false
        page1TitleLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize + 4)
        page1TitleLabel.alignment = .center
        page1TitleLabel.lineBreakMode = .byWordWrapping
        page1TitleLabel.maximumNumberOfLines = 0

        page1BodyLabel.translatesAutoresizingMaskIntoConstraints = false
        page1BodyLabel.alignment = .center
        page1BodyLabel.lineBreakMode = .byWordWrapping
        page1BodyLabel.maximumNumberOfLines = 0
        page1BodyLabel.preferredMaxLayoutWidth = 480

        page1ImageView.translatesAutoresizingMaskIntoConstraints = false
        page1ImageView.imageScaling = .scaleProportionallyDown
        page1ImageView.image = Self.composeJoyConIcon(
            baseName: "joycon_left_base",
            bodyName: "joycon_left_body",
            buttonName: "joycon_left_button",
            bodyColor: NSColor(red: 1.0, green: 0.235, blue: 0.157, alpha: 1.0),
            buttonColor: NSColor(red: 0.32, green: 0.10, blue: 0.08, alpha: 1.0)
        )

        page1ImageViewRight.translatesAutoresizingMaskIntoConstraints = false
        page1ImageViewRight.imageScaling = .scaleProportionallyDown
        page1ImageViewRight.image = Self.composeJoyConIcon(
            baseName: "joycon_right_base",
            bodyName: "joycon_right_body",
            buttonName: "joycon_right_button",
            bodyColor: NSColor(red: 0.039, green: 0.725, blue: 0.902, alpha: 1.0),
            buttonColor: NSColor(red: 0.04, green: 0.25, blue: 0.32, alpha: 1.0)
        )

        page1MappingLabel.translatesAutoresizingMaskIntoConstraints = false
        page1MappingLabel.lineBreakMode = .byWordWrapping
        page1MappingLabel.maximumNumberOfLines = 0
        page1MappingLabel.alignment = .center
        page1MappingLabel.font = NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)

        page1View.addSubview(page1TitleLabel)
        page1View.addSubview(page1BodyLabel)
        page1View.addSubview(page1ImageView)
        page1View.addSubview(page1ImageViewRight)
        page1View.addSubview(page1MappingLabel)

        NSLayoutConstraint.activate([
            page1TitleLabel.topAnchor.constraint(equalTo: page1View.topAnchor),
            page1TitleLabel.leadingAnchor.constraint(equalTo: page1View.leadingAnchor),
            page1TitleLabel.trailingAnchor.constraint(equalTo: page1View.trailingAnchor),

            page1BodyLabel.topAnchor.constraint(equalTo: page1TitleLabel.bottomAnchor, constant: 8),
            page1BodyLabel.leadingAnchor.constraint(equalTo: page1View.leadingAnchor),
            page1BodyLabel.trailingAnchor.constraint(equalTo: page1View.trailingAnchor),

            page1ImageView.topAnchor.constraint(equalTo: page1BodyLabel.bottomAnchor, constant: 20),
            page1ImageView.leadingAnchor.constraint(equalTo: page1View.leadingAnchor, constant: 8),
            page1ImageView.widthAnchor.constraint(equalToConstant: 110),
            page1ImageView.heightAnchor.constraint(equalToConstant: 160),

            page1ImageViewRight.topAnchor.constraint(equalTo: page1ImageView.topAnchor),
            page1ImageViewRight.trailingAnchor.constraint(equalTo: page1View.trailingAnchor, constant: -8),
            page1ImageViewRight.widthAnchor.constraint(equalToConstant: 110),
            page1ImageViewRight.heightAnchor.constraint(equalToConstant: 160),

            page1MappingLabel.centerYAnchor.constraint(equalTo: page1ImageView.centerYAnchor),
            page1MappingLabel.leadingAnchor.constraint(equalTo: page1ImageView.trailingAnchor, constant: 16),
            page1MappingLabel.trailingAnchor.constraint(equalTo: page1ImageViewRight.leadingAnchor, constant: -16),
        ])
    }

    private func buildPage2() {
        page2View.translatesAutoresizingMaskIntoConstraints = false

        page2ImageView.translatesAutoresizingMaskIntoConstraints = false
        page2ImageView.imageScaling = .scaleProportionallyDown
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
            page2ImageView.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)?.withSymbolConfiguration(config)
            page2ImageView.contentTintColor = .systemGray
        }

        page2TitleLabel.translatesAutoresizingMaskIntoConstraints = false
        page2TitleLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize + 4)
        page2TitleLabel.alignment = .center
        page2TitleLabel.lineBreakMode = .byWordWrapping
        page2TitleLabel.maximumNumberOfLines = 0

        page2BodyLabel.translatesAutoresizingMaskIntoConstraints = false
        page2BodyLabel.alignment = .center
        page2BodyLabel.lineBreakMode = .byWordWrapping
        page2BodyLabel.maximumNumberOfLines = 0
        page2BodyLabel.preferredMaxLayoutWidth = 480

        page2View.addSubview(page2ImageView)
        page2View.addSubview(page2TitleLabel)
        page2View.addSubview(page2BodyLabel)

        NSLayoutConstraint.activate([
            page2TitleLabel.topAnchor.constraint(equalTo: page2View.topAnchor),
            page2TitleLabel.leadingAnchor.constraint(equalTo: page2View.leadingAnchor),
            page2TitleLabel.trailingAnchor.constraint(equalTo: page2View.trailingAnchor),

            page2BodyLabel.topAnchor.constraint(equalTo: page2TitleLabel.bottomAnchor, constant: 8),
            page2BodyLabel.leadingAnchor.constraint(equalTo: page2View.leadingAnchor),
            page2BodyLabel.trailingAnchor.constraint(equalTo: page2View.trailingAnchor),

            page2ImageView.topAnchor.constraint(equalTo: page2BodyLabel.bottomAnchor, constant: 24),
            page2ImageView.centerXAnchor.constraint(equalTo: page2View.centerXAnchor),
            page2ImageView.widthAnchor.constraint(equalToConstant: 64),
            page2ImageView.heightAnchor.constraint(equalToConstant: 64),
        ])
    }

    private func applyLocalizedStrings() {
        page0TitleLabel.stringValue = NSLocalizedString("onboarding.step.monitor.title", comment: "")
        page0BodyLabel.stringValue = NSLocalizedString("onboarding.step.monitor.body", comment: "")

        page1TitleLabel.stringValue = NSLocalizedString("onboarding.step.controller.title", comment: "")
        page1BodyLabel.stringValue = NSLocalizedString("onboarding.step.controller.body", comment: "")
        page1MappingLabel.attributedStringValue = makeMappingTable()

        page2TitleLabel.stringValue = NSLocalizedString("onboarding.step.accessibility.title", comment: "")
        page2BodyLabel.stringValue = NSLocalizedString("onboarding.step.accessibility.body", comment: "")

        dontShowAgainButton.title = NSLocalizedString("Don't show again", comment: "Don't show again checkbox")
        skipButton.title = NSLocalizedString("onboarding.button.skip", comment: "")
        backButton.title = NSLocalizedString("onboarding.button.back", comment: "")
        nextButton.title = NSLocalizedString("onboarding.button.next", comment: "")
    }

    private func makeMappingTable() -> NSAttributedString {
        let rows: [(String, String)] = [
            (NSLocalizedString("onboarding.mapping.button.a", comment: ""),
             NSLocalizedString("onboarding.mapping.action.approve", comment: "")),
            (NSLocalizedString("onboarding.mapping.button.b", comment: ""),
             NSLocalizedString("onboarding.mapping.action.reject", comment: "")),
            (NSLocalizedString("onboarding.mapping.button.lr", comment: ""),
             NSLocalizedString("onboarding.mapping.action.scroll", comment: "")),
            (NSLocalizedString("onboarding.mapping.button.start", comment: ""),
             NSLocalizedString("onboarding.mapping.action.interrupt", comment: "")),
        ]
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 6

        let result = NSMutableAttributedString()
        for (i, row) in rows.enumerated() {
            let line = "\(row.0)  →  \(row.1)"
            let suffix = (i == rows.count - 1) ? "" : "\n"
            result.append(NSAttributedString(string: line + suffix))
        }
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }

    private func showStep(_ step: Int) {
        currentStep = step

        page0View.isHidden = (step != 0)
        page1View.isHidden = (step != 1)
        page2View.isHidden = (step != 2)

        for (index, dot) in pageIndicatorDots.enumerated() {
            dot.layer?.backgroundColor = (index == step) ? NSColor.controlAccentColor.cgColor : NSColor.systemGray.cgColor
        }

        backButton.isHidden = (step == 0)

        if step == totalSteps - 1 {
            skipButton.title = NSLocalizedString("onboarding.button.done", comment: "")
            if AccessibilityPermission.isTrusted() {
                nextButton.title = NSLocalizedString("onboarding.button.done", comment: "")
            } else {
                nextButton.title = NSLocalizedString("Open Privacy Settings", comment: "Open settings button")
            }
        } else {
            skipButton.title = NSLocalizedString("onboarding.button.skip", comment: "")
            nextButton.title = NSLocalizedString("onboarding.button.next", comment: "")
        }
    }

    private func persistDontShowAgainIfNeeded() {
        if dontShowAgainButton.state == .on {
            AccessibilityPermission.hasShownOnboarding = true
        }
    }

    @objc private func didTapSkip(_ sender: Any?) {
        persistDontShowAgainIfNeeded()
        self.close()
    }

    @objc private func didTapBack(_ sender: Any?) {
        if currentStep > 0 {
            showStep(currentStep - 1)
        }
    }

    @objc private func didTapNext(_ sender: Any?) {
        if currentStep < totalSteps - 1 {
            showStep(currentStep + 1)
            return
        }
        if !AccessibilityPermission.isTrusted() {
            AccessibilityPermission.registerInTCCList()
            AccessibilityPermission.requestTrust()
            AccessibilityPermission.openSettings()
        }
        persistDontShowAgainIfNeeded()
        self.close()
    }

    static func presentIfNeeded() -> AccessibilityOnboardingWindowController? {
        if AccessibilityPermission.isTrusted() { return nil }
        if AccessibilityPermission.hasShownOnboarding { return nil }
        let controller = AccessibilityOnboardingWindowController()
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        return controller
    }

    /// Compose a Joy-Con icon by layering base + body + button imagesets,
    /// tinting body and button with the given colors. Mirrors the layering
    /// approach in GameControllerIcon.createJoyConLIcon.
    private static func composeJoyConIcon(
        baseName: String,
        bodyName: String,
        buttonName: String,
        bodyColor: NSColor,
        buttonColor: NSColor
    ) -> NSImage? {
        guard
            let base = NSImage(named: baseName),
            let body = NSImage(named: bodyName)?.copy() as? NSImage,
            let button = NSImage(named: buttonName)?.copy() as? NSImage,
            let icon = base.copy() as? NSImage
        else {
            return nil
        }
        let rect = NSRect(origin: .zero, size: icon.size)

        body.lockFocus()
        bodyColor.set()
        rect.fill(using: .sourceAtop)
        body.unlockFocus()

        button.lockFocus()
        buttonColor.set()
        rect.fill(using: .sourceAtop)
        button.unlockFocus()

        icon.lockFocus()
        body.draw(in: rect)
        button.draw(in: rect)
        icon.unlockFocus()

        return icon
    }
}
