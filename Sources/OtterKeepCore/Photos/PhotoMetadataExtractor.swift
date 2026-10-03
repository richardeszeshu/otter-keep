import Foundation
import Photos

/// Extracts PhotoKit metadata (EXIF, IPTC, GPS coordinates, tags, albums) into standard XMP sidecar format.
public final class PhotoMetadataExtractor: Sendable {
    public init() {}

    /// Generates a standard XMP sidecar XML data for a given `PHAsset` and its associated albums.
    public func generateXMPSidecar(for asset: PHAsset, albums: [String] = []) -> Data? {
        var xmp = """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:exif="http://ns.adobe.com/exif/1.0/"
            xmlns:tiff="http://ns.adobe.com/tiff/1.0/">

        """

        let isoFormatter = ISO8601DateFormatter()

        if let creationDate = asset.creationDate {
            let dateStr = isoFormatter.string(from: creationDate)
            xmp += "   <xmp:CreateDate>\(dateStr)</xmp:CreateDate>\n"
            xmp += "   <photoshop:DateCreated>\(dateStr)</photoshop:DateCreated>\n"
        }

        if let modDate = asset.modificationDate {
            let modStr = isoFormatter.string(from: modDate)
            xmp += "   <xmp:ModifyDate>\(modStr)</xmp:ModifyDate>\n"
        }

        if asset.isFavorite {
            xmp += "   <photoshop:Urgency>1</photoshop:Urgency>\n"
        }

        if asset.pixelWidth > 0 && asset.pixelHeight > 0 {
            xmp += "   <tiff:ImageWidth>\(asset.pixelWidth)</tiff:ImageWidth>\n"
            xmp += "   <tiff:ImageLength>\(asset.pixelHeight)</tiff:ImageLength>\n"
        }

        if let location = asset.location {
            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude
            let latRef = lat >= 0 ? "N" : "S"
            let lonRef = lon >= 0 ? "E" : "W"

            xmp += "   <exif:GPSLatitude>\(abs(lat))\(latRef)</exif:GPSLatitude>\n"
            xmp += "   <exif:GPSLongitude>\(abs(lon))\(lonRef)</exif:GPSLongitude>\n"
            xmp += "   <exif:GPSLatitudeRef>\(latRef)</exif:GPSLatitudeRef>\n"
            xmp += "   <exif:GPSLongitudeRef>\(lonRef)</exif:GPSLongitudeRef>\n"
            if location.altitude != 0 {
                xmp += "   <exif:GPSAltitude>\(abs(location.altitude))</exif:GPSAltitude>\n"
            }
        }

        if !albums.isEmpty {
            xmp += "   <dc:subject>\n    <rdf:Bag>\n"
            for album in albums {
                let sanitized = album
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                xmp += "     <rdf:li>\(sanitized)</rdf:li>\n"
            }
            xmp += "    </rdf:Bag>\n   </dc:subject>\n"
        }

        xmp += """
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """

        return xmp.data(using: .utf8)
    }
}
