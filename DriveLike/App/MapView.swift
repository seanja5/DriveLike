import SwiftUI
import MapKit

// MARK: - Map Annotation

final class TrackAnnotation: NSObject, MKAnnotation {
    let track: LikedTrack
    let coordinate: CLLocationCoordinate2D
    var title: String? { track.trackName }

    init(track: LikedTrack, coordinate: CLLocationCoordinate2D) {
        self.track = track
        self.coordinate = coordinate
    }
}

// MARK: - Green Pin Annotation View

final class GreenPinAnnotationView: MKAnnotationView {
    static let reuseId = "GreenPin"

    private let circle = UIView()
    private let heartIcon = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func configure() {
        frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        centerOffset = CGPoint(x: 0, y: -18)

        circle.frame = bounds
        circle.layer.cornerRadius = 18
        circle.backgroundColor = UIColor(red: 0.114, green: 0.729, blue: 0.333, alpha: 1)
        circle.layer.shadowColor = UIColor(red: 0.114, green: 0.729, blue: 0.333, alpha: 0.55).cgColor
        circle.layer.shadowRadius = 8
        circle.layer.shadowOpacity = 1
        circle.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(circle)

        let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        heartIcon.image = UIImage(systemName: "heart.fill", withConfiguration: cfg)
        heartIcon.tintColor = .white
        heartIcon.contentMode = .scaleAspectFit
        heartIcon.frame = CGRect(x: 8, y: 8, width: 20, height: 20)
        addSubview(heartIcon)
    }

    override var isSelected: Bool {
        didSet {
            UIView.animate(
                withDuration: 0.18, delay: 0,
                usingSpringWithDamping: 0.72, initialSpringVelocity: 0,
                options: [.allowUserInteraction], animations: {
                    self.transform = self.isSelected
                        ? CGAffineTransform(scaleX: 1.2, y: 1.2)
                        : .identity
                    self.circle.layer.borderWidth = self.isSelected ? 2.5 : 0
                    self.circle.layer.borderColor = UIColor.white.cgColor
                }, completion: nil)
        }
    }
}

// MARK: - MapKit UIViewRepresentable

struct MapKitMapView: UIViewRepresentable {
    let tracks: [LikedTrack]
    let interactive: Bool
    var onPinTap: ((LikedTrack) -> Void)? = nil

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.overrideUserInterfaceStyle = .dark
        map.mapType = .standard
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        map.isRotateEnabled = interactive
        map.isPitchEnabled = false
        map.showsUserLocation = false
        map.showsCompass = false
        map.showsScale = false
        map.delegate = context.coordinator
        map.register(GreenPinAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: GreenPinAnnotationView.reuseId)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onPinTap = onPinTap

        let existing = map.annotations.compactMap { $0 as? TrackAnnotation }
        let existingIds = Set(existing.map { $0.track.trackId })
        let newTracks = tracks.filter { $0.latitude != nil && $0.longitude != nil }
        let newIds = Set(newTracks.map { $0.trackId })

        guard existingIds != newIds else { return }

        map.removeAnnotations(existing)
        let annotations = newTracks.map {
            TrackAnnotation(track: $0, coordinate: CLLocationCoordinate2D(
                latitude: $0.latitude!, longitude: $0.longitude!))
        }
        map.addAnnotations(annotations)

        guard !annotations.isEmpty else { return }

        if interactive {
            map.showAnnotations(annotations, animated: false)
        } else {
            let meanLat = annotations.map(\.coordinate.latitude).reduce(0, +) / Double(annotations.count)
            let meanLon = annotations.map(\.coordinate.longitude).reduce(0, +) / Double(annotations.count)
            map.setRegion(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: meanLat, longitude: meanLon),
                span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
            ), animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPinTap: onPinTap) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onPinTap: ((LikedTrack) -> Void)?

        init(onPinTap: ((LikedTrack) -> Void)?) { self.onPinTap = onPinTap }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is TrackAnnotation else { return nil }
            return map.dequeueReusableAnnotationView(withIdentifier: GreenPinAnnotationView.reuseId,
                                                     for: annotation)
        }

        func mapView(_ map: MKMapView, didSelect view: MKAnnotationView) {
            guard let ann = view.annotation as? TrackAnnotation else { return }
            map.deselectAnnotation(ann, animated: false)
            onPinTap?(ann.track)
        }
    }
}

// MARK: - Full-Screen Drive Map

struct DriveMapView: View {
    let tracks: [LikedTrack]
    let trackDetails: [String: TrackDetails]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTrack: LikedTrack?

    var body: some View {
        ZStack(alignment: .top) {
            MapKitMapView(tracks: tracks, interactive: true) { tapped in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedTrack = tapped
                }
            }
            .ignoresSafeArea()

            // Transparent tap area to dismiss pin popup when tapping the map
            if selectedTrack != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) { selectedTrack = nil }
                    }
                    .ignoresSafeArea()
            }

            // Back button
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Drives")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color.textPrim)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().strokeBorder(Color.border, lineWidth: 1))
                    )
                }
                .buttonStyle(PressScaleStyle())
                .padding(.leading, 16)
                Spacer()
            }
            .padding(.top, 8)

            // Pin popup
            VStack {
                Spacer()
                if let track = selectedTrack {
                    TrackPinPopup(
                        track: track,
                        details: trackDetails[track.trackId],
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.2)) { selectedTrack = nil }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityLabel("Song map with \(tracks.count) pins")
    }
}

// MARK: - Track Pin Popup

struct TrackPinPopup: View {
    let track: LikedTrack
    let details: TrackDetails?
    let onDismiss: () -> Void

    private var likedTimeString: String {
        let df = DateFormatter()
        df.dateFormat = "MMM d · h:mm a"
        return df.string(from: track.likedAt)
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let urlStr = details?.albumArtURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                        default: placeholderArt
                        }
                    }
                } else {
                    placeholderArt
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(track.trackName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrim)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
                Text(likedTimeString)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted.opacity(0.7))
            }

            Spacer(minLength: 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.border, lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 36)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.trackName) by \(track.artistName), liked \(likedTimeString)")
    }

    private var placeholderArt: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.surface)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .thin))
                    .foregroundStyle(Color.textMuted)
            )
    }
}

// MARK: - Map Preview Card (embedded in DrivesView)

struct MapPreviewCard: View {
    let tracks: [LikedTrack]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                if tracks.isEmpty {
                    noLocationView
                } else {
                    MapKitMapView(tracks: tracks, interactive: false)
                }

                // Glass label bar
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accent)
                    Text(tracks.isEmpty
                         ? "Like from the lock screen to map your drives"
                         : "\(tracks.count) song\(tracks.count == 1 ? "" : "s") pinned on the map")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrim)
                        .lineLimit(1)
                    Spacer()
                    if !tracks.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Rectangle().fill(Color.white.opacity(0.03)))
                )
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(tracks.isEmpty)
        .accessibilityLabel(tracks.isEmpty
            ? "No location data yet"
            : "View \(tracks.count) songs on map")
    }

    private var noLocationView: some View {
        ZStack {
            Color.bgBase
            VStack(spacing: 10) {
                Image(systemName: "map")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundStyle(Color.textMuted.opacity(0.4))
            }
        }
    }
}

