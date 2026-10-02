import UIKit

/// Prepares a picked image for upload.
///
/// Re-encoding through `UIImage` drops every metadata block with it — which is
/// the point as much as the size saving. A photo straight from the library
/// carries GPS coordinates, and a reflection is shared with a group; shipping
/// someone's location alongside it is the client's problem to prevent, not the
/// backend's.
enum ImagePrep {
    /// The backend accepts 15 MB for reflections and 5 MB for avatars; both
    /// are far above what a 1600px long edge produces.
    static func jpeg(from data: Data,
                     maxLongEdge: CGFloat = 1_600,
                     quality: CGFloat = 0.82) -> (fileURL: URL, mime: String)? {
        guard let image = UIImage(data: data) else { return nil }
        let scaled = downscale(image, maxLongEdge: maxLongEdge)
        guard let jpeg = scaled.jpegData(compressionQuality: quality) else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        do {
            try jpeg.write(to: url)
            return (url, "image/jpeg")
        } catch {
            return nil
        }
    }

    private static func downscale(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxLongEdge else { return image }
        let scale = maxLongEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
