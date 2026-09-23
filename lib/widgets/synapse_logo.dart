import 'package:flutter/material.dart';

/// SynapseMail's brand mark: a small cluster of neuron-like nodes connected
/// by pulsing "synapse" lines, drawn entirely in code (no image assets).
///
/// Used at the top of the Login/Sign up screens as the app's logo, above
/// the "SynapseMail" wordmark.
class SynapseLogo extends StatefulWidget {
  final double size;
  const SynapseLogo({super.key, this.size = 88});

  @override
  State<SynapseLogo> createState() => _SynapseLogoState();
}

class _SynapseLogoState extends State<SynapseLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _SynapsePainter(progress: _controller.value),
          );
        },
      ),
    );
  }
}

class _SynapsePainter extends CustomPainter {
  final double progress;
  _SynapsePainter({required this.progress});

  // Fixed node layout: a central "cell body" with dendrite-like nodes
  // around it, reminiscent of a neuron / synapse cluster.
  static const List<Offset> _nodeOffsets = [
    Offset(0.5, 0.5), // center hub
    Offset(0.18, 0.22),
    Offset(0.82, 0.18),
    Offset(0.85, 0.62),
    Offset(0.52, 0.9),
    Offset(0.14, 0.68),
  ];

  static const List<List<int>> _edges = [
    [0, 1], [0, 2], [0, 3], [0, 4], [0, 5],
  ];

  static const Color _accent = Color(0xFF6C5CE7); // violet - "neural" accent
  static const Color _accentBright = Color(0xFF00E5FF); // cyan pulse

  @override
  void paint(Canvas canvas, Size size) {
    final points = _nodeOffsets
        .map((o) => Offset(o.dx * size.width, o.dy * size.height))
        .toList();

    // Soft glow behind the whole cluster.
    final glowPaint = Paint()
      ..color = _accent.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(points[0], size.width * 0.42, glowPaint);

    // Draw the synapse connections with a traveling pulse.
    for (var i = 0; i < _edges.length; i++) {
      final a = points[_edges[i][0]];
      final b = points[_edges[i][1]];

      final linePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      canvas.drawLine(a, b, linePaint);

      // Pulse dot traveling along the edge, offset per-edge so they don't
      // all move in lockstep.
      final t = (progress + i * 0.17) % 1.0;
      final pulsePos = Offset.lerp(a, b, t)!;
      final pulsePaint = Paint()
        ..color = _accentBright
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(pulsePos, 2.6, pulsePaint);
    }

    // Draw nodes on top.
    for (var i = 0; i < points.length; i++) {
      final isHub = i == 0;
      final radius = isHub ? size.width * 0.11 : size.width * 0.055;

      final nodePaint = Paint()
        ..shader = RadialGradient(
          colors: [
            isHub ? _accentBright : Colors.white,
            _accent,
          ],
        ).createShader(Rect.fromCircle(center: points[i], radius: radius));
      canvas.drawCircle(points[i], radius, nodePaint);

      final ringPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(points[i], radius, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SynapsePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Faint animated circuit/dot-grid background used behind the auth screens
/// for a "tech-centric" feel without being visually loud.
class SynapseBackdrop extends StatelessWidget {
  final Widget child;
  const SynapseBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.6),
              radius: 1.4,
              colors: [Color(0xFF1B1633), Color(0xFF0B0B12)],
            ),
          ),
        ),
        CustomPaint(painter: _DotGridPainter()),
        child,
      ],
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    const spacing = 28.0;
    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) => false;
}
