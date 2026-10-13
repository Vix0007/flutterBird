import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Sfx.init(); // loads the sound effects in the background
  runApp(const FlappyApp());
}

class FlappyApp extends StatelessWidget {
  const FlappyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flappy',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFFEC4899),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFEC4899),
      ),
      // respect the phone's text size, but stop huge sizes from breaking cards
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 1.0,
        maxScaleFactor: 1.3,
        child: child!,
      ),
      home: const StartPage(),
    );
  }
}

// =====================================================================
// SOUND
// All effects are synthesized here in code (no audio files, no packages).
// On Android they are played by a few lines of native code in
// MainActivity.kt. On other platforms the calls are safely ignored.
// =====================================================================

class Sfx {
  Sfx._();

  static const MethodChannel _channel = MethodChannel('flappy/sfx');
  static const int rate = 22050;
  static bool enabled = true;
  static bool _native = true;

  /// name -> raw 16-bit mono samples
  static final Map<String, Uint8List> bank = _buildBank();

  static bool _musicWanted = false;
  static bool _musicLoaded = false;

  /// Starts or stops the looping background tune (safe to call every frame).
  static void music(bool on) {
    if (on == _musicWanted) return;
    _musicWanted = on;
    if (!_native || !_musicLoaded) return;
    _channel
        .invokeMethod<void>(on ? 'musicStart' : 'musicStop')
        .catchError((Object _) {});
  }

  /// A cheerful 8-second loop: C - Am - F - G, arpeggio on top, soft bass below.
  static Uint8List _buildMusic() {
    const chords = [
      [523.25, 659.25, 783.99], // C
      [440.0, 523.25, 659.25], // Am
      [349.23, 440.0, 523.25], // F
      [392.0, 493.88, 587.33], // G
    ];
    const bass = [130.81, 110.0, 87.31, 98.0];
    const pattern = [0, 1, 2, 1, 0, 1, 2, 1];
    final arp = <List<double>>[];
    final low = <List<double>>[];
    for (var bar = 0; bar < 4; bar++) {
      for (final i in pattern) {
        final f = chords[bar][i];
        arp.add(_tone(f, f, 0.25, vol: 0.5, decay: 3));
      }
      low.add(_tone(bass[bar], bass[bar], 2.0, vol: 0.55, decay: 0.8));
    }
    final mixed = _mix(_seq(arp), _seq(low));
    return _pcm([for (final s in mixed) s * 0.35]);
  }

  static VoidCallback? onEscape;

  static Future<void> init() async {
    const MethodChannel('flappy/keys').setMethodCallHandler((call) async {
      if (call.method == 'escape') onEscape?.call();
    });
    try {
      for (final e in bank.entries) {
        await _channel.invokeMethod<void>('load', {
          'name': e.key,
          'data': e.value,
        });
      }
      await _channel.invokeMethod<void>('musicLoad', _buildMusic());
      _musicLoaded = true;
      if (_musicWanted) await _channel.invokeMethod<void>('musicStart');
    } on MissingPluginException {
      _native = false;
    } on PlatformException {
      _native = false;
    }
  }

  static void play(String name) {
    if (!enabled) return;
    if (_native) {
      _channel.invokeMethod<void>('play', name).catchError((Object _) {
        _native = false;
      });
    } else if (name == 'tap') {
      SystemSound.play(SystemSoundType.click);
    }
  }

  // ---- saved best score (stored natively, see MainActivity.kt) ----

  static const MethodChannel _saveChannel = MethodChannel('flappy/save');

  static Future<int> loadBest() async {
    try {
      return await _saveChannel.invokeMethod<int>('getBest') ?? 0;
    } catch (_) {
      return 0; // not on Android: just start from zero
    }
  }

  static Future<void> saveBest(int value) async {
    try {
      await _saveChannel.invokeMethod<void>('setBest', value);
    } catch (_) {}
  }

  // ---- tiny synthesizer ----

  static Map<String, Uint8List> _buildBank() {
    const c5 = 523.25, e5 = 659.25, g5 = 783.99, c6 = 1046.5;
    return {
      'flap': _pcm(_tone(380, 760, 0.11, vol: 0.35, decay: 2.5)),
      'score': _pcm(
        _seq([
          _tone(988, 988, 0.07, vol: 0.3, decay: 2),
          _tone(1319, 1319, 0.17, vol: 0.3, decay: 3),
        ]),
      ),
      'hit': _pcm(
        _mix(
          _noise(0.22, vol: 0.5, decay: 7),
          _tone(160, 55, 0.25, vol: 0.6, decay: 4),
        ),
      ),
      'tick': _pcm(_tone(2000, 1500, 0.025, vol: 0.35, decay: 3)),
      'tap': _pcm(_tone(900, 700, 0.045, vol: 0.25, decay: 2.5)),
      'win': _pcm(
        _seq([
          _tone(c5, c5, 0.11, vol: 0.35, decay: 1.5),
          _tone(e5, e5, 0.11, vol: 0.35, decay: 1.5),
          _tone(g5, g5, 0.11, vol: 0.35, decay: 1.5),
          _tone(c6, c6, 0.35, vol: 0.4, decay: 2.5),
        ]),
      ),
      'lose': _pcm(
        _seq([
          _tone(311, 311, 0.2, vol: 0.3, decay: 1.5, square: true),
          _tone(293, 293, 0.2, vol: 0.3, decay: 1.5, square: true),
          _tone(277, 277, 0.2, vol: 0.3, decay: 1.5, square: true),
          _tone(262, 190, 0.5, vol: 0.3, decay: 2, square: true),
        ]),
      ),
      'beep': _pcm(_tone(660, 660, 0.09, vol: 0.3, decay: 1.5)),
      'go': _pcm(_tone(990, 990, 0.22, vol: 0.35, decay: 2)),
      'milestone': _pcm(
        _seq([
          _tone(g5, g5, 0.07, vol: 0.3, decay: 1.5),
          _tone(c6, c6, 0.07, vol: 0.3, decay: 1.5),
          _tone(1568, 1568, 0.22, vol: 0.32, decay: 2.5),
        ]),
      ),
      'best': _pcm(
        _seq([
          _tone(c5, c5, 0.09, vol: 0.35, decay: 1.5),
          _tone(g5, g5, 0.09, vol: 0.35, decay: 1.5),
          _tone(c6, c6, 0.09, vol: 0.35, decay: 1.5),
          _tone(1319, 1319, 0.09, vol: 0.35, decay: 1.5),
          _tone(1568, 1568, 0.4, vol: 0.4, decay: 2.5),
        ]),
      ),
      'pause': _pcm(_tone(700, 500, 0.07, vol: 0.28, decay: 2)),
    };
  }

  static Uint8List _pcm(List<double> samples) {
    final data = ByteData(samples.length * 2);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(
        i * 2,
        (samples[i].clamp(-1.0, 1.0) * 32767).round(),
        Endian.little,
      );
    }
    return data.buffer.asUint8List();
  }

  /// A beep that can slide from [f0] to [f1] Hz.
  static List<double> _tone(
    double f0,
    double f1,
    double seconds, {
    double vol = 0.4,
    double decay = 3,
    bool square = false,
  }) {
    final n = (seconds * rate).round();
    final out = List<double>.filled(n, 0);
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / n;
      phase += 2 * pi * (f0 + (f1 - f0) * t) / rate;
      final attack = min(1.0, i / (rate * 0.004)); // no click at the start
      final env = exp(-decay * t) * attack * (1 - pow(t, 8));
      final wave = square ? (sin(phase) >= 0 ? 0.6 : -0.6) : sin(phase);
      out[i] = wave * env * vol;
    }
    return out;
  }

  static List<double> _noise(
    double seconds, {
    double vol = 0.4,
    double decay = 6,
  }) {
    final rng = Random(7);
    final n = (seconds * rate).round();
    return List<double>.generate(n, (i) {
      final t = i / n;
      return (rng.nextDouble() * 2 - 1) * exp(-decay * t) * vol;
    });
  }

  static List<double> _mix(List<double> a, List<double> b) {
    final n = max(a.length, b.length);
    return List<double>.generate(
      n,
      (i) => (i < a.length ? a[i] : 0) + (i < b.length ? b[i] : 0),
    );
  }

  static List<double> _seq(List<List<double>> parts) => [
    for (final p in parts) ...p,
  ];
}

// =====================================================================
// DESIGN TOKENS
// Style: Claymorphism (soft 3D, chunky borders, double shadows, rounded)
// Colours and rules come from the UI/UX Pro Max design system.
// Every colour in the app lives here, nothing is hard-coded elsewhere.
// =====================================================================

class Palette {
  const Palette({
    required this.bg,
    required this.surface,
    required this.text,
    required this.muted,
    required this.outline,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.onDanger,
    required this.skyTop,
    required this.skyMid,
    required this.skyLow,
    required this.cloudAlpha,
    required this.ground,
    required this.groundDark,
    required this.pipe,
    required this.pipeDark,
    required this.pipeLight,
  });

  final Color bg, surface, text, muted, outline;
  final Color primary, onPrimary, accent, onAccent, danger, onDanger;
  final Color skyTop, skyMid, skyLow;
  final double cloudAlpha;
  final Color ground, groundDark, pipe, pipeDark, pipeLight;

  // the bird looks the same in light and dark mode
  static const birdBody = Color(0xFFFBBF24);
  static const birdWing = Color(0xFFF59E0B);
  static const birdOutline = Color(0xFF78350F);
  static const birdBeak = Color(0xFFEC4899);

  static const light = Palette(
    bg: Color(0xFFFDF2F8),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF0F172A),
    muted: Color(0xFF475569),
    outline: Color(0xFF831843),
    primary: Color(0xFFEC4899),
    onPrimary: Color(0xFF000000), // black on pink = 4.5:1+ contrast
    accent: Color(0xFFF59E0B),
    onAccent: Color(0xFF0F172A),
    danger: Color(0xFFDC2626),
    onDanger: Color(0xFFFFFFFF),
    skyTop: Color(0xFFA5B4FC),
    skyMid: Color(0xFFC4B5FD),
    skyLow: Color(0xFFFBCFE8),
    cloudAlpha: 0.75,
    ground: Color(0xFFFCD34D),
    groundDark: Color(0xFFF59E0B),
    pipe: Color(0xFF8B5CF6),
    pipeDark: Color(0xFF4C1D95),
    pipeLight: Color(0xFFC4B5FD),
  );

  static const dark = Palette(
    bg: Color(0xFF1B1030),
    surface: Color(0xFF2E1F52),
    text: Color(0xFFFDF2F8),
    muted: Color(0xFFCBD5E1),
    outline: Color(0xFFF9A8D4),
    primary: Color(0xFFF472B6),
    onPrimary: Color(0xFF000000),
    accent: Color(0xFFFBBF24),
    onAccent: Color(0xFF0F172A),
    danger: Color(0xFFDC2626),
    onDanger: Color(0xFFFFFFFF),
    skyTop: Color(0xFF1E1B4B),
    skyMid: Color(0xFF4C1D95),
    skyLow: Color(0xFF831843),
    cloudAlpha: 0.14,
    ground: Color(0xFF6D28D9),
    groundDark: Color(0xFF4C1D95),
    pipe: Color(0xFF8B5CF6),
    pipeDark: Color(0xFF2E1065),
    pipeLight: Color(0xFFC4B5FD),
  );

  static Palette of(BuildContext context) =>
      Theme.brightnessOf(context) == Brightness.dark ? dark : light;
}

// The design system picks Fredoka (headings) + Nunito (body). They are not
// bundled yet, so Flutter falls back to the default font until you add them.
// Bold weights keep the chunky, friendly feel either way.
TextStyle heading(Palette p, double size, {Color? color}) => TextStyle(
  fontFamily: 'Fredoka',
  fontSize: size,
  fontWeight: FontWeight.w700,
  color: color ?? p.text,
  height: 1.15,
  letterSpacing: size * 0.03,
);

TextStyle body(Palette p, double size, {Color? color}) => TextStyle(
  fontFamily: 'Nunito',
  fontSize: size,
  fontWeight: FontWeight.w600,
  color: color ?? p.text,
  height: 1.3,
);

// =====================================================================
// REUSABLE CLAY WIDGETS
// =====================================================================

/// Chunky 3D button. At least 56dp tall (touch target rule), shows a
/// pressed state without moving its neighbours, supports screen readers.
class ClayButton extends StatefulWidget {
  const ClayButton({
    super.key,
    this.label = '',
    this.semanticsLabel,
    this.icon,
    required this.color,
    required this.textColor,
    required this.border,
    required this.onPressed,
    this.dimWhenDisabled = true,
  });

  final String label;
  final String? semanticsLabel;
  final IconData? icon;
  final Color color, textColor, border;
  final VoidCallback? onPressed;
  final bool dimWhenDisabled;

  @override
  State<ClayButton> createState() => _ClayButtonState();
}

class _ClayButtonState extends State<ClayButton> {
  bool pressed = false;

  void _tap() {
    Sfx.play('tap');
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = widget.onPressed != null;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final dark = Theme.brightnessOf(context) == Brightness.dark;
    final iconOnly = widget.label.isEmpty;
    final base = (!enabled && widget.dimWhenDisabled)
        ? widget.color.withValues(alpha: 0.5)
        : widget.color;
    final lift = pressed ? 2.0 : 6.0;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel ?? widget.label,
      onTap: enabled ? _tap : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => pressed = false) : null,
        onTap: enabled ? _tap : null,
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          constraints: BoxConstraints(
            minHeight: 56,
            minWidth: iconOnly ? 56 : 140,
          ),
          transform: Matrix4.translationValues(0, pressed ? 4 : 0, 0),
          padding: EdgeInsets.symmetric(
            horizontal: iconOnly ? 0 : 28,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(iconOnly ? 28 : 24),
            border: Border.all(color: widget.border, width: 3),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(base, Colors.white, 0.28)!, base],
            ),
            boxShadow: [
              BoxShadow(color: widget.border, offset: Offset(0, lift)),
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.35 : 0.14),
                offset: Offset(0, lift + 6),
                blurRadius: 14,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null)
                Icon(widget.icon, color: widget.textColor, size: 28),
              if (widget.icon != null && !iconOnly) const SizedBox(width: 8),
              if (!iconOnly)
                Flexible(
                  child: AnimatedSwitcher(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 350),
                    child: Text(
                      widget.label,
                      key: ValueKey(widget.label),
                      textAlign: TextAlign.center,
                      style: heading(p, 20, color: widget.textColor),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ClayCard extends StatelessWidget {
  const ClayCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: p.outline, width: 3),
        boxShadow: [
          BoxShadow(color: p.outline, offset: const Offset(0, 6)),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            offset: const Offset(0, 16),
            blurRadius: 24,
          ),
        ],
      ),
      child: child,
    );
  }
}

// =====================================================================
// PART 1: the start screen with the "please don't click me" button
// =====================================================================

enum Phase { start, ouch, game }

class StartPage extends StatefulWidget {
  const StartPage({super.key});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  Phase phase = Phase.start;

  void flappyBird() {
    if (phase != Phase.start) return; // ignore extra taps
    HapticFeedback.mediumImpact();
    Sfx.play('hit');
    setState(() => phase = Phase.ouch);
    // stay on "Ouch!" for a moment, then fade into the game
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => phase = Phase.game);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: p.bg,
      // AnimatedSwitcher crossfades the intro away to reveal the game
      body: AnimatedSwitcher(
        duration: reduce
            ? const Duration(milliseconds: 300)
            : const Duration(milliseconds: 1000),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        child: phase == Phase.game
            ? GameScreen(
                key: const ValueKey('game'),
                onExit: SystemNavigator.pop,
              )
            : _intro(p, reduce),
      ),
    );
  }

  Widget _intro(Palette p, bool reduce) {
    final ouch = phase == Phase.ouch;
    return Container(
      key: const ValueKey('intro'),
      color: p.bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Hello World!\nThis is a test!',
            textAlign: TextAlign.center,
            style: body(p, 22),
          ),
          const SizedBox(height: 32),
          // little shake when you press it (skipped if motion is reduced)
          TweenAnimationBuilder<double>(
            key: ValueKey(ouch),
            tween: Tween(begin: 0, end: 1),
            duration: (ouch && !reduce)
                ? const Duration(milliseconds: 500)
                : Duration.zero,
            builder: (context, v, child) => Transform.translate(
              offset: Offset(ouch ? sin(v * pi * 6) * 10 * (1 - v) : 0, 0),
              child: child,
            ),
            child: ClayButton(
              label: ouch ? 'Ouch!' : 'Please don\'t click me!',
              color: ouch ? p.danger : p.primary,
              textColor: ouch ? p.onDanger : p.onPrimary,
              border: p.outline,
              dimWhenDisabled: false,
              onPressed: ouch ? null : flappyBird,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// PART 2: the casino wheel (shown when you crash)
// =====================================================================

/// The wheel picks its segment with this. Tests swap it for a fixed value.
Random wheelRandom = Random();

class SpinWheelCard extends StatefulWidget {
  const SpinWheelCard({
    super.key,
    required this.score,
    required this.onRevive,
    required this.onLose,
  });

  final int score;
  final VoidCallback onRevive;
  final VoidCallback onLose;

  @override
  State<SpinWheelCard> createState() => _SpinWheelCardState();
}

class _SpinWheelCardState extends State<SpinWheelCard>
    with TickerProviderStateMixin {
  // true = REVIVE, false = LOSE. 3 of 8 segments revive you (37.5% chance).
  static const List<bool> kinds = [
    true,
    false,
    false,
    true,
    false,
    true,
    false,
    false,
  ];

  late final AnimationController _spin = AnimationController(vsync: this);
  late final AnimationController _lights = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  double _target = 0; // total rotation (radians) the spin ends at
  int _picked = 0; // which segment it will land on
  int _lastSeg = -1;
  bool _spinning = false;
  bool? _won; // null until the wheel stops

  @override
  void initState() {
    super.initState();
    _spin.addListener(_onSpin);
    _spin.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (!reduce && !_lights.isAnimating) _lights.repeat();
    if (reduce && _lights.isAnimating) _lights.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    _lights.dispose();
    super.dispose();
  }

  double get _angle => _target * Curves.easeOutQuart.transform(_spin.value);

  void _onSpin() {
    // click each time a segment passes the pointer at the top
    final seg = 2 * pi / kinds.length;
    final local = (-_angle) % (2 * pi);
    final idx = (local / seg).floor() % kinds.length;
    if (idx != _lastSeg) {
      _lastSeg = idx;
      Sfx.play('tick');
      HapticFeedback.selectionClick();
    }
  }

  void _start() {
    if (_spinning || _won != null) return;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final n = kinds.length;
    final seg = 2 * pi / n;
    _picked = wheelRandom.nextInt(n);
    // land somewhere inside the picked segment (never right on a line)
    final offset = (wheelRandom.nextDouble() - 0.5) * seg * 0.7;
    final turns = 5 + wheelRandom.nextInt(2);
    _target = 2 * pi * turns - (_picked * seg + seg / 2 + offset);
    _spin.duration = Duration(milliseconds: reduce ? 700 : 4600);
    setState(() => _spinning = true);
    _spin.forward(from: 0);
  }

  void _finish() {
    final won = kinds[_picked];
    Sfx.play(won ? 'win' : 'lose');
    HapticFeedback.heavyImpact();
    if (mounted) {
      setState(() {
        _spinning = false;
        _won = won;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final size = min(260.0, MediaQuery.sizeOf(context).width - 140);
    final won = _won;

    final title = won == null ? 'You crashed!' : (won ? 'REVIVE!' : 'Busted!');
    final subtitle = won == null
        ? (_spinning
              ? 'Good luck...'
              : 'Spin for a second chance. Your score of ${widget.score} is on the line!')
        : (won
              ? 'You come back right where you crashed. Your score is safe.'
              : 'You lose everything.');

    return ClayCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            label: '$title $subtitle',
            excludeSemantics: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, textAlign: TextAlign.center, style: heading(p, 32)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: body(p, 16, color: p.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            label: 'Casino wheel with 3 revive segments out of 8',
            child: ExcludeSemantics(
              child: SizedBox(
                width: size,
                height: size + 16,
                child: Stack(
                  children: [
                    Positioned(
                      top: 16,
                      left: 0,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_spin, _lights]),
                        builder: (context, _) => CustomPaint(
                          size: Size.square(size),
                          painter: _WheelPainter(
                            angle: _angle,
                            kinds: kinds,
                            lightPhase: (_lights.value * (_spinning ? 6 : 2))
                                .floor(),
                            p: p,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: size / 2 - 17,
                      child: CustomPaint(
                        size: const Size(34, 40),
                        painter: _PointerPainter(p),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          ClayButton(
            label: won == null
                ? (_spinning ? 'Spinning...' : 'SPIN')
                : 'Continue',
            icon: won == null
                ? Icons.casino_rounded
                : (won ? Icons.favorite_rounded : Icons.flag_rounded),
            color: won == false ? p.danger : p.primary,
            textColor: won == false ? p.onDanger : p.onPrimary,
            border: p.outline,
            onPressed: _spinning
                ? null
                : (won == null
                      ? _start
                      : (won ? widget.onRevive : widget.onLose)),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.angle,
    required this.kinds,
    required this.lightPhase,
    required this.p,
  });

  final double angle;
  final List<bool> kinds;
  final int lightPhase;
  final Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final wheelR = r - 24;

    // rim, gold ring and the chasing casino bulbs
    canvas.drawCircle(c, r, Paint()..color = p.outline);
    canvas.drawCircle(c, r - 4, Paint()..color = p.accent);
    const bulbs = 16;
    for (var j = 0; j < bulbs; j++) {
      final a = -pi / 2 + j * 2 * pi / bulbs;
      final pos = c + Offset(cos(a), sin(a)) * (r - 12);
      final on = (j + lightPhase) % 2 == 0;
      canvas.drawCircle(
        pos,
        5,
        Paint()..color = on ? Colors.white : p.outline.withValues(alpha: 0.55),
      );
    }
    canvas.drawCircle(c, wheelR + 3, Paint()..color = p.outline);

    // the wheel itself, rotated by [angle]
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final seg = 2 * pi / kinds.length;
    final rect = Rect.fromCircle(center: Offset.zero, radius: wheelR);
    for (var i = 0; i < kinds.length; i++) {
      final start = -pi / 2 + i * seg;
      final path = Path()
        ..moveTo(0, 0)
        ..arcTo(rect, start, seg, false)
        ..close();
      final revive = kinds[i];
      canvas.drawPath(
        path,
        Paint()
          ..color = revive
              ? const Color(0xFFFDE68A)
              : (i.isEven ? p.pipe : p.pipeDark),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..color = p.outline,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: revive ? 'REVIVE' : 'LOSE',
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 1.2,
            color: revive ? const Color(0xFF0F172A) : Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.rotate(start + seg / 2);
      canvas.translate(wheelR * 0.6, 0);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    // hub
    canvas.drawCircle(Offset.zero, 24, Paint()..color = p.outline);
    canvas.drawCircle(Offset.zero, 19, Paint()..color = p.accent);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WheelPainter old) => true;
}

class _PointerPainter extends CustomPainter {
  _PointerPainter(this.p);
  final Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(2, 2)
      ..lineTo(size.width - 2, 2)
      ..lineTo(size.width / 2, size.height - 2)
      ..close();
    canvas.drawPath(path, Paint()..color = p.primary);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = p.outline,
    );
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.p != p;
}

// =====================================================================
// PART 3: the game
// =====================================================================

enum GState { ready, playing, paused, crashed, reviving, dead }

class Pipe {
  Pipe(this.x, this.gapY, this.gap);
  double x; // left edge in pixels
  final double gapY; // centre of the hole
  final double gap; // height of the hole
  bool scored = false;
}

class Cloud {
  Cloud(this.x, this.y, this.size, this.speed);
  double x;
  final double y, size, speed;
}

/// A little bit of flying confetti or feather.
class Particle {
  Particle(
    this.x,
    this.y,
    this.vx,
    this.vy,
    this.life,
    this.size,
    this.color,
    this.spin,
  ) : maxLife = life;
  double x, y, vx, vy, life, rot = 0;
  final double maxLife, size, spin;
  final Color color;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.particles);
  final List<Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final q in particles) {
      final a = (q.life / q.maxLife).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(q.x, q.y);
      canvas.rotate(q.rot);
      final paint = Paint()
        ..color = q.color.withValues(alpha: min(1.0, a * 1.6));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: q.size,
            height: q.size * 0.55,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}

/// Two layers of soft rolling hills that scroll slower than the ground.
class _HillsPainter extends CustomPainter {
  _HillsPainter(this.offset, this.baseY, this.far, this.near);
  final double offset, baseY;
  final Color far, near;

  void _layer(
    Canvas canvas,
    Size size,
    double shift,
    double amp,
    double period,
    double lift,
    Color color,
  ) {
    final path = Path()..moveTo(0, size.height);
    for (double x = 0; x <= size.width + 8; x += 8) {
      final y =
          baseY - lift - amp * (0.5 + 0.5 * sin((x + shift) / period * 2 * pi));
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _layer(canvas, size, offset * 0.12, 70, 520, 40, far);
    _layer(canvas, size, offset * 0.25 + 200, 50, 340, 8, near);
  }

  @override
  bool shouldRepaint(_HillsPainter old) =>
      old.offset != offset ||
      old.baseY != baseY ||
      old.far != far ||
      old.near != near;
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.onExit});

  /// Called when the player picks "Main menu" on the game-over card.
  final VoidCallback? onExit;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // numbers you can tweak
  static const double gravity = 2000; // pixels per second, per second
  static const double flapSpeed = -640; // negative = up
  static const double birdR = 22; // hit radius of the bird
  static const double pipeW = 78;
  static const double capH = 30;
  static const double capOver = 6; // how far the pipe cap sticks out
  static const double groundH = 96;
  static const double spacing = 280; // distance between pipes
  static const double pipeMargin = 90; // min distance from hole to edges
  static const double shakeTime = 0.35;

  late final Ticker _ticker;
  final ValueNotifier<int> frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  double time = 0; // game clock in seconds

  double w = 0, h = 0;
  double birdY = 0, vel = 0;
  final List<Pipe> pipes = [];
  final List<Cloud> clouds = [];
  final List<Particle> particles = [];
  double groundX = 0;
  int score = 0, best = 0;
  bool newBest = false;
  bool choosing = false; // after a crash: showing the Spin / Quit choice
  GState state = GState.ready;
  double shake = 0; // seconds of screen shake left
  double countdown = 0; // revive countdown (3 -> 0)
  int shownCount = 0; // the number on screen: 3, 2, 1
  double invincible = 0; // seconds of protection after a revive
  bool reduce = false;
  final Random rand = Random();

  double get birdX => w * 0.3;
  double get floorY => h - groundH;
  double get currentGap => 215 - min(score, 15) * 2.5;
  double get speed => 165 + min(score, 20) * 3.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Sfx.onEscape =
        _onEscape; // Esc pauses / resumes (sent from MainActivity.kt)
    Sfx.loadBest().then((v) {
      if (mounted && v > best) setState(() => best = v);
    });
    // a Ticker fires once per screen frame, so the game is smooth
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    Sfx.onEscape = null;
    Sfx.music(false);
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    frame.dispose();
    super.dispose();
  }

  // Android sends Esc / the Back button here instead of as a normal key.
  @override
  Future<bool> didPopRoute() async {
    if (state == GState.playing || state == GState.paused) {
      _togglePause();
      return true;
    }
    return false;
  }

  void _onEscape() {
    if (state == GState.playing || state == GState.paused) _togglePause();
  }

  // pause automatically if the player leaves the app mid-game
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) {
      Sfx.music(false);
      if (state == GState.playing) setState(() => state = GState.paused);
    } else {
      setState(() {}); // build() restarts the music if it should be playing
    }
  }

  void _layout(double width, double height) {
    if (w == width && h == height) return;
    w = width;
    h = height;
    if (clouds.isEmpty) {
      for (var i = 0; i < 5; i++) {
        clouds.add(
          Cloud(
            rand.nextDouble() * w,
            h * (0.08 + rand.nextDouble() * 0.38),
            70 + rand.nextDouble() * 70,
            8 + rand.nextDouble() * 14,
          ),
        );
      }
    }
    if (state == GState.ready) {
      birdY = h * 0.42;
    } else {
      // screen size changed mid-game (rotation): keep the bird on screen
      birdY = birdY.clamp(birdR, max(birdR, floorY - birdR)).toDouble();
    }
  }

  // ---------------------------------------------------------------
  // the game loop (runs once per frame)
  // ---------------------------------------------------------------

  void _onTick(Duration elapsed) {
    final dt = min((elapsed - _last).inMicroseconds / 1e6, 0.05);
    _last = elapsed;
    if (w == 0 || state == GState.paused) return;
    time += dt;

    if (!reduce) {
      for (final c in clouds) {
        c.x -= c.speed * dt;
        if (c.x + c.size < -20) c.x = w + 20;
      }
    }

    for (final q in particles) {
      q.life -= dt;
      q.vy += 900 * dt;
      q.x += q.vx * dt;
      q.y += q.vy * dt;
      q.rot += q.spin * dt;
    }
    particles.removeWhere((q) => q.life <= 0);

    switch (state) {
      case GState.ready:
        birdY = h * 0.42 + sin(time * 3) * 10; // bob while waiting
        groundX += 60 * dt;
      case GState.playing:
        _stepPlaying(dt);
      case GState.crashed:
        // the world freezes where you crashed; only the shake keeps going
        if (shake <= 0 && particles.isEmpty) return;
        shake = max(0, shake - dt);
      case GState.reviving:
        _stepReviving(dt);
      case GState.dead:
        final landed = birdY + birdR >= floorY;
        if (shake <= 0 && landed && particles.isEmpty) return; // nothing moving
        shake = max(0, shake - dt);
        if (!landed) {
          vel += gravity * dt;
          birdY = min(birdY + vel * dt, floorY - birdR);
        }
      case GState.paused:
        return;
    }
    frame.value++;
  }

  void _stepPlaying(double dt) {
    vel += gravity * dt;
    birdY += vel * dt;
    groundX += speed * dt;
    if (invincible > 0) invincible = max(0, invincible - dt);

    for (final pipe in pipes) {
      pipe.x -= speed * dt;
    }
    pipes.removeWhere((pipe) => pipe.x + pipeW + capOver < 0);

    // add a new pipe once the last one has moved far enough
    if (pipes.isEmpty || pipes.last.x < w - spacing) {
      final g = currentGap;
      final room = max(0.0, floorY - 2 * pipeMargin - g);
      pipes.add(Pipe(w, pipeMargin + g / 2 + rand.nextDouble() * room, g));
    }

    // score a point when a pipe passes the bird
    for (final pipe in pipes) {
      if (!pipe.scored && pipe.x + pipeW < birdX - birdR) {
        pipe.scored = true;
        // no free points while the bird is protected after a revive
        if (invincible <= 0) {
          setState(() => score++);
          Sfx.play(score % 10 == 0 ? 'milestone' : 'score');
        }
      }
    }

    // ceiling
    if (birdY - birdR < 0) {
      birdY = birdR;
      vel = 0;
    }

    // collisions (the hitbox is a bit smaller than the drawing, to be fair)
    final r = birdR * 0.85;
    if (invincible > 0) {
      // protected right after a revive: the floor holds you up, pipes pass through
      if (birdY + r > floorY) {
        birdY = floorY - r - 1;
        vel = 0;
      }
      return;
    }
    var hit = birdY + r > floorY;
    for (final pipe in pipes) {
      final overlapX = birdX + r > pipe.x && birdX - r < pipe.x + pipeW;
      final outsideGap =
          birdY - r < pipe.gapY - pipe.gap / 2 ||
          birdY + r > pipe.gapY + pipe.gap / 2;
      if (overlapX && outsideGap) hit = true;
    }
    if (hit) _crash();
  }

  void _stepReviving(double dt) {
    countdown -= dt;
    final n = max(0, countdown.ceil());
    if (n != shownCount && n > 0) {
      shownCount = n;
      Sfx.play('beep');
      setState(() {});
    }
    if (countdown <= 0) {
      Sfx.play('go');
      setState(() {
        state = GState.playing;
        vel = flapSpeed;
        invincible = 1.8;
      });
    }
  }

  // ---------------------------------------------------------------
  // what happens when things happen
  // ---------------------------------------------------------------

  /// Sprays [n] bits in the given colours from the bird's position.
  void _burst(
    int n,
    List<Color> colors, {
    double speed = 320,
    double up = 200,
  }) {
    if (reduce) return;
    for (var i = 0; i < n; i++) {
      final a = rand.nextDouble() * 2 * pi;
      final s = speed * (0.35 + rand.nextDouble() * 0.65);
      particles.add(
        Particle(
          birdX,
          birdY,
          cos(a) * s,
          sin(a) * s - up,
          0.8 + rand.nextDouble() * 0.7,
          8 + rand.nextDouble() * 8,
          colors[rand.nextInt(colors.length)],
          (rand.nextDouble() - 0.5) * 16,
        ),
      );
    }
  }

  void _crash() {
    HapticFeedback.heavyImpact();
    Sfx.play('hit');
    _burst(18, const [Palette.birdBody, Palette.birdWing, Palette.birdBeak]);
    setState(() {
      state = GState.crashed;
      choosing = true;
      shake = reduce ? 0 : shakeTime;
    });
  }

  void _chooseSpin() => setState(() => choosing = false);

  /// Quit = leave the game and go back to the home screen.
  void _quit() {
    if (state == GState.crashed || state == GState.paused) _recordBest();
    Sfx.music(false);
    widget.onExit?.call();
  }

  /// Skip the wheel and start a fresh run.
  void _playAgainNow() {
    _recordBest();
    _restart();
  }

  void _recordBest() {
    newBest = score > best;
    best = max(best, score);
    if (newBest) {
      Sfx.saveBest(best);
      Sfx.play('best');
    }
  }

  /// The wheel said REVIVE: the bird comes back where it crashed.
  void _revive() {
    // only nudge it if it would die again at once (inside a pipe)
    var y = birdY;
    const r = birdR;
    for (final pipe in pipes) {
      if (birdX + r + 6 > pipe.x && birdX - r - 6 < pipe.x + pipeW) {
        final lo = pipe.gapY - pipe.gap / 2 + r + 10;
        final hi = pipe.gapY + pipe.gap / 2 - r - 10;
        y = y.clamp(lo, max(lo, hi)).toDouble();
      }
    }
    y = y.clamp(r + 30, max(r + 30, floorY - 140)).toDouble();
    Sfx.play('beep');
    final pal = Palette.of(context);
    birdY = y;
    _burst(
      36,
      [pal.primary, pal.accent, pal.pipe, Palette.birdBody, Colors.white],
      speed: 420,
      up: 260,
    );
    setState(() {
      vel = 0;
      countdown = 3;
      shownCount = 3;
      state = GState.reviving;
    });
  }

  /// The wheel said LOSE: the run is over.
  void _lose() {
    setState(() {
      state = GState.dead;
      vel = 0;
      _recordBest();
    });
  }

  void _restart() {
    setState(() {
      pipes.clear();
      score = 0;
      vel = 0;
      invincible = 0;
      birdY = h * 0.42;
      newBest = false;
      state = GState.ready;
    });
  }

  void _onTapDown() {
    if (state == GState.ready) {
      setState(() => state = GState.playing);
      _flap();
    } else if (state == GState.playing) {
      _flap();
    }
  }

  void _flap() {
    vel = flapSpeed;
    Sfx.play('flap');
    HapticFeedback.selectionClick();
  }

  void _togglePause() {
    Sfx.play('pause');
    setState(() {
      if (state == GState.playing) {
        state = GState.paused;
      } else if (state == GState.paused) {
        state = GState.playing;
      }
    });
  }

  // ---------------------------------------------------------------
  // build
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    reduce = MediaQuery.disableAnimationsOf(context);
    final pad = MediaQuery.paddingOf(context);

    // music only plays while the run is actually going
    Sfx.music(
      Sfx.enabled &&
          (state == GState.ready ||
              state == GState.playing ||
              state == GState.reviving),
    );

    return LayoutBuilder(
      builder: (context, c) {
        _layout(c.maxWidth, c.maxHeight);
        final canPause = state == GState.playing || state == GState.paused;

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1) the world. Only this layer redraws every frame.
            Semantics(
              button: true,
              label: state == GState.ready
                  ? 'Tap to start flying'
                  : 'Tap to flap',
              onTap: _onTapDown,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => _onTapDown(),
                child: RepaintBoundary(
                  child: ValueListenableBuilder<int>(
                    valueListenable: frame,
                    builder: (context, _, _) => _world(p),
                  ),
                ),
              ),
            ),

            // 2) score
            Positioned(
              top: pad.top + 16,
              left: 0,
              right: 0,
              child: IgnorePointer(child: Center(child: _scoreChip(p))),
            ),

            // 3) sound on/off
            Positioned(
              top: pad.top + 12,
              left: 16,
              child: ClayButton(
                icon: Sfx.enabled
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                semanticsLabel: Sfx.enabled ? 'Mute sound' : 'Turn sound on',
                color: p.surface,
                textColor: p.text,
                border: p.outline,
                onPressed: () => setState(() => Sfx.enabled = !Sfx.enabled),
              ),
            ),

            // 4) pause button (hidden when it isn't useful)
            if (canPause)
              Positioned(
                top: pad.top + 12,
                right: 16,
                child: ClayButton(
                  icon: state == GState.paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  semanticsLabel: state == GState.paused ? 'Resume' : 'Pause',
                  color: p.accent,
                  textColor: p.onAccent,
                  border: p.outline,
                  onPressed: _togglePause,
                ),
              ),

            // 5) messages and overlays
            if (state == GState.ready) _readyHint(p, c.maxHeight),
            if (state == GState.paused) _pausedOverlay(p),
            if (state == GState.crashed && choosing) _gameOver(p),
            if (state == GState.crashed && !choosing) _wheelOverlay(),
            if (state == GState.reviving) _countdownOverlay(p),
            if (state == GState.dead) _gameOver(p),
          ],
        );
      },
    );
  }

  Widget _scoreChip(Palette p) {
    return Semantics(
      liveRegion: true,
      label: 'Score $score',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(score),
        tween: Tween(begin: reduce ? 1.0 : 1.3, end: 1.0),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 240),
        curve: Curves.easeOutBack,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
        child: Container(
          constraints: const BoxConstraints(minWidth: 72),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: p.outline, width: 3),
            boxShadow: [
              BoxShadow(color: p.outline, offset: const Offset(0, 5)),
            ],
          ),
          child: Text(
            '$score',
            textAlign: TextAlign.center,
            style: heading(p, 40),
          ),
        ),
      ),
    );
  }

  Widget _readyHint(Palette p, double height) {
    final pulse = reduce ? 1.0 : 1 + sin(time * 4) * 0.03;
    return Positioned(
      left: 0,
      right: 0,
      top: height * 0.58,
      child: IgnorePointer(
        child: Center(
          child: Transform.scale(
            scale: pulse,
            child: ClayCard(
              child: Text(
                'Tap to flap',
                textAlign: TextAlign.center,
                style: heading(p, 28),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pausedOverlay(Palette p) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // swallow taps so the bird doesn't flap
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.4),
          child: Center(
            child: ClayCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Paused', style: heading(p, 36)),
                  const SizedBox(height: 20),
                  ClayButton(
                    label: 'Resume',
                    icon: Icons.play_arrow_rounded,
                    color: p.primary,
                    textColor: p.onPrimary,
                    border: p.outline,
                    onPressed: _togglePause,
                  ),
                  if (widget.onExit != null) ...[
                    const SizedBox(height: 14),
                    ClayButton(
                      label: 'Quit',
                      icon: Icons.logout_rounded,
                      color: p.surface,
                      textColor: p.text,
                      border: p.outline,
                      onPressed: _quit,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wheelOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          // shrinks on small screens so it always fits
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SpinWheelCard(
              key: const ValueKey('wheel'),
              score: score,
              onRevive: _revive,
              onLose: _lose,
            ),
          ),
        ),
      ),
    );
  }

  Widget _countdownOverlay(Palette p) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Semantics(
            liveRegion: true,
            label: 'Resuming in $shownCount',
            excludeSemantics: true,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(shownCount),
              tween: Tween(begin: reduce ? 1.0 : 1.5, end: 1.0),
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 450),
              curve: Curves.easeOutBack,
              builder: (context, s, child) =>
                  Transform.scale(scale: s, child: child),
              child: Text(
                '$shownCount',
                style: heading(p, 140, color: Colors.white).copyWith(
                  shadows: [
                    Shadow(color: p.outline, offset: const Offset(0, 6)),
                    const Shadow(color: Colors.black54, blurRadius: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One card for both moments: right after a crash (can still spin) and
  /// after the run is really over.
  Widget _gameOver(Palette p) {
    final crashed = state == GState.crashed;
    final shownBest = max(best, score);
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.25),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: reduce ? 1.0 : 0.85, end: 1.0),
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              builder: (context, s, child) =>
                  Transform.scale(scale: s, child: child),
              child: ClayCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      liveRegion: true,
                      label: crashed
                          ? 'You crashed. Score $score. Best $shownBest.'
                          : 'Game over. Score $score. Best $best.',
                      excludeSemantics: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            crashed ? 'You crashed!' : 'Game over',
                            style: heading(p, 36),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            crashed
                                ? 'Spin the wheel for a revive?'
                                : 'The wheel said no.',
                            style: body(p, 16, color: p.muted),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _stat(p, 'SCORE', score),
                              _stat(p, 'BEST', crashed ? shownBest : best),
                            ],
                          ),
                          if (newBest) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: p.accent,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: p.outline, width: 2),
                              ),
                              child: Text(
                                'New best!',
                                style: heading(p, 18, color: p.onAccent),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (crashed) ...[
                      ClayButton(
                        label: 'Spin the wheel',
                        icon: Icons.casino_rounded,
                        color: p.primary,
                        textColor: p.onPrimary,
                        border: p.outline,
                        onPressed: _chooseSpin,
                      ),
                      const SizedBox(height: 14),
                    ],
                    ClayButton(
                      label: 'Play again',
                      icon: Icons.replay_rounded,
                      color: crashed ? p.surface : p.primary,
                      textColor: crashed ? p.text : p.onPrimary,
                      border: p.outline,
                      onPressed: crashed ? _playAgainNow : _restart,
                    ),
                    if (widget.onExit != null) ...[
                      const SizedBox(height: 14),
                      ClayButton(
                        label: 'Quit',
                        icon: Icons.logout_rounded,
                        color: p.surface,
                        textColor: p.text,
                        border: p.outline,
                        onPressed: _quit,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(Palette p, String label, int value) {
    return Column(
      children: [
        Text(label, style: body(p, 16, color: p.muted)),
        Text('$value', style: heading(p, 44)),
      ],
    );
  }

  // ---------------------------------------------------------------
  // the world (sky, clouds, pipes, ground, bird)
  // ---------------------------------------------------------------

  Widget _world(Palette p) {
    final k = shake > 0 ? shake / shakeTime : 0.0;
    final dx = (rand.nextDouble() - 0.5) * 16 * k;
    final dy = (rand.nextDouble() - 0.5) * 16 * k;
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [p.skyTop, p.skyMid, p.skyLow],
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _HillsPainter(
                reduce ? 0 : groundX,
                floorY,
                Color.lerp(p.skyLow, p.pipe, 0.18)!,
                Color.lerp(p.skyLow, p.pipe, 0.32)!,
              ),
            ),
          ),
          for (final c in clouds) _cloud(c, p),
          for (final pipe in pipes) ..._pipe(pipe, p),
          _ground(p),
          _bird(p),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ParticlePainter(particles)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cloud(Cloud c, Palette p) {
    final s = c.size;
    Widget blob(double wd, double ht) => DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ht),
      ),
      child: SizedBox(width: wd, height: ht),
    );
    return Positioned(
      left: c.x,
      top: c.y,
      child: Opacity(
        opacity: p.cloudAlpha,
        child: SizedBox(
          width: s,
          height: s * 0.5,
          child: Stack(
            children: [
              Positioned(left: 0, bottom: 0, child: blob(s, s * 0.28)),
              Positioned(
                left: s * 0.15,
                bottom: s * 0.12,
                child: blob(s * 0.42, s * 0.36),
              ),
              Positioned(
                left: s * 0.46,
                bottom: s * 0.12,
                child: blob(s * 0.32, s * 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _pipe(Pipe pipe, Palette p) {
    final holeTop = pipe.gapY - pipe.gap / 2;
    final holeBottom = pipe.gapY + pipe.gap / 2;
    final lowerBodyTop = holeBottom + capH - 4;
    return [
      Positioned(
        left: pipe.x,
        top: -12,
        width: pipeW,
        height: max(0, holeTop - capH + 16),
        child: _pipePart(p),
      ),
      Positioned(
        left: pipe.x - capOver,
        top: holeTop - capH,
        width: pipeW + capOver * 2,
        height: capH,
        child: _pipePart(p, cap: true),
      ),
      Positioned(
        left: pipe.x - capOver,
        top: holeBottom,
        width: pipeW + capOver * 2,
        height: capH,
        child: _pipePart(p, cap: true),
      ),
      Positioned(
        left: pipe.x,
        top: lowerBodyTop,
        width: pipeW,
        height: max(0, floorY + 12 - lowerBodyTop),
        child: _pipePart(p),
      ),
    ];
  }

  Widget _pipePart(Palette p, {bool cap = false}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.pipe,
        borderRadius: BorderRadius.circular(cap ? 12 : 6),
        border: Border.all(color: p.pipeDark, width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            offset: const Offset(0, 4),
            blurRadius: 6,
          ),
        ],
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: FractionallySizedBox(
            heightFactor: 0.7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.pipeLight.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const SizedBox(width: 8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ground(Palette p) {
    const stripe = 44.0;
    final off = groundX % stripe;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: groundH,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.ground,
                border: Border(top: BorderSide(color: p.groundDark, width: 6)),
              ),
            ),
          ),
          for (var i = -1; i < (w / stripe).ceil() + 1; i++)
            Positioned(
              left: i * stripe - off,
              top: 26,
              width: 22,
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.groundDark.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bird(Palette p) {
    final angle = (vel / 900).clamp(-0.45, 1.1);
    final flap = reduce
        ? 0.0
        : sin(time * (state == GState.playing ? 22 : 8)) * 0.5;
    // blinks while protected after a revive
    final blink = invincible > 0 && sin(time * 30) < 0 ? 0.35 : 1.0;
    return Positioned(
      left: birdX - 26,
      top: birdY - 26,
      width: 52,
      height: 52,
      child: Opacity(
        opacity: blink,
        child: Transform.rotate(
          angle: angle,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // body
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Palette.birdBody,
                  shape: BoxShape.circle,
                  border: Border.all(color: Palette.birdOutline, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      offset: const Offset(0, 4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const SizedBox.expand(),
              ),
              // wing
              Positioned(
                left: 6,
                top: 26,
                width: 22,
                height: 14,
                child: Transform.rotate(
                  angle: flap,
                  alignment: Alignment.centerRight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Palette.birdWing,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Palette.birdOutline, width: 3),
                    ),
                  ),
                ),
              ),
              // eye
              Positioned(
                right: 9,
                top: 10,
                width: 16,
                height: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Palette.birdOutline, width: 2),
                  ),
                  child: Align(
                    alignment: const Alignment(0.5, 0),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Palette.birdOutline,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox(width: 6, height: 6),
                    ),
                  ),
                ),
              ),
              // beak
              Positioned(
                right: -8,
                top: 26,
                width: 18,
                height: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Palette.birdBeak,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Palette.birdOutline, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
