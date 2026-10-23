import UIKit

enum ImagePreprocessor {
    /// 긴 변을 `maxDimension` 이하로 줄이고 JPEG 로 압축한다. (업로드 크기/토큰 절약)
    static func jpegData(from image: UIImage, maxDimension: CGFloat = 2000, quality: CGFloat = 0.85) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }

        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
