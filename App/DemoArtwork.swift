import UIKit

/// Vector artwork and short stories created for this app, with no external images.
@MainActor
enum DemoArtwork {
    private static func palette(_ id: String) -> (UIColor, UIColor) {
        switch id {
        case "demo-garden": return (UIColor(red: 0.13, green: 0.30, blue: 0.27, alpha: 1), UIColor(red: 0.90, green: 0.77, blue: 0.48, alpha: 1))
        case "demo-clouds": return (UIColor(red: 0.24, green: 0.27, blue: 0.46, alpha: 1), UIColor(red: 0.96, green: 0.66, blue: 0.51, alpha: 1))
        default: return (UIColor(red: 0.09, green: 0.20, blue: 0.32, alpha: 1), UIColor(red: 0.97, green: 0.67, blue: 0.28, alpha: 1))
        }
    }
    static func cover(_ series: LibrarySeries) -> UIImage {
        draw(id: series.id, title: series.title, narration: nil, page: 0, size: CGSize(width: 600, height: 900))
    }
    static func page(_ page: DemoCatalog.Page) -> UIImage {
        draw(id: page.seriesID, title: page.title, narration: page.narration, page: page.index,
             size: CGSize(width: 900, height: page.vertical ? 1800 : 1260))
    }
    private static func text(_ string: String, in rect: CGRect, size: CGFloat, color: UIColor, weight: UIFont.Weight = .regular) {
        let style = NSMutableParagraphStyle(); style.lineSpacing = 8
        (string as NSString).draw(in: rect, withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
    }
    private static func draw(id: String, title: String, narration: String?, page: Int, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let (night, accent) = palette(id), w = size.width, h = size.height
            let cg = context.cgContext
            night.setFill(); cg.fill(CGRect(origin: .zero, size: size))
            accent.withAlphaComponent(0.12).setFill()
            cg.fillEllipse(in: CGRect(x: w * 0.32, y: h * 0.28, width: w * 0.85, height: w * 0.85))
            text("TANKARR READER  /  RACCONTI DEMO", in: CGRect(x: 42, y: 40, width: w - 84, height: 35), size: narration == nil ? 17 : 23, color: accent, weight: .semibold)
            text(title, in: CGRect(x: 42, y: 105, width: w - 84, height: 180), size: narration == nil ? 52 : 62, color: .white, weight: .bold)
            let base = h * (narration == nil ? 0.72 : 0.57)
            if id == "demo-lighthouse" {
                let beam = UIBezierPath(); beam.move(to: CGPoint(x: w * 0.53, y: base - w * 0.37))
                beam.addLine(to: CGPoint(x: w, y: base - w * 0.60)); beam.addLine(to: CGPoint(x: w, y: base - w * 0.20)); beam.close()
                accent.withAlphaComponent(0.35).setFill(); beam.fill()
                UIColor.white.withAlphaComponent(0.90).setFill()
                let tower = UIBezierPath(); tower.move(to: CGPoint(x: w * 0.38, y: base)); tower.addLine(to: CGPoint(x: w * 0.43, y: base - w * 0.35)); tower.addLine(to: CGPoint(x: w * 0.56, y: base - w * 0.35)); tower.addLine(to: CGPoint(x: w * 0.62, y: base)); tower.close(); tower.fill()
                accent.setFill(); cg.fill(CGRect(x: w * 0.42, y: base - w * 0.42, width: w * 0.15, height: w * 0.08))
            } else if id == "demo-garden" {
                for i in 0..<5 {
                    let x = w * (0.13 + CGFloat(i) * 0.16), height = w * (0.19 + CGFloat((i + page) % 3) * 0.06)
                    UIColor.white.withAlphaComponent(0.16 + CGFloat(i) * 0.05).setFill(); cg.fill(CGRect(x: x, y: base - height, width: w * 0.12, height: height))
                    accent.setStroke(); cg.setLineWidth(5); cg.move(to: CGPoint(x: x + w * 0.06, y: base - height)); cg.addLine(to: CGPoint(x: x + w * 0.06, y: base - height - 60)); cg.strokePath()
                    accent.setFill(); cg.fillEllipse(in: CGRect(x: x + w * 0.01, y: base - height - 80, width: 42, height: 28))
                }
            } else {
                for i in 0..<4 {
                    let x = w * (0.12 + CGFloat(i % 2) * 0.37), y = base - w * 0.36 + CGFloat(i) * 75
                    UIColor.white.withAlphaComponent(0.25 + CGFloat(i) * 0.14).setFill()
                    UIBezierPath(roundedRect: CGRect(x: x, y: y, width: w * 0.36, height: 60), cornerRadius: 30).fill()
                    cg.fillEllipse(in: CGRect(x: x + 45, y: y - 35, width: 90, height: 90))
                }
            }
            accent.setFill(); cg.fill(CGRect(x: 42, y: base + 35, width: w - 84, height: 3))
            if let narration {
                text(narration, in: CGRect(x: 58, y: base + 75, width: w - 116, height: h - base - 175), size: 34, color: .white)
                text("\(page + 1)  /  3   ·   Storia e illustrazioni originali", in: CGRect(x: 58, y: h - 65, width: w - 116, height: 35), size: 22, color: accent)
            } else {
                text("VOLUME 01\nUn nuovo inizio", in: CGRect(x: 42, y: base + 75, width: w - 84, height: 100), size: 24, color: accent)
            }
        }
    }
}
