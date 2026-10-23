import SwiftUI
import UIKit

/// 시스템 공유 시트 (UIActivityViewController) 래퍼. 알림의 "공유" 동작에서 사용한다.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
