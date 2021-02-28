import SwiftUI

struct OptionalImage: View {
    var uiImage: UIImage?

    var body: some View {
        // group doesnt modify layout
        Group {
            if let uiImage = uiImage {
                Image(uiImage: uiImage)
            }
        }
    }
}

