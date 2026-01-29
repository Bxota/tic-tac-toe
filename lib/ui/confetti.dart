import 'dart:math';

import 'package:flutter/material.dart';

class ConfettiParticle {
  ConfettiParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.drift,
    required this.rotation,
    required this.rotationSpeed,
    required this.color,
  });

  final double x;
  final double y;
  final double size;
  final double speed;
  final double drift;
  final double rotation;
  final double rotationSpeed;
  final Color color;

  static ConfettiParticle random(Random random, List<Color> palette) {
    final color = palette[random.nextInt(palette.length)];
    return ConfettiParticle(
      x: random.nextDouble(),
      y: -0.2 + random.nextDouble() * 0.4,
      size: 3 + random.nextDouble() * 4,
      speed: 60 + random.nextDouble() * 120,
      drift: -30 + random.nextDouble() * 60,
      rotation: random.nextDouble() * pi * 2,
      rotationSpeed: -3 + random.nextDouble() * 6,
      color: color,
    );
  }
}

class ConfettiOverlay extends StatelessWidget {
  const ConfettiOverlay({
    super.key,
    required this.animation,
    required this.particles,
  });

  final Animation<double> animation;
  final List<ConfettiParticle> particles;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ConfettiPainter(
        animation: animation,
        particles: particles,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.animation,
    required this.particles,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final List<ConfettiParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final t = animation.value * 1.8;
    final gravity = 220.0;
    final fade = animation.value < 0.7
        ? 1.0
        : (1 - (animation.value - 0.7) / 0.3).clamp(0.0, 1.0);

    for (final particle in particles) {
      final x = particle.x * size.width + particle.drift * t;
      final y = particle.y * size.height +
          particle.speed * t +
          0.5 * gravity * t * t;
      if (y > size.height + particle.size * 2) {
        continue;
      }
      final alpha = particle.color.opacity * fade;
      if (alpha <= 0) {
        continue;
      }
      final paint = Paint()..color = particle.color.withOpacity(alpha);
      final angle = particle.rotation + particle.rotationSpeed * t;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: particle.size * 1.6,
        height: particle.size,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(particle.size * 0.3)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.animation != animation || oldDelegate.particles != particles;
  }
}
