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
        // Circle bottom sits on the geographic coordinate point
        centerOffset = CGPoint(x: 0, y: -18)
        // Group nearby pins under one cluster identifier
        clusteringIdentifier = "drivelike"

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
    var onPinTap: ((LikedTrack, CGPoint) -> Void)? = nil
    var onPositionUpdate: ((CGPoint) -> Void)? = nil

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
        context.coordinator.onPositionUpdate = onPositionUpdate

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

    func makeCoordinator() -> Coordinator {
        Coordinator(onPinTap: onPinTap, onPositionUpdate: onPositionUpdate)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onPinTap: ((LikedTrack, CGPoint) -> Void)?
        var onPositionUpdate: ((CGPoint) -> Void)?
        var selectedCoordinate: CLLocationCoordinate2D?

        init(onPinTap: ((LikedTrack, CGPoint) -> Void)?,
             onPositionUpdate: ((CGPoint) -> Void)?) {
            self.onPinTap = onPinTap
            self.onPositionUpdate = onPositionUpdate
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                // MKMarkerAnnotationView is battle-tested with didSelect — no custom class needed
                let v = MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: nil)
                v.markerTintColor = UIColor(red: 0.114, green: 0.729, blue: 0.333, alpha: 1)
                v.glyphText = "\(cluster.memberAnnotations.count)"
                v.titleVisibility = .hidden
                v.subtitleVisibility = .hidden
                return v
            }
            guard annotation is TrackAnnotation else { return nil }
            return map.dequeueReusableAnnotationView(withIdentifier: GreenPinAnnotationView.reuseId,
                                                     for: annotation)
        }

        func mapView(_ map: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                map.deselectAnnotation(cluster, animated: false)
                // Zoom to ~100 m span; mapViewDidChangeVisibleRegion then kills
                // clusteringIdentifier so pins always show individually at this level
                map.setRegion(
                    MKCoordinateRegion(
                        center: cluster.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)),
                    animated: true)
                return
            }

            guard let ann = view.annotation as? TrackAnnotation else { return }
            selectedCoordinate = ann.coordinate
            let pt = map.convert(ann.coordinate, toPointTo: map)
            map.deselectAnnotation(ann, animated: false)
            onPinTap?(ann.track, pt)
        }

        func mapViewDidChangeVisibleRegion(_ map: MKMapView) {
            // Update callout popup position
            if let coord = selectedCoordinate {
                onPositionUpdate?(map.convert(coord, toPointTo: map))
            }

            // Above 0.003° (~300 m): cluster overlapping pins.
            // Below 0.003°: disable clustering so every pin is individually tappable
            // even if they share nearly the same coordinate.
            let shouldCluster = map.region.span.latitudeDelta > 0.003
            for annotation in map.annotations where annotation is TrackAnnotation {
                (map.view(for: annotation) as? GreenPinAnnotationView)?
                    .clusteringIdentifier = shouldCluster ? "drivelike" : nil
            }
        }
    }
}

// MARK: - Callout Bubble Shape

private struct CalloutBubble: Shape {
    var cornerRadius: CGFloat = 14
    var arrowWidth: CGFloat = 14
    var arrowHeight: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let card = CGRect(x: rect.minX, y: rect.minY,
                          width: rect.width, height: rect.height - arrowHeight)
        let mid = rect.midX
        var p = Path()
        p.move(to: CGPoint(x: card.minX + r, y: card.minY))
        p.addLine(to: CGPoint(x: card.maxX - r, y: card.minY))
        p.addArc(center: CGPoint(x: card.maxX - r, y: card.minY + r),
                 radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: card.maxX, y: card.maxY - r))
        p.addArc(center: CGPoint(x: card.maxX - r, y: card.maxY - r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: mid + arrowWidth / 2, y: card.maxY))
        p.addLine(to: CGPoint(x: mid, y: rect.maxY))
        p.addLine(to: CGPoint(x: mid - arrowWidth / 2, y: card.maxY))
        p.addLine(to: CGPoint(x: card.minX + r, y: card.maxY))
        p.addArc(center: CGPoint(x: card.minX + r, y: card.maxY - r),
                 radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: card.minX, y: card.minY + r))
        p.addArc(center: CGPoint(x: card.minX + r, y: card.minY + r),
                 radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Popup geometry

private enum Callout {
    static let width: CGFloat       = 260
    static let cardHeight: CGFloat  = 68
    static let arrowHeight: CGFloat = 9
    static var totalHeight: CGFloat { cardHeight + arrowHeight }

    // coordPt.y = geographic coordinate = bottom of pin circle.
    // Circle top = coordPt.y - 36.  Gap above circle = 42 pt (6 original + 36 = one diameter).
    // Arrow tip  = coordPt.y - 36 - 42 = coordPt.y - 78.
    // Popup center = arrowTip - totalHeight / 2.
    static func centerY(from coordPt: CGPoint) -> CGFloat {
        coordPt.y - 78 - totalHeight / 2
    }

    static func clampedX(_ x: CGFloat) -> CGFloat {
        let half = width / 2 + 12
        return min(max(x, half), UIScreen.main.bounds.width - half)
    }
}

// MARK: - Full-Screen Drive Map

struct DriveMapView: View {
    let tracks: [LikedTrack]
    @Binding var trackDetails: [String: TrackDetails]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTrack: LikedTrack?
    @State private var pinCoordPoint: CGPoint = .zero

    private let api = SpotifyAPIManager.shared

    var body: some View {
        ZStack(alignment: .top) {
            MapKitMapView(
                tracks: tracks,
                interactive: true,
                onPinTap: { tapped, coordPt in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        selectedTrack = tapped
                        pinCoordPoint = coordPt
                    }
                },
                onPositionUpdate: { newPt in
                    pinCoordPoint = newPt
                }
            )
            .ignoresSafeArea()

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

            if let track = selectedTrack {
                TrackPinPopup(
                    track: track,
                    details: trackDetails[track.trackId],
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.18)) { selectedTrack = nil }
                    }
                )
                .position(
                    x: Callout.clampedX(pinCoordPoint.x),
                    y: Callout.centerY(from: pinCoordPoint)
                )
                .transition(.scale(scale: 0.78, anchor: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityLabel("Song map with \(tracks.count) pins")
        .onAppear { fetchMissingDetails() }
    }

    // Fetch album art for any map track not already in the details cache
    private func fetchMissingDetails() {
        for track in tracks where trackDetails[track.trackId] == nil {
            Task {
                guard let details = try? await api.getTrackDetails(id: track.trackId) else { return }
                await MainActor.run {
                    trackDetails[track.trackId] = details
                    var cache = SharedStore.readTrackDetailsCache()
                    cache[track.trackId] = details
                    SharedStore.writeTrackDetailsCache(cache)
                }
            }
        }
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
        ZStack {
            CalloutBubble(cornerRadius: 14, arrowWidth: 14, arrowHeight: Callout.arrowHeight)
                .fill(.ultraThinMaterial)
            CalloutBubble(cornerRadius: 14, arrowWidth: 14, arrowHeight: Callout.arrowHeight)
                .stroke(Color.accent.opacity(0.45), lineWidth: 1)

            HStack(spacing: 10) {
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
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.trackName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrim)
                        .lineLimit(1)
                    Text(track.artistName)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                    Text(likedTimeString)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accent)
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.textMuted)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.surface.opacity(0.5)))
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, Callout.arrowHeight)
            .frame(height: Callout.totalHeight)
        }
        .frame(width: Callout.width, height: Callout.totalHeight)
        .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.trackName) by \(track.artistName), liked \(likedTimeString)")
    }

    private var placeholderArt: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.surface)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .thin))
                    .foregroundStyle(Color.textMuted)
            )
    }
}

// MARK: - Map Preview Card

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
            Image(systemName: "map")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(Color.textMuted.opacity(0.4))
        }
    }
}
