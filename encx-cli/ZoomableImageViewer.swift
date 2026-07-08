import SwiftUI
import UIKit

/// Full-screen, pinch-to-zoom image viewer with panning on both axes.
/// Presented when the player taps an image inside a task/hint/bonus WebView.
struct ZoomableImageViewer: View {
    let url: URL
    var onClose: () -> Void

    @State private var phase: LoadPhase = .loading

    private enum LoadPhase {
        case loading
        case loaded(UIImage)
        case failed
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .loading:
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
            case let .loaded(image):
                ZoomableScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                .ignoresSafeArea()
            case .failed:
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Не удалось загрузить изображение")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Link("Открыть в браузере", destination: url)
                        .font(.subheadline.weight(.semibold))
                        .tint(.white)
                }
                .padding()
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .accessibilityLabel("Закрыть")
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }
        }
        .task(id: url) {
            phase = .loading
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    phase = .loaded(image)
                } else {
                    phase = .failed
                }
            } catch {
                phase = .failed
            }
        }
    }
}

/// UIScrollView-backed zoom + pan container. UIScrollView gives correct
/// two-axis panning while zoomed, which a pure SwiftUI MagnificationGesture cannot.
private struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let hosted = context.coordinator.hostingController.view!
        hosted.translatesAutoresizingMaskIntoConstraints = false
        hosted.backgroundColor = .clear
        scrollView.addSubview(hosted)

        NSLayoutConstraint.activate([
            hosted.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hosted.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hosted.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hosted.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hosted.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hosted.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hostingController: UIHostingController(rootView: content))
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let hostingController: UIHostingController<Content>

        init(hostingController: UIHostingController<Content>) {
            self.hostingController = hostingController
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: hostingController.view)
                let targetScale = min(scrollView.maximumZoomScale, 3)
                let size = scrollView.bounds.size
                let width = size.width / targetScale
                let height = size.height / targetScale
                let rect = CGRect(
                    x: point.x - width / 2,
                    y: point.y - height / 2,
                    width: width,
                    height: height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
