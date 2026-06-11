import Foundation

/// Display metadata for a shader tunable. Anything parsed from the shader that
/// has no spec still shows up, in the "Other" group, with a guessed range.
struct ParamSpec {
    let range: ClosedRange<Double>
    let group: String
    let help: String
    let def: Double

    init(_ range: ClosedRange<Double>, _ group: String, _ def: Double, _ help: String) {
        self.range = range
        self.group = group
        self.def = def
        self.help = help
    }
}

enum Specs {
    static let groupOrder = [
        "Black hole", "Accretion disk", "Color & light", "Motion & screen",
        "Token mode", "Pomodoro", "Other",
    ]

    static let all: [String: ParamSpec] = [
        // black hole
        "HOLE_RADIUS":   ParamSpec(0.01...0.25, "Black hole", 0.08, "Size dial. Pomodoro: shadow radius at full size, fraction of screen height. Token mode: scales the area calibration — exact at 0.08, smaller/bigger scales everything proportionally"),
        "LENS_DEPTH":    ParamSpec(0.0...20.0, "Black hole", 4.0, "Distance from the hole to the terminal “sky” plane, in Schwarzschild radii — bigger bends text harder"),
        "STAR_GAIN":     ParamSpec(0.0...2.0, "Black hole", 0.0, "Brightness of the lensed starfield around the hole (0 = off)"),

        // disk geometry + matter
        "DISK_INNER":    ParamSpec(1.6...8.0, "Accretion disk", 3.0, "Inner edge in Schwarzschild radii; 3 is the ISCO (innermost stable circular orbit)"),
        "DISK_OUTER":    ParamSpec(4.0...20.0, "Accretion disk", 9.0, "Outer edge in Schwarzschild radii"),
        "DISK_INCL":     ParamSpec(0.0...1.5707, "Accretion disk", 1.45, "Inclination in radians: 0 = face-on, π/2 = edge-on (Interstellar look)"),
        "DISK_ROLL":     ParamSpec(-3.1416...3.1416, "Accretion disk", 0.15, "Rotation of the whole system in the screen plane, radians"),
        "DISK_GAIN":     ParamSpec(0.0...4.0, "Accretion disk", 1.0, "Disk emission brightness"),
        "DISK_OPACITY":  ParamSpec(0.0...1.0, "Accretion disk", 0.65, "How much the near disk hides the shadow, far-side images and text behind it"),
        "DISK_SPEED":    ParamSpec(-10.0...10.0, "Accretion disk", 3.6, "Streak pattern speed; negative reverses the orbital direction"),
        "DISK_WIND":     ParamSpec(0.0...15.0, "Accretion disk", 5.0, "Spiral winding tightness of the streaks"),
        "DISK_CONTRAST": ParamSpec(0.0...2.0, "Accretion disk", 0.9, "Streak contrast: 0 = smooth haze, higher = sharp filaments"),

        // color & light
        "DISK_TEMP":     ParamSpec(2000.0...20000.0, "Color & light", 8500.0, "Blackbody temperature of the hottest annulus, Kelvin"),
        "DOPPLER_MIX":   ParamSpec(0.0...1.0, "Color & light", 1.0, "Relativistic Doppler shift + beaming asymmetry: 0 = off, 1 = full physics"),
        "DISK_BEAM":     ParamSpec(0.0...6.0, "Color & light", 3.0, "Beaming exponent: observed intensity scales as g^N (3 ≈ photon-count, 4 ≈ bolometric)"),
        "EXPOSURE":      ParamSpec(0.05...5.0, "Color & light", 1.0, "Tonemap exposure for the disk light; terminal text is never tonemapped"),

        // motion & screen
        "DRIFT_SPEED":   ParamSpec(0.0...3.0, "Motion & screen", 1.0, "How fast the hole floats around"),
        "WORK_AREA":     ParamSpec(0.0...0.8, "Motion & screen", 0.33, "Bottom screen fraction kept completely undistorted"),
        "DILATION_MIN":  ParamSpec(0.0...1.0, "Motion & screen", 0.2, "Disk pattern time rate at full size — gravitational time dilation theme"),

        // token mode
        "TOKEN_LEVEL":   ParamSpec(-1.0...1.0, "Token mode", -1.0, "Preview any context fill — emits the OSC 12 cursor-color signal to every Ghostty surface (claude-token.py's channel); negative clears the signal and hides the hole. A live Claude session re-emits its own level, overriding the preview in its surface"),
        "TOKEN_AREA_MIN": ParamSpec(0.001...0.10, "Token mode", 0.01, "Shadow area at 0% context, as a fraction of the terminal area"),
        "TOKEN_AREA_MAX": ParamSpec(0.05...0.90, "Token mode", 0.50, "Shadow area at 100% context, as a fraction of the terminal area"),
        "TOKEN_HOME_X":  ParamSpec(0.0...1.0, "Token mode", 0.94, "Corner-home x in uv (1 = right edge)"),
        "TOKEN_HOME_Y":  ParamSpec(0.0...1.0, "Token mode", 0.06, "Corner-home y in uv (0 = screen top)"),
        "TOKEN_EASE":    ParamSpec(0.1...3.0, "Token mode", 1.0, "Growth curve exponent: 1 = proportional, <1 front-loads growth, >1 back-loads it"),
        "TOKEN_REACH":   ParamSpec(0.0...1.0, "Token mode", 1.0, "How much of the playable screen the roam box covers at 100% context"),
        "TOKEN_CALM":    ParamSpec(0.0...1.0, "Token mode", 0.04, "Drift speed at 0% context"),
        "TOKEN_RUSH":    ParamSpec(0.0...3.0, "Token mode", 1.1, "Drift speed at 100% context"),

        // pomodoro
        "WORK_PERIOD_MIN": ParamSpec(1.0...120.0, "Pomodoro", 55.0, "Work minutes per cycle (growth phase)"),
        "BREAK_MIN":       ParamSpec(1.0...30.0, "Pomodoro", 5.0, "Break minutes per cycle (hole gone)"),
        "IDLE_FADE_SEC":   ParamSpec(10.0...600.0, "Pomodoro", 90.0, "Typing pause after which the hole starts fading"),
        "TIME_SCALE":      ParamSpec(1.0...200.0, "Pomodoro", 1.0, "Testing: >1 fast-forwards the pomodoro cycle via iTime"),
    ]

    static func spec(for name: String, value: Double) -> ParamSpec {
        if let s = all[name] { return s }
        let hi = max(abs(value) * 4.0, 1.0)
        return ParamSpec(value < 0 ? -hi...hi : 0...hi, "Other", value, "")
    }

    /// Presets in the spirit of the Bruneton demo's scene settings.
    static let presets: [(String, [String: Double])] = [
        ("Defaults", all.filter { $0.key != "TOKEN_LEVEL" }.mapValues(\.def)),
        ("Gargantua", [
            "DISK_TEMP": 4500, "DISK_INCL": 1.52, "DISK_ROLL": 0.10,
            "DISK_INNER": 2.2, "DISK_OUTER": 7.0, "DISK_OPACITY": 0.85,
            "DOPPLER_MIX": 0.35, "DISK_BEAM": 2.0, "DISK_GAIN": 1.4,
            "DISK_CONTRAST": 0.5, "STAR_GAIN": 0.0, "EXPOSURE": 1.2,
        ]),
        ("Quasar", [
            "DISK_TEMP": 15000, "DISK_INCL": 1.30, "DISK_INNER": 3.0,
            "DISK_OUTER": 14.0, "DISK_OPACITY": 0.35, "DOPPLER_MIX": 1.0,
            "DISK_BEAM": 4.0, "DISK_GAIN": 1.2, "DISK_CONTRAST": 1.3,
            "DISK_WIND": 8.0, "STAR_GAIN": 0.0, "EXPOSURE": 0.8,
        ]),
        ("Face-on ember", [
            "DISK_TEMP": 6500, "DISK_INCL": 0.30, "DISK_ROLL": 0.0,
            "DISK_INNER": 3.0, "DISK_OUTER": 10.0, "DISK_OPACITY": 0.5,
            "DOPPLER_MIX": 0.8, "DISK_BEAM": 2.5, "DISK_GAIN": 1.0,
            "DISK_CONTRAST": 1.1, "STAR_GAIN": 0.0, "EXPOSURE": 1.0,
        ]),
        // the EHT image of M87*: warm orange donut, nearly face-on, one
        // beamed bright side, smooth haze instead of filaments
        ("M87* donut", [
            "DISK_TEMP": 3800, "DISK_INCL": 0.55, "DISK_ROLL": -0.30,
            "DISK_INNER": 2.2, "DISK_OUTER": 6.0, "DISK_OPACITY": 0.45,
            "DOPPLER_MIX": 0.9, "DISK_BEAM": 3.5, "DISK_GAIN": 1.6,
            "DISK_CONTRAST": 0.4, "DISK_WIND": 3.0, "DISK_SPEED": 2.5,
            "STAR_GAIN": 0.0, "EXPOSURE": 1.1,
        ]),
        // violently hot and fast: a huge thin jet-fed disk, heavily beamed
        ("Blazar", [
            "DISK_TEMP": 18000, "DISK_INCL": 1.05, "DISK_ROLL": 0.55,
            "DISK_INNER": 3.0, "DISK_OUTER": 16.0, "DISK_OPACITY": 0.30,
            "DOPPLER_MIX": 1.0, "DISK_BEAM": 5.0, "DISK_GAIN": 1.0,
            "DISK_CONTRAST": 1.5, "DISK_WIND": 9.0, "DISK_SPEED": 6.0,
            "STAR_GAIN": 0.0, "EXPOSURE": 0.75,
        ]),
        // dense molten edge-on disk, thick filaments, everything overdriven
        ("Inferno", [
            "DISK_TEMP": 5500, "DISK_INCL": 1.50, "DISK_ROLL": 0.35,
            "DISK_INNER": 1.8, "DISK_OUTER": 8.0, "DISK_OPACITY": 0.90,
            "DOPPLER_MIX": 0.6, "DISK_BEAM": 2.5, "DISK_GAIN": 2.2,
            "DISK_CONTRAST": 1.6, "DISK_WIND": 7.0, "DISK_SPEED": 5.0,
            "STAR_GAIN": 0.0, "EXPOSURE": 1.4,
        ]),
        // no disk at all: just the shadow, lensed starfield and bending text —
        // pure Schwarzschild geometry
        ("Pure lens", [
            "DISK_GAIN": 0.0, "DISK_OPACITY": 0.0, "STAR_GAIN": 0.6,
            "DOPPLER_MIX": 1.0, "EXPOSURE": 1.0,
        ]),
        // barely-there companion for focused work: dim, slow, no starfield
        ("Zen", [
            "DISK_TEMP": 7000, "DISK_INCL": 1.45, "DISK_ROLL": 0.15,
            "DISK_INNER": 3.5, "DISK_OUTER": 7.0, "DISK_OPACITY": 0.40,
            "DOPPLER_MIX": 0.5, "DISK_BEAM": 2.0, "DISK_GAIN": 0.5,
            "DISK_CONTRAST": 0.3, "DISK_WIND": 3.0, "DISK_SPEED": 1.5,
            "STAR_GAIN": 0.0, "EXPOSURE": 0.7,
        ]),
    ]

    static func grouped(_ params: [ShaderParam]) -> [(String, [ShaderParam])] {
        groupOrder.compactMap { group in
            let members = params.filter { spec(for: $0.name, value: $0.value).group == group }
            return members.isEmpty ? nil : (group, members)
        }
    }
}
