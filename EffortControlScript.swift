import Foundation
import WebKit

enum EffortControlScript {
    private static let founderAssets: [(placeholder: String, resource: String)] = [
        ("__DSH_FOUNDER_OFF_DATA_URI__", "founder-off"),
        ("__DSH_FOUNDER_HIGH_DATA_URI__", "founder-high"),
        ("__DSH_FOUNDER_MAX_DATA_URI__", "founder-max"),
    ]

    static let founderThemeDefaultsKey = "founderThemeEnabled"

    static func makeUserScript(bundle: Bundle = .main, founderThemeEnabled: Bool? = nil) -> WKUserScript? {
        guard let scriptURL = bundle.url(forResource: "EffortControl", withExtension: "js"),
              var source = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            return nil
        }

        let resolvedFounderEnabled = founderThemeEnabled ?? UserDefaults.standard.object(forKey: founderThemeDefaultsKey) as? Bool ?? true

        for asset in founderAssets {
            guard let imageURL = bundle.url(forResource: asset.resource, withExtension: "png"),
                  let data = try? Data(contentsOf: imageURL) else {
                return nil
            }
            let dataURI = "data:image/png;base64,\(data.base64EncodedString())"
            source = source.replacingOccurrences(of: asset.placeholder, with: dataURI)
        }

        source = source.replacingOccurrences(of: "__DSH_FOUNDER_THEME_ENABLED__", with: resolvedFounderEnabled ? "true" : "false")

        return WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }
}
