import SwiftUI

/// Draws the About flame, and the fire that rises out of it when stoked, for one moment in time.
///
/// Tongues of flame are soft blobs that rise, sway, and shrink. Blurring them together and cutting the blur at a
/// threshold melts them into one flat shape, so they pull out of the logo, pinch off, and burn away in its own flat
/// colors. With Reduce Motion on, nothing moves: the core only glows hotter and fades back.
nonisolated struct FireRenderer {
    struct Palette {
        var ember: Color
        var core: Color
        var hot: Color
    }

    /// The canvas reaches past the flame: up for the fire, down and out for the glow.
    static let size = CGSize(width: 200, height: 180)
    /// How far the canvas hangs below the bottom of the flame.
    static let floor: CGFloat = 36
    static let flameHeight: CGFloat = 88

    var stokes: StokeHistory
    var palette: Palette
    var reduceMotion: Bool

    private struct Blob {
        var center: CGPoint
        var radius: Double
        var coreRadius: Double
        /// Which way the tongue leans, following its path.
        var tilt: Double
    }

    private struct Spark {
        var center: CGPoint
        var radius: Double
        var opacity: Double
        var isHot: Bool
    }

    private static let slotsPerSecond = 60.0
    private static let longestLife = 2.0

    func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let heat = stokes.heat(at: time)
        let flame = flameRect(in: size)
        let stretch = reduceMotion ? 0 : heat
        let body = FlameShape().path(in: stretched(flame, by: stretch))
        let core = FlameShape().path(in: coreRect(in: flame, growth: stretch))

        drawBloom(in: &context, flame: flame, heat: heat)

        let blobs = reduceMotion ? [] : blobs(in: flame, at: time)
        if !blobs.isEmpty {
            drawMelted(
                in: &context, color: palette.ember, blur: 4.5, base: body,
                tongues: blobs.map { tongue($0, radius: $0.radius) })
        }

        var shadowed = context
        shadowed.addFilter(.shadow(color: palette.ember.opacity(0.18 + heat * 0.22), radius: 24, y: 8))
        shadowed.fill(body, with: .color(palette.ember))

        if blobs.isEmpty {
            context.fill(core, with: .color(palette.core))
        } else {
            drawMelted(
                in: &context, color: palette.core, blur: 3.5, base: core,
                tongues: blobs.map { tongue($0, radius: $0.coreRadius) })
            context.fill(core, with: .color(palette.core))
        }

        if reduceMotion, heat > 0.01 {
            var warmed = context
            warmed.opacity = heat
            warmed.fill(core, with: .color(palette.hot))
        }

        if heat > 0.01 {
            var glowing = context
            glowing.opacity = min(1, heat * 1.3)
            glowing.addFilter(.blur(radius: 5))
            glowing.fill(FlameShape().path(in: hotRect(in: flame, growth: stretch)), with: .color(palette.hot))
        }

        if !reduceMotion {
            drawSparks(in: &context, flame: flame, time: time)
        }
    }

    // MARK: - Geometry

    private func flameRect(in size: CGSize) -> CGRect {
        let height = Self.flameHeight
        let width = height / 1.5
        return CGRect(x: (size.width - width) / 2, y: size.height - Self.floor - height, width: width, height: height)
    }

    /// A stoked flame stands a little taller and narrower, from its base.
    private func stretched(_ flame: CGRect, by heat: Double) -> CGRect {
        let height = flame.height * (1 + 0.08 * heat)
        let width = flame.width * (1 - 0.03 * heat)
        return CGRect(x: flame.midX - width / 2, y: flame.maxY - height, width: width, height: height)
    }

    /// The core sits where `FlameGlyph` puts it, and swells as the fire gets hotter.
    private func coreRect(in flame: CGRect, growth: Double) -> CGRect {
        let scale = 1 + 0.2 * growth
        let width = flame.width * 0.53 * scale
        let height = flame.height * 0.56 * scale
        let bottom = flame.maxY - flame.height * 0.07
        return CGRect(x: flame.midX - width / 2, y: bottom - height, width: width, height: height)
    }

    private func hotRect(in flame: CGRect, growth: Double) -> CGRect {
        let width = flame.width * (0.26 + 0.08 * growth)
        let height = flame.height * (0.3 + 0.1 * growth)
        let bottom = flame.maxY - flame.height * 0.1
        return CGRect(x: flame.midX - width / 2, y: bottom - height, width: width, height: height)
    }

    // MARK: - Layers

    private func drawBloom(in context: inout GraphicsContext, flame: CGRect, heat: Double) {
        guard heat > 0.01 else { return }
        let center = CGPoint(x: flame.midX, y: flame.maxY - flame.width * 0.6)
        // Without motion the bloom only brightens. With it, the bloom also spreads.
        let radius = reduceMotion ? 70 : 34 + 46 * heat
        let bloom = Path(
            ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(
            bloom,
            with: .radialGradient(
                Gradient(colors: [palette.ember.opacity(0.3 * heat), palette.ember.opacity(0)]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    /// A small flame for a blob: its belly on the blob, its tip leaning along the blob's path.
    private func tongue(_ blob: Blob, radius: Double) -> Path? {
        guard radius > 0.5 else { return nil }
        let rect = CGRect(x: -radius, y: radius - radius * 3.2, width: radius * 2, height: radius * 3.2)
        let transform = CGAffineTransform(translationX: blob.center.x, y: blob.center.y).rotated(by: blob.tilt)
        return FlameShape().path(in: rect).applying(transform)
    }

    /// Blurs the shape and tongues together, then cuts the blur at half opacity into one flat, fluid color.
    private func drawMelted(
        in context: inout GraphicsContext,
        color: Color,
        blur: Double,
        base: Path,
        tongues: [Path?]
    ) {
        context.drawLayer { layer in
            layer.addFilter(.alphaThreshold(min: 0.5, color: color))
            layer.addFilter(.blur(radius: blur))
            layer.drawLayer { melt in
                // Filling with the final color keeps the cut edge from picking up a dark fringe.
                melt.fill(base, with: .color(color))
                for case let tongue? in tongues {
                    melt.fill(tongue, with: .color(color))
                }
            }
        }
    }

    private func drawSparks(in context: inout GraphicsContext, flame: CGRect, time: TimeInterval) {
        for spark in sparks(in: flame, at: time) where spark.opacity > 0.01 {
            let radius = spark.radius
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: spark.center.x - radius, y: spark.center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color((spark.isHot ? palette.hot : palette.ember).opacity(spark.opacity))
            )
        }
    }

    // MARK: - Fire

    /// The shared draft that leans every tongue the same way at once, so the fire sways as one.
    private func draft(at time: TimeInterval) -> Double {
        4 * sin(1.9 * time) + 2.5 * sin(3.3 * time + 1.1)
    }

    private func blobs(in flame: CGRect, at time: TimeInterval) -> [Blob] {
        var blobs: [Blob] = []
        forEachBirth(at: time, salt: 1, perSecond: 26, burst: 5) { seed, born, heat, isBurst in
            if let blob = blob(seed: seed, born: born, heat: heat, isBurst: isBurst, in: flame, at: time) {
                blobs.append(blob)
            }
        }
        return blobs
    }

    private func blob(
        seed: Int, born: TimeInterval, heat: Double, isBurst: Bool, in flame: CGRect, at time: TimeInterval
    )
        -> Blob?
    {
        let age = time - born
        let life = (0.85 + 0.5 * random(seed, 1)) * (0.8 + 0.5 * heat)
        guard age >= 0, age < life else { return nil }
        let progress = age / life

        func position(at age: Double) -> CGPoint {
            let progress = age / life
            let startX = flame.midX + (random(seed, 2) - 0.5) * flame.width * 0.5
            let startY = flame.maxY - flame.width * 0.45 + (random(seed, 3) - 0.5) * 10
            let speed = (52 + 40 * heat) * (isBurst ? 1.35 : 1)
            let y = startY - (speed * age + 35 * age * age)

            // Tongues start across the belly and draw in toward the tip as they rise.
            let drawIn = 1 - 0.8 * smoothstep(progress / 0.55)
            let sway =
                (4 + 7 * heat) * sin(2 * .pi * ((0.7 + 0.6 * random(seed, 4)) * age + random(seed, 5))) * progress
            let x = flame.midX + (startX - flame.midX) * drawIn + sway + draft(at: born + age) * progress
            return CGPoint(x: x, y: y)
        }

        let center = position(at: age)
        let before = position(at: max(0, age - 0.04))
        let tilt = atan2(center.x - before.x, before.y - center.y)

        let grow = min(1, age / 0.1)
        let size = (7 + 5 * random(seed, 6)) * (0.85 + 0.4 * heat)
        let radius = size * grow * pow(1 - progress, 1.3)
        let coreRadius = size * 0.62 * grow * pow(max(0, 1 - progress / 0.65), 0.8)
        return Blob(center: center, radius: radius, coreRadius: coreRadius, tilt: tilt)
    }

    private func sparks(in flame: CGRect, at time: TimeInterval) -> [Spark] {
        var sparks: [Spark] = []
        forEachBirth(at: time, salt: 2, perSecond: 14, burst: 7) { seed, born, heat, _ in
            let age = time - born
            let life = 0.7 + 0.7 * random(seed, 1)
            guard age >= 0, age < life else { return }
            let progress = age / life

            let startX = flame.midX + (random(seed, 2) - 0.5) * 14
            let startY = flame.minY + 18 + random(seed, 3) * 14
            let pushX = (random(seed, 4) - 0.5) * 50 * (1 + heat)
            let pushY = -(70 + 60 * random(seed, 5)) * (0.7 + 0.6 * heat)
            let travel = (1 - exp(-1.1 * age)) / 1.1
            let x = startX + pushX * travel + 5 * sin(9 * age + 2 * .pi * random(seed, 6)) + draft(at: time) * progress
            let y = startY + pushY * travel - 15 * age * age

            let twinkle = 0.65 + 0.35 * sin(30 * age + 6 * random(seed, 8))
            // Sparks fade out before they reach the top of the canvas, so none are clipped.
            let edge = smoothstep((y - 6) / 20)
            sparks.append(
                Spark(
                    center: CGPoint(x: x, y: y),
                    radius: (0.8 + 1.1 * random(seed, 7)) * (1 - progress * 0.5),
                    opacity: pow(1 - progress, 1.2) * twinkle * edge,
                    isHot: random(seed, 9) < 0.6
                )
            )
        }
        return sparks
    }

    /// Calls `body` for every particle alive at `time`: a steady stream while the fire is hot, and a burst per press.
    ///
    /// Births fall on fixed time slots, and each slot's randomness comes from its index, so any frame can be drawn
    /// from scratch and still agree with the one before it.
    private func forEachBirth(
        at time: TimeInterval,
        salt: Int,
        perSecond: Double,
        burst: Int,
        _ body: (_ seed: Int, _ born: TimeInterval, _ heat: Double, _ isBurst: Bool) -> Void
    ) {
        let first = Int(((time - Self.longestLife) * Self.slotsPerSecond).rounded(.down))
        let last = Int((time * Self.slotsPerSecond).rounded(.down))
        for slot in first...last {
            let born = Double(slot) / Self.slotsPerSecond
            // Below a flicker of heat the stream stops, so a cooling fire goes out instead of sputtering forever.
            let heat = stokes.heat(at: born)
            let rate = perSecond * max(0, heat - 0.05) / 0.95
            let seed = slot &* 31 &+ salt
            if random(seed, 0) < rate / Self.slotsPerSecond {
                body(seed, born, heat, false)
            }
        }

        for press in stokes.presses where time - press.start < Self.longestLife {
            let heat = max(0.5, stokes.heat(at: press.start + 0.1))
            let pressSeed = Int((press.start * 1000).rounded()) &* 131 &+ salt
            for index in 0..<burst {
                body(pressSeed &+ index &* 7919, press.start + Double(index) * 0.012, heat, true)
            }
        }
    }

    // MARK: - Math

    /// A stable pseudo-random number in 0..<1 for a seed and a lane.
    private func random(_ seed: Int, _ lane: Int) -> Double {
        var value = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(lane) &* 0xBF58_476D_1CE4_E5B9
        value ^= value >> 31
        value &*= 0x94D0_49BB_1331_11EB
        value ^= value >> 29
        value &*= 0xBF58_476D_1CE4_E5B9
        value ^= value >> 32
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }

    private func smoothstep(_ value: Double) -> Double {
        let clamped = min(1, max(0, value))
        return clamped * clamped * (3 - 2 * clamped)
    }
}
