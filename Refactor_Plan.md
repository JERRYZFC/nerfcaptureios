# LiDAR-Depth-Map-Capture-for-iOS 重构计划

## 1. 核心目标

将 `LiDAR-Depth-Map-Capture-for-iOS` 项目的输出，从零散的单帧文件，重构为与主流3D重建工具链（如 Gaussian Splatting, NeRF, Luma AI 等）兼容的、结构化的数据集。

最终输出应为一个 `.zip` 压缩包，其内部结构如下：

```
[YYMMddHHmmss]/      # 以时间戳命名的项目文件夹
├── images/           # 存放所有图像和深度数据的文件夹
│   ├── 0.jpg         # RGB图像 (或 .png)
│   ├── 0.depth.tiff  # 32位浮点无损深度图
│   ├── 1.jpg
│   ├── 1.depth.tiff
│   └── ...
└── transforms.json   # 核心元数据文件
```

## 2. 待办任务与实施步骤

### 第一阶段：UI/UX 和状态管理

**目标**: 将单次拍摄模式改为连续的“录制会话”模式。

**涉及文件**:
*   `ARViewModel.swift`
*   `ContentView.swift`
*   `CaptureButton.swift`
*   `CaptureButtonPanelView.swift`

**步骤**:

1.  **修改 `ARViewModel.swift`**:
    *   移除 `captureSuccessful` 和 `lastCapture` 等与单次捕获相关的 `@Published` 变量。
    *   添加一个新的状态变量：`@Published var isRecording: Bool = false`。
    *   添加一个新的 `DatasetWriter` 实例变量，用于处理文件写入。

2.  **修改 `CaptureButton.swift` 和 `CaptureButtonPanelView.swift`**:
    *   修改按钮的视觉样式，使其能反映“录制中”和“未录制”两种状态（例如，从一个圆形变成一个方形，或者改变颜色）。
    *   修改按钮的 `action`：
        *   不再调用 `model.saveDepthMap()`。
        *   改为切换 `arViewModel.isRecording` 的布尔值。

3.  **修改 `ContentView.swift`**:
    *   根据 `arViewModel.isRecording` 的状态，更新UI，例如显示一个红色的录制指示灯或计时器。

### 第二阶段：数据结构和写入逻辑

**目标**: 创建一个专门的数据写入模块，并定义 `transforms.json` 的数据结构。

**步骤**:

1.  **创建 `Manifest.swift` 文件**:
    *   在 `LiDAR-Depth-Map-Capture-for-iOS/DepthCamera/` 目录下创建一个新的Swift文件 `Manifest.swift`。
    *   在其中定义两个 `Codable` 结构体：
        *   `Manifest`: 包含相机类型、内参和 `frames` 数组。
        *   `Frame`: 包含 `file_path`, `depth_path`, 和 `transform_matrix`。

2.  **创建 `DatasetWriter.swift` 文件**:
    *   在 `LiDAR-Depth-Map-Capture-for-iOS/DepthCamera/` 目录下创建一个新的Swift文件 `DatasetWriter.swift`。
    *   这个类将包含以下核心功能：
        *   `initializeProject()`: 当开始录制时调用。负责创建时间戳文件夹和 `images` 子文件夹，并初始化一个空的 `Manifest` 对象。
        *   `addFrame(frame: ARFrame)`: 在录制过程中，由 `ARViewModel` 的 `session(_:didUpdate:)` 代理方法在每一帧调用。此方法负责：
            *   保存RGB图像到 `images` 目录。
            *   使用 `libtiff` 将 `frame.sceneDepth.depthMap` 中的 `Float32` 数据无损保存为 `.tiff` 文件到 `images` 目录。
            *   从 `frame.camera` 中提取内参和4x4变换矩阵。
            *   创建一个 `Frame` 对象并追加到 `Manifest` 的 `frames` 数组中。
        *   `finalizeProject()`: 当停止录制时调用。负责：
            *   将内存中的 `Manifest` 对象编码为JSON。
            *   将JSON数据写入项目根目录下的 `transforms.json` 文件。
            *   （可选）调用 `Zip` 库将整个项目文件夹打包成 `.zip` 文件。

### 第三阶段：整合与重构

**目标**: 将新的UI、状态管理和数据写入逻辑整合到一起。

**步骤**:

1.  **重构 `ARViewModel.swift`**:
    *   移除旧的 `saveDepthMap()` 函数。
    *   修改 `session(_:didUpdate:)` 函数：
        *   添加一个判断 `if isRecording { ... }`。
        *   在判断为真时，调用 `datasetWriter.addFrame(frame: frame)`。
    *   添加 `startRecording()` 和 `stopRecording()` 两个函数，分别调用 `datasetWriter.initializeProject()` 和 `datasetWriter.finalizeProject()`。

2.  **更新 `CaptureButton.swift`**:
    *   确保按钮的 `action` 正确调用 `arViewModel.startRecording()` 和 `arViewModel.stopRecording()`。

3.  **项目配置**:
    *   将新创建的 `Manifest.swift` 和 `DatasetWriter.swift` 文件添加到 Xcode 项目 (`project.pbxproj`) 的编译目标中。
    *   确保 `Zip` 库（如果需要打包功能）已经被正确地添加到项目的依赖中。

完成以上步骤后，`LiDAR-Depth-Map-Capture-for-iOS` 项目将能够生成与 `NeRFCapture` 格式一致、数据精确、可直接用于Splatam计算的数据集。
