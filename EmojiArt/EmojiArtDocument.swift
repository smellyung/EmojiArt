import SwiftUI
import Combine

class EmojiArtDocument: ObservableObject {

    static let palette: String = "🐛🍎🍌🚕🚨🚖🦕🐍🦧🍀🌴🌲🌝🌜🌼🌸"

    private static let untitled = "EmojiArtDocument.Untitled"

    // these are 'Never' fail types
    @Published private var emojiArt: EmojiArt

    @Published private(set) var backgroundImage: UIImage?

    // lives as long as the VM does
    private var autosaveCancellable: AnyCancellable? // type from Combine

    init() {
        // re-instate EmojiArt aaved state
        emojiArt = EmojiArt(json: UserDefaults.standard.data(forKey: EmojiArtDocument.untitled)) ?? EmojiArt()

        // subscribed to emojiArt publisher
        autosaveCancellable = $emojiArt.sink { emojiArt in
            print("json = \(emojiArt.json?.utf8 ?? "nil")")
            UserDefaults.standard.set(emojiArt.json, forKey: EmojiArtDocument.untitled)
        }
        fetchBackgroundImageData()
    }

    var emojis: [EmojiArt.Emoji] { emojiArt.emojis }

    // MARK: - Intent(s)


    func addEmoji(_ emoji: String, at location: CGPoint, size: CGFloat) {
        emojiArt.addEmoji(emoji, x: Int(location.x), y: Int(location.y), size: Int(size))
    }

    func moveEmoji(_ emoji: EmojiArt.Emoji, by offset: CGSize) {
        if let index = emojiArt.emojis.firstIndex(matching: emoji) {
            emojiArt.emojis[index].x += Int(offset.width)
            emojiArt.emojis[index].y += Int(offset.height)
        }
    }

    func scaleEmoji(_ emoji: EmojiArt.Emoji, by scale: CGFloat) {
        if let index = emojiArt.emojis.firstIndex(matching: emoji) {
            emojiArt.emojis[index].size = Int((CGFloat(emojiArt.emojis[index].size) * scale).rounded(.toNearestOrEven))
        }
    }

    var backgroundURL: URL? {
        get {
            emojiArt.backgroundURL
        }
        set {
            emojiArt.backgroundURL = newValue?.imageURL
            fetchBackgroundImageData()
        }
    }

    private var fetchImageCancellable: AnyCancellable?

    func fetchBackgroundImageData() {
        backgroundImage = nil
        if let url = self.emojiArt.backgroundURL {
            fetchImageCancellable?.cancel()

            fetchImageCancellable = URLSession.shared.dataTaskPublisher(for: url)
                .map { data, urlResponse in UIImage(data: data) }
                .receive(on: DispatchQueue.main)
                .replaceError(with: nil) // error type changed to Never
                .assign(to: \EmojiArtDocument.backgroundImage, on: self)

            // fetching image data could take a while and we dont want the UI to freeze
//            DispatchQueue.global(qos: .userInitiated).async {
//                if let imageData = try? Data(contentsOf: url) {
//
//                    // we don't want the view to redraw on background thread
//                    DispatchQueue.main.async {
//                        // protect against user dragging in another image before this one has loaded
//                        if url == self.emojiArt.backgroundURL {
//                            self.backgroundImage = UIImage(data: imageData)
//                        }
//                    }
//                }
//            }
        }
    }
}

// doesnt violate MVVM since it lives in VM
// don't have to deal with ints in View
extension EmojiArt.Emoji {
    var fontSize: CGFloat { CGFloat(self.size) }
    var location: CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
}
