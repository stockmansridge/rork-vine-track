import UIKit

struct PDFHeaderHelper {
    static func drawHeader(
        vineyardName: String,
        logoData: Data?,
        title: String,
        accentColor: UIColor,
        margin: CGFloat,
        contentWidth: CGFloat,
        y: inout CGFloat
    ) {
        let logoSize: CGFloat = 44
        let titleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
        let nameFont = UIFont.systemFont(ofSize: 13, weight: .semibold)

        if let logoData = logoData, let logoImage = UIImage(data: logoData) {
            let logoRect = CGRect(x: margin, y: y, width: logoSize, height: logoSize)
            let clipPath = UIBezierPath(roundedRect: logoRect, cornerRadius: 8)
            UIGraphicsGetCurrentContext()?.saveGState()
            clipPath.addClip()
            logoImage.draw(in: logoRect)
            UIGraphicsGetCurrentContext()?.restoreGState()

            let textX = margin + logoSize + 10
            let availableWidth = contentWidth - logoSize - 10

            if !vineyardName.isEmpty {
                let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: UIColor.darkGray]
                (vineyardName as NSString).draw(
                    in: CGRect(x: textX, y: y + 2, width: availableWidth, height: 18),
                    withAttributes: nameAttrs
                )
            }

            let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: accentColor]
            let titleY = vineyardName.isEmpty ? y + 8 : y + 20
            (title as NSString).draw(
                in: CGRect(x: textX, y: titleY, width: availableWidth, height: 28),
                withAttributes: titleAttrs
            )

            y += max(logoSize, 48) + 6
        } else {
            if !vineyardName.isEmpty {
                let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: UIColor.darkGray]
                (vineyardName as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: nameAttrs)
                y += 18
            }

            let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: accentColor]
            (title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
            y += 28
        }

        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: y))
        line.addLine(to: CGPoint(x: margin + contentWidth, y: y))
        accentColor.setStroke()
        line.lineWidth = 1.5
        line.stroke()
        y += 12
    }
}
