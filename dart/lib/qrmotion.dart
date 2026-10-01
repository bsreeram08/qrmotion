/// Animated QR codes where every frame still scans.
library;

export 'src/effects.dart' show Effect, Pose, QrEffect, resolveEffect;
export 'src/qr.dart' show Ecc, QR, encode, isFinder;
export 'src/render.dart' show Raster, RenderOptions, Rgb, Shape, VerifyResult, frameShapes, rasterize, verify;
export 'src/widget.dart' show AnimatedQr;
