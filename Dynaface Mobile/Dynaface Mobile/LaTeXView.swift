import SwiftUI
import SwiftMath

/// SwiftUI bridge to SwiftMath's `MTMathUILabel` — renders a LaTeX math string
/// natively (Core Graphics, no WebView). Used by the Analysis metric drop-downs
/// (U5) to show each metric's formula, variables, and worked example.
///
/// `textColor` defaults to `UIColor.label` so formulas adapt to light/dark mode.
/// `sizeThatFits` reports the exact rendered size so SwiftUI lays the formula out
/// with no clipping or vertical offset (place inside a horizontal ScrollView for
/// formulas wider than the container). SwiftMath only supports the TeX *math*
/// subset (fractions, subscripts, roots, sums, greek, \text{…}).
struct LaTeXView: UIViewRepresentable {
    let latex: String
    var fontSize: CGFloat = 17
    var textColor: UIColor = .label

    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.labelMode = .display
        label.textAlignment = .left
        label.backgroundColor = .clear
        return label
    }

    func updateUIView(_ uiView: MTMathUILabel, context: Context) {
        uiView.latex = latex
        uiView.fontSize = fontSize
        uiView.textColor = textColor
    }

    /// Report the exact rendered size so the formula isn't clipped or offset.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
        uiView.latex = latex
        uiView.fontSize = fontSize
        uiView.layoutIfNeeded()
        let size = uiView.intrinsicContentSize
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else {
            return nil
        }
        return size
    }
}
