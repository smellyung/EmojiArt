import SwiftUI

struct EmojiArtDocumentView: View {
    @ObservedObject var document: EmojiArtDocument

    @State private var chosenPalette: String = ""

    init(document: EmojiArtDocument) {
        self.document = document
        // set the actual state value in init (instead of onAppear)
        _chosenPalette = State(wrappedValue: self.document.defaultPalette)
    }

    var body: some View {
        VStack {
            HStack {
                PaletteChooser(document: document, chosenPalette: $chosenPalette) // projectedValue of our state in this View
                ScrollView(.horizontal) {
                    HStack {
                        // ForEach exoects an array of Identifiables (can do == on)
                        // \ (keyPath)
                        ForEach(chosenPalette.map { String($0) }, id: \.self) { emoji in
                            Text(emoji)
                                .font(.system(size: defaultEmojiSize))
                                .onDrag { NSItemProvider(object: emoji as NSString) }
                        }
                    }
                }
            }
            GeometryReader { geometry in
                ZStack {
                    Color.white.overlay(
                        OptionalImage(uiImage: self.document.backgroundImage)
                            .scaleEffect(self.zoomScale)
                            .offset(self.panOffset)
                    )
                    .gesture(self.doubleTapToZoom(in: geometry.size))
                    if self.isLoading {
                        Image(systemName: "hourglass").imageScale(.large).spinning()
                    } else {
                        ForEach(self.document.emojis) { emoji in
                            Text(emoji.text)
                                .font(animatableWithSize: emoji.fontSize * zoomScale)
                                .position(self.position(for: emoji, in: geometry.size))
                                .offset(self.panOffset)
                        }
                    }
                }
                .clipped()
                .gesture(self.panGesture())
                .gesture(self.zoomGesture())
                .edgesIgnoringSafeArea([.horizontal, .bottom])
                // $backgroundImage publisher
                .onReceive(self.document.$backgroundImage) { image in
                    self.zoomToFit(image, in: geometry.size)
                }
                .onDrop(of: ["public.image", "public.text"], isTargeted: nil) { providers, location in
                    var location = geometry.convert(location, from: .global)
                    location = CGPoint(x: location.x - geometry.size.width / 2, y: location.y - geometry.size.height / 2)
                    location = CGPoint(x: location.x - self.panOffset.width , y: location.y - self.panOffset.height)
                    location = CGPoint(x: location.x / self.zoomScale, y: location.y / self.zoomScale)
                    return self.drop(providers: providers, location: location)
                }
                .navigationBarItems(leading: self.pickImage, trailing: Button(action: {
                    if let url = UIPasteboard.general.url, url != self.document.backgroundURL{
                        self.confirmBackgroundPaste = true
                    } else {
                        self.explainBackgroundPaste = true
                    }
                }, label: {
                    Image(systemName: "doc.on.clipboard").imageScale(.large)
                        .alert(isPresented: self.$explainBackgroundPaste) {
                            return Alert(
                                title: Text("Paste Background"),
                                message: Text("Copy the URL of an image to the clip board and touch this button to make it the background of your document"),
                                dismissButton: .default(Text("OK"))
                            )
                        }
                }))
            }
            .alert(isPresented: self.$confirmBackgroundPaste) {
                Alert(
                    title: Text("Paste Background"),
                    message: Text("Replace your background with \(UIPasteboard.general.url?.absoluteString ?? "nothing")?"),
                    primaryButton: .default(Text("OK")) {
                        self.document.backgroundURL = UIPasteboard.general.url
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    @State private var imagePickerSourceType = UIImagePickerController.SourceType.photoLibrary
    @State private var showImagePicker = false

    private var pickImage: some View {
        HStack {
            Image(systemName: "photo").imageScale(.large).foregroundColor(.accentColor).onTapGesture {
                self.imagePickerSourceType = .photoLibrary
                self.showImagePicker = true
            }
            // TODO: doesn't open camera
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Image(systemName: "camera").imageScale(.large).foregroundColor(.accentColor).onTapGesture {
                    self.imagePickerSourceType = .camera
                    self.showImagePicker = true
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: imagePickerSourceType) { image in
                if image != nil {
                    // delaying this while
                    DispatchQueue.main.async {
                        self.document.backgroundURL = image?.storeInFilesystem()
                    }
                }
                self.showImagePicker = false
            }
        }
    }

    @State private var explainBackgroundPaste = false
    @State private var confirmBackgroundPaste = false

    var isLoading: Bool {
        document.backgroundURL != nil && document.backgroundImage == nil
    }

    // MARK: - Gestures
    @GestureState private var gestureZoomScale: CGFloat = 1.0

    private var zoomScale: CGFloat {
        document.steadyStateZoomScale * gestureZoomScale
    }

    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            // $ = binding
            .updating($gestureZoomScale) { (latestGestureScale, ourGestureStateInOut, transaction) in
                // ourGestureStateInOut == gestureZoomeScale
                // can rename var to GestureState name so we can do
                // gestureZoomScale *= latestGestureScale
                ourGestureStateInOut *= latestGestureScale
            }
            .onEnded { finalGestureScale in
                self.document.steadyStateZoomScale *= finalGestureScale
            }
    }

    @GestureState private var gesturePanOffset: CGSize = .zero

    private var panOffset: CGSize {
        (document.steadyStatePanOffset + gesturePanOffset) * zoomScale
    }

    private func panGesture() -> some Gesture {
        DragGesture()
            .updating($gesturePanOffset) { (latestDragGestureValue, gesturePanOffset, transaction) in
                gesturePanOffset = latestDragGestureValue.translation / self.zoomScale
            }
            .onEnded { finalDragGestureValue in
                self.document.steadyStatePanOffset = self.document.steadyStatePanOffset + (finalDragGestureValue.translation / self.zoomScale)
            }
    }

    // MARK: -

    private func doubleTapToZoom(in size: CGSize) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation {
                    self.zoomToFit(self.document.backgroundImage, in: size)
                }
            }
    }

    private func zoomToFit(_ image: UIImage?, in size: CGSize) {
        if let image = image, image.size.width > 0, image.size.height > 0, size.height > 0, size.width > 0 {
            let hZoom = size.width / image.size.width
            let vZoom = size.height / image.size.height

            // image will always fully be on screen
            self.document.steadyStatePanOffset = .zero
            self.document.steadyStateZoomScale = min(hZoom, vZoom)
        }
    }

    private func position(for emoji: EmojiArt.Emoji, in size: CGSize) -> CGPoint {
        var location = emoji.location
        location = CGPoint(x: location.x * zoomScale, y: location.y * zoomScale)
        location = CGPoint(x: emoji.location.x + size.width / 2, y: emoji.location.y + size.height / 2)
        location = CGPoint(x: location.x + panOffset.width, y: location.y + panOffset.height)
        return location
    }

    private func drop(providers: [NSItemProvider], location: CGPoint) -> Bool {
        var found = providers.loadFirstObject(ofType: URL.self) { url in
            print("dropped \(url)")
            self.document.backgroundURL = url
        }
        if !found {
            found = providers.loadObjects(ofType: String.self) { string in
                self.document.addEmoji(string, at: location, size: self.defaultEmojiSize)
            }
        }
        return found
    }

    private let defaultEmojiSize: CGFloat = 40
}

//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}
