import SwiftUI
import AVKit
import AVFoundation
import CoreImage

// MARK: - AVPlayerViewController wrapper that mirrors ONLY video frames
struct MirroredAVPlayerControllerView: UIViewControllerRepresentable {
    let url: URL
    var loop: Bool = true

    final class Coordinator {
        var endObserver: Any?
        var player: AVPlayer?
        
        deinit { 
            if let endObserver { 
                NotificationCenter.default.removeObserver(endObserver) 
            }
            player?.pause()
            player = nil
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        configurePlayer(on: vc, coordinator: context.coordinator)
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        // Reconfigure only if URL changed
        if let current = (vc.player?.currentItem?.asset as? AVURLAsset)?.url, current == url { return }
        configurePlayer(on: vc, coordinator: context.coordinator)
    }
    
    private func configurePlayer(on vc: AVPlayerViewController, coordinator: Coordinator) {
        let asset = AVURLAsset(url: url)

        // Build a mirrored composition using CIFilters (very robust across orientations)
        let composition = AVVideoComposition(asset: asset) { request in
            let src = request.sourceImage
            let extent = src.extent
            // Mirror horizontally in pixel space, keep UI normal
            let flipped = src.transformed(by:
                CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -extent.width, y: 0)
            )
            request.finish(with: flipped, context: nil)
        }

        let item = AVPlayerItem(asset: asset)
        item.videoComposition = composition

        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        vc.player = player
        coordinator.player = player

        // Loop if requested
        if loop {
            if let obs = coordinator.endObserver { NotificationCenter.default.removeObserver(obs) }
            coordinator.endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                // Use a more efficient looping approach
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                player.play()
            }
        }

        // Kick playback next runloop
        DispatchQueue.main.async {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
        }
    }
}

// MARK: - SwiftUI view that preserves original aspect and fills most of the screen height
struct AdaptiveMirroredPlayer: View {
    let url: URL
    var heightFraction: CGFloat = 0.8  // ~80% of available height

    @State private var aspect: CGFloat?  // width / height
    @State private var isPlayerReady = false

    var body: some View {
        GeometryReader { geo in
            let maxH = geo.size.height * heightFraction

            Group {
                if let aspect, isPlayerReady {
                    let fullW = geo.size.width
                    let hByFullW = fullW / aspect
                    let useFullWidth = hByFullW <= maxH
                    let width  = useFullWidth ? fullW    : maxH * aspect
                    let height = useFullWidth ? hByFullW : maxH

                    MirroredAVPlayerControllerView(url: url, loop: true)
                        .frame(width: width, height: height)
                        .clipped()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .onAppear {
                            // Mark player as ready to reduce unnecessary observations
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isPlayerReady = true
                            }
                        }
                } else {
                    ProgressView().onAppear(perform: computeAspect)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.black.ignoresSafeArea())
        }
    }

    // Load tracks asynchronously to avoid race conditions
    private func computeAspect() {
        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
            var loaded = false
            var err: NSError?
            switch asset.statusOfValue(forKey: "tracks", error: &err) {
            case .loaded: loaded = true
            default: break
            }
            guard loaded, let track = asset.tracks(withMediaType: .video).first else {
                DispatchQueue.main.async { 
                    self.aspect = 9.0 / 16.0 // fallback
                    self.isPlayerReady = true
                }
                return
            }

            // Use display-corrected size (naturalSize * preferredTransform)
            let corrected = track.naturalSize.applying(track.preferredTransform)
            let w = abs(corrected.width), h = abs(corrected.height)
            let a = (w > 0 && h > 0) ? (w / h) : (9.0 / 16.0)
            DispatchQueue.main.async { 
                self.aspect = a
                self.isPlayerReady = true
            }
        }
    }
}
