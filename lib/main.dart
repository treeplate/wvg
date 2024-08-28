// ignore_for_file: avoid_print

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const bytesPerBlock = 256;
late final ByteData file;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  file = await rootBundle.load('video-005.wvg');
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: CustomPaint(
        painter: WVGPainter(file),
      ),
    ),
  );
}

class WVGPainter extends CustomPainter {
  WVGPainter(this.file);
  ByteData file;
  @override
  void paint(Canvas canvas, Size size) {
    if (file.getUint32(0, Endian.little) != 0x0A475657 /* WVG\n in utf8 */) {
      return;
    }
    ByteData blockSizes = ByteData.sublistView(file, 4, 256);
    List<int> blockOffsets = [];
    for (int i = 4; i < 256; i += 4) {
      if (i == 4) {
        blockOffsets.add(256);
      } else {
        blockOffsets.add(blockOffsets[((i ~/ 4) - 2)] +
            blockSizes.getUint32(i - 8, Endian.little) * 256);
      }
    }

    double imageWidth;
    double imageHeight;
    if (blockSizes.getUint32(0, Endian.little) == 0) {
      imageWidth = 1;
      imageHeight = 1;
    } else {
      imageWidth = file.getFloat32(256, Endian.little);
      imageHeight = file.getFloat32(260, Endian.little);
    }

    int paramCount = blockSizes.getUint32(28, Endian.little) * 64;
    ByteData rparameters = ByteData.sublistView(
      file,
      blockOffsets[7],
      blockOffsets[8],
    );
    ByteData parameters = ByteData(rparameters.lengthInBytes);
    for (int i = 0; i < paramCount * 4; i += 4) {
      parameters.setUint32(
          i, rparameters.getUint32(i, Endian.little), Endian.little);
      print(
        'param${i ~/ 4}: ${parameters.getUint32(i, Endian.little).toRadixString(16)}',
      );
    }
    //parameters.setFloat32(0, .5, Endian.little);
    int exprCount = blockSizes.getUint32(60, Endian.little);
    ByteData exprResults = ByteData(exprCount * 4);
    for (int currentExpr = 0; currentExpr < exprCount; currentExpr++) {
      ByteData expr = ByteData.sublistView(
        file,
        blockOffsets[15] + currentExpr * bytesPerBlock,
        blockOffsets[15] + (currentExpr + 1) * bytesPerBlock,
      );
      ByteData stack = ByteData(bytesPerBlock);
      int exprIndex = 0;
      int stackIndex = 0;
      int errorCount = 0;
      for (; exprIndex < bytesPerBlock; exprIndex += 4) {
        assert(stackIndex < 64); // TODO: should this be 256?
        print(
            'expr ${expr.getUint32(exprIndex, Endian.little).toRadixString(16)}:');
        if (expr.getUint32(exprIndex, Endian.little) < 0x80000000) {
          print('raw number');
          stack.setUint32(
            stackIndex,
            expr.getUint32(
              exprIndex,
              Endian.little,
            ),
            Endian.little,
          );
          stackIndex += 4;
        } else if (expr.getUint32(exprIndex, Endian.little) < 0x80020001) {
          if (stackIndex < 4) {
            errorCount++;
            print('error type -2: stack index less than one');
          } else if (expr.getUint32(exprIndex, Endian.little) == 0x80000000) {
            print('int-negate');
            stack.setInt32(stackIndex - 4,
                -stack.getInt32(stackIndex - 4, Endian.little), Endian.little);
          } else if (expr.getUint32(exprIndex, Endian.little) == 0x80010000) {
            print('float-negate');
            stack.setFloat32(
                stackIndex - 4,
                -stack.getFloat32(stackIndex - 4, Endian.little),
                Endian.little);
          } else if (expr.getUint32(exprIndex, Endian.little) == 0x80008000) {
            print('round');
            stack.setInt32(
                stackIndex - 4,
                stack.getFloat32(stackIndex - 4, Endian.little).round(),
                Endian.little);
          } else if (expr.getUint32(exprIndex, Endian.little) == 0x80018000) {
            print('round to float');
            stack.setFloat32(
                stackIndex - 4,
                stack.getInt32(stackIndex - 4, Endian.little).roundToDouble(),
                Endian.little);
          } else if (expr.getUint32(exprIndex, Endian.little) == 0x80020000) {
            print('duplicate');
            stack.setInt32(stackIndex,
                stack.getInt32(stackIndex - 4, Endian.little), Endian.little);
            stackIndex += 4;
          } else {
            errorCount++;
            print('error type -1: invalid one-operand expression');
          }
        } else if (expr.getUint32(exprIndex, Endian.little) < 0xC0010005) {
          if (stackIndex < 8) {
            print('error type 1 $stackIndex');
            errorCount++;
          } else if (expr.getUint32(exprIndex, Endian.little) == 0xC0000001) {
            print('int add');
            stack.setInt32(
                stackIndex - 8,
                stack.getInt32(stackIndex - 8, Endian.little) +
                    stack.getInt32(stackIndex - 4, Endian.little),
                Endian.little);
            stackIndex -= 4;
          } else if (stack.getUint32(exprIndex, Endian.little) == 0xC0000002) {
            print('int minus');
            stack.setInt32(
                stackIndex - 8,
                stack.getInt32(stackIndex - 8, Endian.little) -
                    stack.getInt32(stackIndex - 4, Endian.little),
                Endian.little);
            stackIndex -= 4;
          } else if (expr.getUint32(exprIndex, Endian.little) == 0xC0000003) {
            print('int *');
            stack.setInt32(
                stackIndex - 8,
                stack.getInt32(stackIndex - 8, Endian.little) *
                    stack.getInt32(stackIndex - 4, Endian.little),
                Endian.little);
            stackIndex -= 4;
          } else if (expr.getUint32(exprIndex, Endian.little) == 0xC0000004) {
            print('~/');
            stack.setInt32(
                stackIndex - 8,
                stack.getInt32(stackIndex - 8, Endian.little) ~/
                    stack.getInt32(stackIndex - 4, Endian.little),
                Endian.little);
            stackIndex -= 4;
          } else if (expr.getUint32(exprIndex, Endian.little) == 0xC0010001) {
            print('float add');
            stack.setFloat32(
                stackIndex - 8,
                stack.getFloat32(stackIndex - 8, Endian.little) +
                    stack.getFloat32(stackIndex - 4, Endian.little),
                Endian.little);
            stackIndex -= 4;
          } else if (expr.getUint32(exprIndex, Endian.little) == 0xC0010002) {
            print('float -');
            stack.setFloat32(
                stackIndex - 8,
                stack.getFloat32(stackIndex - 8, Endian.little) -
                    stack.getFloat32(stackIndex - 4, Endian.little),
                Endian.little);
            stackIndex -= 4;
          } else if (expr.getUint32(exprIndex, Endian.little) == 0xC0010003) {
            print('float times');
            stack.setFloat32(
                stackIndex - 8,
                stack.getFloat32(stackIndex - 8, Endian.little) *
                    stack.getFloat32(stackIndex - 4, Endian.little),
                Endian.little);
            stackIndex -= 4;
          } else if (expr.getUint32(exprIndex, Endian.little) == 0xC0010004) {
            print('float /');
            stack.setFloat32(
                stackIndex - 8,
                stack.getFloat32(stackIndex - 8, Endian.little) /
                    stack.getFloat32(stackIndex - 4, Endian.little),
                Endian.little);
            stackIndex -= 4;
          } else {
            print('error type 0: invalid two-operand expression');
            errorCount++;
          }
        } else if (expr.getUint32(exprIndex, Endian.little) < 0xFFF000000) {
          if (expr.getUint32(exprIndex, Endian.little) == 0xFFC00000) {
            break; // terminate
          }
          if (expr.getUint32(exprIndex, Endian.little) >> 16 == 0xFFD0) {
            // parameter reference
            if (expr.getUint32(exprIndex, Endian.little) - 0xFFD00000 >=
                paramCount) {
              print('error type 2: reference nonexistent parameter');
              errorCount++;
              continue;
            }
            print('parameter reference');
            stack.setUint32(
                stackIndex,
                parameters.getUint32(
                    (expr.getUint32(exprIndex, Endian.little) - 0xFFD00000) * 4,
                    Endian.little),
                Endian.little);
            stackIndex += 4;
          } else if (expr.getUint32(exprIndex, Endian.little) >> 16 == 0xFFE0) {
            // expression reference
            if (expr.getUint32(exprIndex, Endian.little) - 0xFFE00000 >=
                currentExpr) {
              errorCount++;
              print('error type 3: cannot reference future expression');
              continue;
            }
            print('expression reference');
            stack.setUint32(
                stackIndex,
                exprResults.getUint32(
                    (expr.getUint32(exprIndex, Endian.little) - 0xFFE00000) * 4,
                    Endian.little),
                Endian.little);
            stackIndex += 4;
          } else {
            print(
                'error type 4: unexpected high sixteen bits for no-argument expression');
            errorCount++;
          }
        } else {
          print('error type 5: expression more than or equal to 0xFFF000000');
          errorCount++;
        }
      }
      if (stackIndex == 0) {
        stack.setUint32(0, 0, Endian.little);
        stackIndex += 4;
      }
      print('stack index: $stackIndex');
      print('result: ${stack.getFloat32(stackIndex - 4, Endian.little)}');
      print('\n');
      exprResults.setUint32(currentExpr * 4,
          stack.getUint32(stackIndex - 4, Endian.little), Endian.little);
      //if (errorCount != 0) return;
    }
    int matrixCount = blockSizes.getUint32(23 * 4, Endian.little) * 4;
    ByteData matrices = ByteData.sublistView(
      file,
      blockOffsets[23],
      blockOffsets[24],
    );
    Matrix getMatrix(int i) {
      if (i >= matrixCount) {
        return Matrix(
            true, true, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
      }
      bool static = true;
      bool valid = true;
      ByteData cell(int j) {
        return ByteData.sublistView(
            matrices, i * 64 + j * 4, (i * 64 + j * 4) + 4);
      }

      List<double> result = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          ByteData value = cell(x * 4 + y);
          double float = value.getFloat32(0, Endian.little);
          int uint = value.getUint32(0, Endian.little);
          if (!float.isNaN) {
            result[x * 4 + y] = float;

            continue;
          }
          int mode = uint >> 16;
          int arg = uint - (mode << 16);
          if (mode == 0xFFD0) {
            static = false;
            result[x * 4 + y] = parameters.getFloat32(arg * 4, Endian.little);
          } else if (mode == 0xFFE0) {
            static = false;
            result[x * 4 + y] = exprResults.getFloat32(arg * 4, Endian.little);
          } else {
            valid = false;
            result[x * 4 + y] = float;
          }
        }
      }
      return Matrix(static, valid, result);
    }

    Curve getCurve(int i, int b, int g) {
      int group = i ~/ 64;
      int groupOffset = blockOffsets[31] + b + group * g;
      assert(groupOffset < blockOffsets[32]);
      ByteData? rawcell(int j) {
        if (j >= g) return null;
        return ByteData.sublistView(
          file,
          groupOffset + (j * bytesPerBlock) + (i % 64) * 4,
          groupOffset + (j * bytesPerBlock) + (i % 64) * 4 + 4,
        );
      }

      bool static = true;
      bool valid = true;
      ByteData cell(int j) {
        final raw = rawcell(j);
        if (raw == null) {
          return ByteData(4)..setUint32(0, 0xFFFFFFFF, Endian.little);
        }
        if (!raw.getFloat32(0, Endian.little).isNaN) return raw;
        int uint = raw.getUint32(0, Endian.little);
        int mode = uint >> 16;
        int arg = uint - (mode << 16);
        static = false;
        if (mode == 0xFFC0) {
          return ByteData.sublistView(parameters, arg * 4, arg * 4 + 4);
        }
        if (mode == 0xFFC0) {
          return ByteData.sublistView(exprResults, arg * 4, arg * 4 + 4);
        }
        valid = false;
        return raw;
      }

      if ((cell(6).getUint32(0, Endian.little) == 0xFFFFFFFF) &&
          !cell(5).getFloat32(0, Endian.little).isNaN) {
        return CubicBezierCurve(
          cell(2).getFloat32(0, Endian.little),
          cell(3).getFloat32(0, Endian.little),
          cell(4).getFloat32(0, Endian.little),
          cell(5).getFloat32(0, Endian.little),
          cell(0).getFloat32(0, Endian.little),
          cell(1).getFloat32(0, Endian.little),
          static,
          valid,
        );
      }
      if (cell(5).getUint32(0) == 0xFFFFFFFF) {
        return RationalQuadraticBezierCurve(
          cell(2).getFloat32(0, Endian.little),
          cell(3).getFloat32(0, Endian.little),
          cell(0).getFloat32(0, Endian.little),
          cell(1).getFloat32(0, Endian.little),
          cell(4).getFloat32(0, Endian.little),
          static,
          valid,
        );
      }
      valid = false;
      return Curve(static, valid);
    }

    ByteData rawShapes = ByteData.sublistView(
      file,
      blockOffsets[35],
      blockOffsets[36],
    );
    List<Shape> shapes = [];
    for (int i = 0; i < rawShapes.lengthInBytes; i += 16) {
      int startBlockIndex = rawShapes.getUint32(i, Endian.little);
      int startCurveIndex = rawShapes.getUint32(i + 4, Endian.little);
      int curveCount = rawShapes.getUint32(i + 8, Endian.little);
      int groupSize = rawShapes.getUint32(i + 12, Endian.little);
      List<Curve> curves = [];
      for (int i = startCurveIndex; i < startCurveIndex + curveCount; i++) {
        curves.add(getCurve(i, startBlockIndex, groupSize));
      }
      shapes.add(Shape(curves));
    }
    ByteData rawGradients = ByteData.sublistView(
      file,
      blockOffsets[43],
      blockOffsets[44],
    );
    int gradientCount = blockSizes.getUint32(43 * 4, Endian.little) ~/ 2;

    Gradient gradient(int i) {
      if (i * 2 >= gradientCount) {
        return Gradient(
            [0, 1], [const Color(0x00000000), const Color(0x00000000)]);
      }
      ByteData stop(int j) {
        return ByteData.sublistView(
            rawGradients, i * 512 + j * 4, i * 512 + j * 4 + 4);
      }

      int color(int j) {
        return rawGradients.getUint32(i * 512 + j * 4 + 256, Endian.little);
      }

      double lastStop = 0;
      int count = 0;
      List<Color> tempColors = [];
      List<double> tempStops = [];
      for (; count < 64; count++) {
        double valueDouble = stop(count).getFloat32(0, Endian.little);
        int valueInt = stop(count).getUint32(0, Endian.little);
        double nextStop;
        if (!valueDouble.isNaN) {
          nextStop = valueDouble;
        } else {
          int mode = valueInt >> 16;
          int arg = valueInt & 0xFFFF;
          if (mode == 0xFFD0) {
            nextStop = parameters.getFloat32(arg * 4, Endian.little);
          } else if (mode == 0xFFE0) {
            nextStop = exprResults.getFloat32(arg * 4, Endian.little);
          } else {
            nextStop = valueDouble;
          }
        }
        if (count == 0 && nextStop != 0) nextStop = 0;
        if (lastStop < 1 && (nextStop > 1 || nextStop.isNaN)) nextStop = 1.0;
        if (nextStop < lastStop || nextStop > 1 || nextStop.isNaN) break;
        lastStop = nextStop;
        Color nextColor;
        int value = color(count);
        int mode = value >> 16;
        int arg = value - (mode << 16);
        if (mode == 0xFFD0) {
          int expr = parameters.getUint32(arg * 4, Endian.little);
          nextColor = Color((expr >> 8) + (expr << 24));
        } else if (mode == 0xFFE0) {
          int expr = exprResults.getUint32(arg * 4, Endian.little);
          nextColor = Color((expr >> 8) + (expr << 24));
        } else {
          nextColor = const Color(0x00000000);
        }
        tempColors.add(nextColor);
        tempStops.add(nextStop);
      }
      return Gradient(tempStops, tempColors);
    }

    ByteData rawPaintBlocks = ByteData.sublistView(
      file,
      blockOffsets[47],
      blockOffsets[48],
    );
    Paint getPaint(int operator, int color) {
      if (operator == 0xFFFFFFFF) {
        return FlatColorPaint(Color((color >> 8) + (color << 24)));
      }
      int mode = operator >> 16;
      int arg = operator - (mode << 16);
      if (mode == 0xFFD0) {
        int expr = parameters.getUint32(arg * 4, Endian.little);
        return FlatColorPaint(Color((expr >> 8) + (expr << 24)));
      } else if (mode == 0xFFE0) {
        int expr = exprResults.getUint32(arg * 4, Endian.little);
        return FlatColorPaint(Color((expr >> 8) + (expr << 24)));
      } else if (mode == 0xFFF0) {
        int sig = rawPaintBlocks.getUint32(arg * bytesPerBlock, Endian.little);
        return GradientPaint(
            gradient(rawPaintBlocks.getUint32(
                arg * bytesPerBlock + 4, Endian.little)),
            rawPaintBlocks.getUint32(arg * bytesPerBlock + 8, Endian.little),
            getMatrix(rawPaintBlocks.getUint32(
                arg * bytesPerBlock + 12, Endian.little)),
            sig == 0x10);
      } else {
        print(
            'Paint getter failed, mode: ${mode.toRadixString(16)}, arg: ${arg.toRadixString(16)}, color: ${color.toRadixString(16)}');
        return FlatColorPaint(const Color(0x00000000));
      }
    }

    ByteData compBlocks = ByteData.sublistView(
      file,
      blockOffsets[55],
    );

    for (int i = 0; i < blockSizes.getUint32(55 * 4, Endian.little); i++) {
      int matrixi = compBlocks.getUint32(i * bytesPerBlock, Endian.little);
      int shapei = compBlocks.getUint32(i * bytesPerBlock + 4, Endian.little);
      int seqLen = compBlocks.getUint32(i * bytesPerBlock + 8, Endian.little);
      Paint paint = getPaint(
          compBlocks.getUint32(i * bytesPerBlock + 12, Endian.little),
          compBlocks.getUint32(i * bytesPerBlock + 16, Endian.little));
      Path path = Path();
      for (int i = 0; i <= seqLen; i++) {
        Shape shape = shapes[shapei + i];
        Matrix matrix = getMatrix(matrixi + i);
        Path subPath = Path();
        for (Curve curve in shape.curves) {
          if (curve is RationalQuadraticBezierCurve) {
            subPath.conicTo(curve.x1, curve.y1, curve.x2, curve.y2, curve.w);
          }
          if (curve is CubicBezierCurve) {
            subPath.cubicTo(
                curve.x1, curve.y1, curve.x2, curve.y2, curve.x3, curve.y3);
          }
        }
        subPath.close();
        //path.addPath(subPath.transform(Float64List.fromList(matrix.matrix)), Offset.zero);
        path.addPath(subPath, Offset.zero,
            matrix4: Float64List.fromList(matrix.matrix));
      }
      ui.Paint flutterPaint = ui.Paint();
      if (paint is GradientPaint) {
        TileMode mode;
        switch (paint.flags & 3) {
          case 0:
            mode = TileMode.clamp;
            break;
          case 1:
            mode = TileMode.repeated;
            break;
          case 2:
            mode = TileMode.mirror;
            break;
          default:
            mode = TileMode.decal;
            break;
        }
        print('paint: $paint');
        if (paint.linear) {
          flutterPaint.shader = ui.Gradient.linear(
              Offset.zero,
              const Offset(1, 0),
              paint.gradient.colors,
              paint.gradient.stops,
              mode,
              Float64List.fromList(paint.matrix.matrix));
        } else {
          flutterPaint.shader = ui.Gradient.radial(
              Offset.zero,
              1,
              paint.gradient.colors,
              paint.gradient.stops,
              mode,
              Float64List.fromList(paint.matrix.matrix));
        }
      } else if (paint is FlatColorPaint) {
        flutterPaint.color = paint.color;
      }
      canvas.save();
      canvas.scale(size.height / imageHeight);
      canvas.drawPath(path, flutterPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class Paint {}

class FlatColorPaint extends Paint {
  FlatColorPaint(this.color);
  final Color color;
  @override
  String toString() => 'flat $color';
}

class GradientPaint extends Paint {
  GradientPaint(this.gradient, this.flags, this.matrix, this.linear);
  final Gradient gradient;
  final int flags;
  final Matrix matrix;
  final bool linear;
  @override
  String toString() =>
      '${linear ? 'linear' : 'radial'} gradient $gradient with flags $flags and matrix $matrix';
}

class Gradient {
  Gradient(this.stops, this.colors);
  final List<double> stops;
  final List<Color> colors;
  @override
  String toString() => '(stops $stops, colors $colors)';
}

class Shape {
  Shape(this.curves);
  final List<Curve> curves;
  @override
  String toString() => 'curves $curves';
}

class Curve {
  final bool static;
  final bool valid;
  @override
  String toString() => 'static $static valid $valid curve....';

  Curve(this.static, this.valid);
}

class CubicBezierCurve extends Curve {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double x3;
  final double y3;
  @override
  String toString() => 'static $static valid $valid $x1 $y1 $x2 $y2 $x3 $y3';

  CubicBezierCurve(this.x1, this.y1, this.x2, this.y2, this.x3, this.y3,
      bool static, bool valid)
      : super(static, valid);
}

class RationalQuadraticBezierCurve extends Curve {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double w;
  @override
  String toString() => 'static $static valid $valid $x1 $y1 $x2 $y2 w $w';
  RationalQuadraticBezierCurve(
      this.x1, this.y1, this.x2, this.y2, this.w, bool static, bool valid)
      : super(static, valid);
}

class Matrix {
  Matrix(this.static, this.valid, this.matrix) {}
  final bool static;
  final bool valid;
  final List<double> matrix;
  @override
  String toString() => 'static $static valid $valid matrix $matrix';
}
