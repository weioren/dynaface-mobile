import SwiftUI
import AVKit

struct PastExerciseView: View {
    let videoURL: URL
    let exerciseTitle: String
    let recordingDate: String
    
    @Environment(\.presentationMode) var presentationMode
    @State private var player: AVPlayer?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title and date
            VStack(spacing: 8) {
                Text(exerciseTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(recordingDate)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.black.opacity(0.3))
            
            // Video player taking up most of the screen
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(9/16, contentMode: .fit) // Changed to 9/16 for vertical videos
                    .background(Color.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Placeholder while video loads
                Rectangle()
                    .fill(Color.black)
                    .aspectRatio(9/16, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    )
            }
        }
        .background(Color.black)
        .navigationBarBackButtonHidden(false)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func setupPlayer() {
        player = AVPlayer(url: videoURL)
        
        // Set up looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            player?.play()
        }
        
        // Start playing automatically
        player?.play()
    }
}

// MARK: - Preview
#Preview {
    PastExerciseView(
        videoURL: URL(fileURLWithPath: "/path/to/video.mov"),
        exerciseTitle: "Sample Exercise",
        recordingDate: "Jan 15, 2024 at 2:30 PM"
    )
}

