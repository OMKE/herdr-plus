import SwiftUI
import UIKit

final class ImagePasteTextView: UITextView {
    var onImages: (([UIImage]) -> Void)?
    var onDeleteEmpty: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onSubmitNow: (() -> Void)?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pb = UIPasteboard.general
        if pb.hasImages, let images = pb.images, !images.isEmpty {
            onImages?(images)
            if pb.hasStrings, let s = pb.string, !s.isEmpty, !s.hasPrefix("file:") { super.paste(sender) }
            return
        }
        super.paste(sender)
    }

    override func deleteBackward() {
        if text.isEmpty { onDeleteEmpty?() }
        super.deleteBackward()
    }

    override var keyCommands: [UIKeyCommand]? {
        let send = UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(submit))
        send.discoverabilityTitle = "Send"
        guard onSubmitNow != nil else { return [send] }
        let now = UIKeyCommand(input: "\r", modifierFlags: .control, action: #selector(submitNow))
        now.discoverabilityTitle = "Send now"
        now.wantsPriorityOverSystemBehavior = true
        return [send, now]
    }

    @objc private func submit() { onSubmit?() }
    @objc private func submitNow() { onSubmitNow?() }
}

struct PasteTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: UIFont = .systemFont(ofSize: 15)
    var maxLines = 8
    var focusToken = 0
    var dark = true
    var onFocus: (Bool) -> Void = { _ in }
    var onImages: ([UIImage]) -> Void
    var onDeleteEmpty: () -> Void = {}
    var onSubmit: () -> Void = {}
    var onSubmitNow: (() -> Void)?

    func makeUIView(context: Context) -> ImagePasteTextView {
        let v = ImagePasteTextView()
        v.delegate = context.coordinator
        v.font = font
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.isScrollEnabled = true
        v.alwaysBounceVertical = false
        v.showsVerticalScrollIndicator = false
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultHigh, for: .vertical)
        context.coordinator.focusToken = focusToken
        style(v)
        return v
    }

    private func style(_ v: ImagePasteTextView) {
        v.textColor = UIColor(Theme.text)
        v.tintColor = UIColor(Theme.amber)
        v.keyboardAppearance = dark ? .dark : .light
        if v.font != font { v.font = font }
        v.onImages = onImages
        v.onDeleteEmpty = onDeleteEmpty
        v.onSubmit = onSubmit
        v.onSubmitNow = onSubmitNow
    }

    func updateUIView(_ v: ImagePasteTextView, context: Context) {
        context.coordinator.parent = self
        style(v)
        if v.text != text {
            v.text = text
            v.invalidateIntrinsicContentSize()
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { v.becomeFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView v: ImagePasteTextView, context: Context) -> CGSize? {
        let width = max(proposal.width ?? v.bounds.width, 40)
        let fit = ceil(v.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        let line = ceil(font.lineHeight)
        let cap = ceil(font.lineHeight * CGFloat(maxLines))
        let overflow = fit > cap + 1
        context.coordinator.overflow = overflow
        v.showsVerticalScrollIndicator = overflow
        if !overflow, v.contentOffset != .zero {
            DispatchQueue.main.async { if !context.coordinator.overflow { v.setContentOffset(.zero, animated: false) } }
        }
        return CGSize(width: width, height: max(line, min(fit, cap)))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PasteTextView
        var overflow = false
        var focusToken = 0
        init(_ p: PasteTextView) { parent = p }

        func textViewDidChange(_ v: UITextView) {
            parent.text = v.text
            v.invalidateIntrinsicContentSize()
            DispatchQueue.main.async {
                if self.overflow {
                    v.scrollRangeToVisible(v.selectedRange)
                } else if v.contentOffset != .zero {
                    v.setContentOffset(.zero, animated: false)
                }
            }
        }

        func scrollViewDidScroll(_ s: UIScrollView) {
            if !overflow, s.contentOffset != .zero, !s.isDragging { s.contentOffset = .zero }
        }

        func textViewDidBeginEditing(_ v: UITextView) { parent.onFocus(true) }
        func textViewDidEndEditing(_ v: UITextView) { parent.onFocus(false) }
    }
}
