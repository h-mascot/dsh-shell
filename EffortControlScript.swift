import Foundation
import WebKit

enum EffortControlScript {
    private static let founderAssets: [(placeholder: String, resource: String)] = [
        ("__DSH_FOUNDER_OFF_DATA_URI__", "founder-off"),
        ("__DSH_FOUNDER_HIGH_DATA_URI__", "founder-high"),
        ("__DSH_FOUNDER_MAX_DATA_URI__", "founder-max"),
    ]

    static func makeUserScript(bundle: Bundle = .main) -> WKUserScript? {
        guard let scriptURL = bundle.url(forResource: "EffortControl", withExtension: "js"),
              var source = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            return nil
        }

        for asset in founderAssets {
            guard let imageURL = bundle.url(forResource: asset.resource, withExtension: "png"),
                  let data = try? Data(contentsOf: imageURL) else {
                return nil
            }
            let dataURI = "data:image/png;base64,\(data.base64EncodedString())"
            source = source.replacingOccurrences(of: asset.placeholder, with: dataURI)
        }

        return WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }
}
