import Foundation

struct Manifest: Codable {
    var flX: Float
    var flY: Float
    var cX: Float
    var cY: Float
    var w: Int
    var h: Int
    var integerDepthScale: Float
    var frames: [Frame]

    enum CodingKeys: String, CodingKey {
        case flX = "fl_x"
        case flY = "fl_y"
        case cX = "cx"
        case cY = "cy"
        case w
        case h
        case integerDepthScale = "integer_depth_scale"
        case frames
    }
}

struct Frame: Codable {
    let filePath: String
    let depthPath: String
    let transformMatrix: [[Float]]

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case depthPath = "depth_path"
        case transformMatrix = "transform_matrix"
    }
}
