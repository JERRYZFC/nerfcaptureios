import Foundation

struct Manifest: Codable {
    var cameraAngleX: Float
    var cameraAngleY: Float
    var flX: Float
    var flY: Float
    var cx: Float
    var cy: Float
    var w: Int
    var h: Int
    var frames: [Frame]

    struct Frame: Codable {
        var filePath: String
        var depthPath: String
        var transformMatrix: [[Float]]
        var timestamp: TimeInterval

        enum CodingKeys: String, CodingKey {
            case filePath = "file_path"
            case depthPath = "depth_path"
            case transformMatrix = "transform_matrix"
            case timestamp
        }
    }

    enum CodingKeys: String, CodingKey {
        case cameraAngleX = "camera_angle_x"
        case cameraAngleY = "camera_angle_y"
        case flX = "fl_x"
        case flY = "fl_y"
        case cx
        case cy
        case w
        case h
        case frames
    }
}
