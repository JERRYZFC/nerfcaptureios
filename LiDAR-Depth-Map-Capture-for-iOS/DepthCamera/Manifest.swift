import Foundation

struct Manifest: Codable {
    let cameraType: String
    let intrinsics: [[Double]]
    var frames: [Frame]

    enum CodingKeys: String, CodingKey {
        case cameraType = "camera_type"
        case intrinsics
        case frames
    }
}

struct Frame: Codable {
    let filePath: String
    let depthPath: String
    let transformMatrix: [[Double]]

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case depthPath = "depth_path"
        case transformMatrix = "transform_matrix"
    }
}
