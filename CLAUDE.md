# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

vger is a GPU-accelerated vector graphics renderer written in C with Swift bindings, designed for iOS and macOS. It renders primitives analytically in fragment shaders rather than using CPU tessellation, achieving high performance for immediate-mode UIs.

## Architecture

### Core Components

- **C Core (`Sources/vger/`)**: The main rendering engine written in C/C++/Objective-C++ with Metal shaders
  - `vger.h`: Main API interface - review this for all available rendering functions
  - `vger.mm`: Core implementation with Metal rendering logic
  - `vgerRenderer.mm`: Main renderer class handling Metal command encoding
  - `vgerPathScanner.mm`: Path processing and horizontal slab decomposition for fills
  - `vgerGlyphCache.mm`: Text rendering with glyph atlas management
  - `vger.metal`: Fragment shaders for primitive rendering

- **Swift Layer (`Sources/vgerSwift/`)**: SwiftUI integration and higher-level APIs
  - `VgerView.swift`: SwiftUI view wrapper for Metal rendering
  - `Renderer.swift`: Metal rendering coordinator
  - `TextureRenderer.swift`: Additional texture rendering utilities

- **Demo App (`Demo/`)**: Complete iOS/macOS SwiftUI application demonstrating usage
  - Cross-platform implementation showing VgerView integration
  - Examples of text, shapes, SVG rendering, and various primitives

### Key Design Patterns

- **Immediate Mode**: All drawing commands are recorded per frame, no retained geometry
- **GPU-Centric**: Fragment shaders handle primitive evaluation, minimal CPU work
- **Instanced Rendering**: Each primitive renders as a quad with shader-computed geometry
- **Paint System**: Separate paint objects for colors, gradients, textures, and patterns
- **Transform Stack**: Standard graphics transform state with save/restore

## Development Commands

### Building
```bash
# Build the project
./build.sh

# Or use xcodebuild directly
xcodebuild -scheme vger -sdk macosx -destination "name=My Mac"
```

### Testing
```bash
# Run all tests
./test.sh

# Or use xcodebuild directly
xcodebuild test -scheme vger -sdk macosx -destination "name=My Mac"
```

### Swift Package Manager
This project uses SPM and can be built with:
```bash
swift build
swift test
```

## Usage Patterns

### Basic C API Usage
```c
vgerContext vg = vgerNew(0, MTLPixelFormatBGRA8Unorm);
vgerBegin(vg, width, height, devicePixelRatio);

// Create paint and draw primitives
vgerPaintIndex paint = vgerColorPaint(vg, (vector_float4){1,0,0,1});
vgerFillCircle(vg, center, radius, paint);

vgerEncode(vg, commandBuffer, renderPassDescriptor);
```

### SwiftUI Integration
```swift
VgerView(renderCallback: { vger, size in
    let paint = vgerColorPaint(vger, SIMD4<Float>(1,0,1,1))
    vgerFillRect(vger, min, max, cornerRadius, paint)
})
```

## Key Implementation Details

- **Path Fills**: Uses reverse Loop-Blinn technique in fragment shader to avoid solving quadratic equations
- **Text Rendering**: Glyph atlas with SDF-based rendering for scalable text
- **Buffering**: Supports double/triple buffering schemes via creation flags
- **Layers**: Multi-layer rendering support (up to 4 layers)
- **Transform Stack**: Full 2D transformation support with save/restore

## Test Structure

Tests are in `Tests/vgerTests/` and include:
- Basic primitive rendering tests with reference images
- Path scanning and fill algorithm tests  
- Glyph cache and text rendering tests
- SDF computation tests
- Texture management tests

Reference images in `Tests/vgerTests/images/` are used for visual regression testing.