import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Animated dot-grid background from the web login page. Touch to light up dots
/// (the web reacts to the mouse trail). Falls back to the flat #121212 colour while
/// the shader compiles or if it can't load.
class DotShaderBackground extends StatefulWidget {
  const DotShaderBackground({super.key});

  @override
  State<DotShaderBackground> createState() => _DotShaderBackgroundState();
}

class _DotShaderBackgroundState extends State<DotShaderBackground> with SingleTickerProviderStateMixin {
  static Future<ui.FragmentProgram>? _program;
  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  double _time = 0;
  Offset? _touch; // in uv space, y up
  double _strength = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _program ??= ui.FragmentProgram.fromAsset('shaders/dots.frag');
    _program!.then((p) {
      if (mounted) setState(() => _shader = p.fragmentShader());
    }).catchError((_) {});
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      setState(() {
        _time = elapsed.inMicroseconds / 1e6;
        // trail fades over ~400ms (web: maxAge 400)
        if (_strength > 0) _strength = (_strength - dt / 0.4).clamp(0, 1);
      });
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    super.dispose();
  }

  void _onPointer(Offset local, Size size) {
    // Same cover-UV transform as the shader so the touch lines up with the dots
    final maxSide = size.width > size.height ? size.width : size.height;
    final su = Offset(local.dx / size.width, 1 - local.dy / size.height);
    _touch = Offset(
      ((su.dx - 0.5) * size.width / maxSide + 0.5).clamp(0, 1),
      ((su.dy - 0.5) * size.height / maxSide + 0.5).clamp(0, 1),
    );
    _strength = 1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _onPointer(e.localPosition, size),
        onPointerMove: (e) => _onPointer(e.localPosition, size),
        child: CustomPaint(
          size: size,
          painter: _DotPainter(_shader, _time, _touch, _strength),
        ),
      );
    });
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.shader, this.time, this.touch, this.strength);
  final ui.FragmentShader? shader;
  final double time;
  final Offset? touch;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final s = shader;
    if (s == null) {
      canvas.drawRect(rect, Paint()..color = const Color(0xFF121212));
      return;
    }
    s
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, touch?.dx ?? 0)
      ..setFloat(4, touch?.dy ?? 0)
      ..setFloat(5, strength);
    canvas.drawRect(rect, Paint()..shader = s);
  }

  @override
  bool shouldRepaint(_DotPainter old) => true;
}
