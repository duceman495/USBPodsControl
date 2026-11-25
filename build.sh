#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${APP_OUT:-$ROOT_DIR/dist/USBPodsControl.app}"
BUILD_TMP="$ROOT_DIR/.build"

mkdir -p "$BUILD_TMP"

echo "==> [1/4] Running ParserTests..."
swiftc -swift-version 5 -parse-as-library \
    "$ROOT_DIR/Sources/Models.swift" \
    "$ROOT_DIR/Sources/USBPodsParser.swift" \
    "$ROOT_DIR/Tests/ParserTests.swift" \
    -o "$BUILD_TMP/ParserTests"
"$BUILD_TMP/ParserTests"

echo "==> [2/4] Generating AppIcon.icns..."
ICONSET_DIR="$BUILD_TMP/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

cat > "$BUILD_TMP/gen_icon.swift" << 'EOF'
import Cocoa

let iconsetPath = CommandLine.arguments[1]
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, filename) in sizes {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let inset = s * 0.06
    let bgRect = rect.insetBy(dx: inset, dy: inset)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.22, yRadius: s * 0.22)

    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.24, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.96, green: 0.45, blue: 0.14, alpha: 1.0)
    )!
    gradient.draw(in: bgPath, angle: 45)

    // Subtle glossy rim
    NSColor.white.withAlphaComponent(0.22).setStroke()
    bgPath.lineWidth = max(1.0, s * 0.015)
    bgPath.stroke()

    // Draw headphone symbol centered
    if let sym = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.44, weight: .semibold)
        if let configured = sym.withSymbolConfiguration(cfg) {
            let imgSize = configured.size
            let drawRect = NSRect(
                x: (s - imgSize.width) / 2,
                y: (s - imgSize.height) / 2 + s * 0.05,
                width: imgSize.width,
                height: imgSize.height
            )
            NSColor.white.set()
            configured.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 0.96)
        }
    }

    // Gold LDAC badge text at bottom for >= 64px
    if px >= 64 {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: s * 0.14, weight: .heavy),
            .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.45, alpha: 1.0)
        ]
        let label = NSAttributedString(string: "LDAC", attributes: attrs)
        let lSize = label.size()
        label.draw(at: NSPoint(x: (s - lSize.width) / 2, y: s * 0.14))
    }

    NSGraphicsContext.restoreGraphicsState()
    let pngData = rep.representation(using: .png, properties: [:])!
    try! pngData.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(filename)"))
}
EOF

swift "$BUILD_TMP/gen_icon.swift" "$ICONSET_DIR"

echo "==> [3/4] Compiling USBPodsControl.app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

swiftc -swift-version 5 -O \
    -framework Cocoa \
    -framework SwiftUI \
    -framework IOKit \
    -framework CoreAudio \
    "$ROOT_DIR/Sources/Models.swift" \
    "$ROOT_DIR/Sources/USBDeviceDiscovery.swift" \
    "$ROOT_DIR/Sources/CoreAudioHelper.swift" \
    "$ROOT_DIR/Sources/SerialPort.swift" \
    "$ROOT_DIR/Sources/USBPodsParser.swift" \
    "$ROOT_DIR/Sources/USBPodsController.swift" \
    "$ROOT_DIR/Sources/ContentView.swift" \
    "$ROOT_DIR/Sources/main.swift" \
    -o "$APP_DIR/Contents/MacOS/USBPodsControl"

echo "==> [4/4] Signing USBPodsControl.app (ad-hoc)..."
codesign --force --deep --sign - "$APP_DIR"

echo "Done! Built: $APP_DIR"
