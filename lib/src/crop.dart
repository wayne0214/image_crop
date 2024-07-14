part of insta_assets_crop;

const _kCropGridColumnCount = 3;
const _kCropGridRowCount = 3;
const _kCropGridColor = Color.fromRGBO(0xd0, 0xd0, 0xd0, 0.9);
const _kCropOverlayActiveOpacity = 0.3;
const _kCropOverlayInactiveOpacity = 0.7;
const _kCropHandleColor = Color.fromRGBO(0xd0, 0xd0, 0xd0, 1.0);
const _kCropHandleHitSize = 48.0;
const _kCropMinFraction = 0.1;
const _kCropBackgroundColor =
    Color.fromRGBO(0x0, 0x0, 0x0, _kCropOverlayInactiveOpacity);

enum _CropAction { none, moving, cropping, scaling }

enum _CropHandleSide { none, topLeft, topRight, bottomLeft, bottomRight }

/// Model containing all the internal parameters of the [Crop] widget
class CropInternal {
  final Rect view, area;
  final double scale;

  const CropInternal({
    required this.view,
    required this.area,
    required this.scale,
  });
}

class Crop extends StatefulWidget {
  final double? aspectRatio;
  final double maximumScale;
  final bool alwaysShowGrid;

  /// Set [disableResize] to `true` in order to hide corner handlers
  ///
  /// Defaults to `false`
  final bool disableResize;

  /// Specifies [backgroundColor] to set the color of the mask that hide the cropped areas
  ///
  /// Defaults to [_kCropBackgroundColor]
  final Color backgroundColor;

  /// To initialize the crop view with data programmatically
  final CropInternal? initialParam;

  final Size size;
  final Widget child;

  const Crop({
    Key? key,
    required this.child,
    required this.size,
    this.aspectRatio,
    this.maximumScale = 2.0,
    this.alwaysShowGrid = false,
    this.disableResize = false,
    this.backgroundColor = _kCropBackgroundColor,
    this.initialParam,
  })  : assert(size != Size.zero, 'Size cannot be zero.'),
        assert(size != Size.infinite, 'Size cannot be infinite.'),
        super(key: key);

  @override
  State<StatefulWidget> createState() => CropState();

  static CropState? of(BuildContext context) =>
      context.findAncestorStateOfType<CropState>();
}

class CropState extends State<Crop> with TickerProviderStateMixin {
  final _surfaceKey = GlobalKey();

  late final AnimationController _activeController;
  late final AnimationController _settleController;

  double _scale = 1.0;
  double _ratio = 1.0;
  Rect _view = Rect.zero;
  Rect _area = Rect.zero;
  Offset _lastFocalPoint = Offset.zero;
  _CropAction _action = _CropAction.none;
  _CropHandleSide _handle = _CropHandleSide.none;

  late double _startScale;
  late Rect _startView;
  late Tween<Rect?> _viewTween;
  late Tween<double> _scaleTween;

  double get scale => _area.shortestSide / _scale;

  Rect? get area => _view.isEmpty
      ? null
      : Rect.fromLTWH(
          max(_area.left * _view.width / _scale - _view.left, 0),
          max(_area.top * _view.height / _scale - _view.top, 0),
          _area.width * _view.width / _scale,
          _area.height * _view.height / _scale,
        );

  bool get _isEnabled => _view.isEmpty == false;

  double get cropHandleSize => widget.disableResize ? 0.0 : 10.0;

  // Saving the length for the widest area for different aspectRatio's
  final Map<double, double> _maxAreaWidthMap = {};

  // Counting pointers(number of user fingers on screen)
  int pointers = 0;

  /// Returns the internal parameters of the state
  /// can be provided using [initialParam] to initialize the view to the same state
  CropInternal get internalParameters =>
      CropInternal(view: _view, area: _area, scale: _scale);

  @override
  void initState() {
    super.initState();
    _updateImage();
    _activeController = AnimationController(
      vsync: this,
      value: widget.alwaysShowGrid ? 1.0 : 0.0,
    )..addListener(() => setState(() {}));
    _settleController = AnimationController(vsync: this)
      ..addListener(_settleAnimationChanged);
  }

  @override
  void dispose() {
    _activeController.dispose();
    _settleController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(Crop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.child.key != oldWidget.child.key ||
        widget.size != oldWidget.size) {
      _updateImage();
    } else if (widget.aspectRatio != oldWidget.aspectRatio) {
      _scale = 1.0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateView());
    }
    if (widget.alwaysShowGrid != oldWidget.alwaysShowGrid) {
      if (widget.alwaysShowGrid) {
        _activate();
      } else {
        _deactivate();
      }
    }
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints.expand(),
        child: Listener(
          onPointerDown: (event) => pointers++,
          onPointerUp: (event) => pointers = 0,
          child: GestureDetector(
            key: _surfaceKey,
            behavior: HitTestBehavior.opaque,
            onScaleStart: _isEnabled ? _handleScaleStart : null,
            onScaleUpdate: _isEnabled ? _handleScaleUpdate : null,
            onScaleEnd: _isEnabled ? _handleScaleEnd : null,
            child: CustomPaint(
              foregroundPainter: _CropPainter(
                ratio: _ratio,
                view: _view,
                area: _area,
                scale: _scale,
                active: _activeController.value,
                backgroundColor: widget.backgroundColor,
                disableResize: widget.disableResize,
                cropHandleSize: cropHandleSize,
              ),
              child: CropTransform(
                ratio: _ratio,
                scale: _scale,
                view: _view,
                childSize: widget.size,
                getRect: (size) => _getRect(size, cropHandleSize),
                child: widget.child,
              ),
            ),
          ),
        ),
      );

  void _activate() {
    _activeController.animateTo(
      1.0,
      curve: Curves.fastOutSlowIn,
      duration: const Duration(milliseconds: 250),
    );
  }

  void _deactivate() {
    if (widget.alwaysShowGrid == false) {
      _activeController.animateTo(
        0.0,
        curve: Curves.fastOutSlowIn,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  Size? get _boundaries {
    final context = _surfaceKey.currentContext;
    if (context == null) {
      return null;
    }

    final size = context.size;
    if (size == null) {
      return null;
    }

    return size - Offset(cropHandleSize, cropHandleSize) as Size;
  }

  Offset? _getLocalPoint(Offset point) {
    final context = _surfaceKey.currentContext;
    if (context == null) {
      return null;
    }

    final box = context.findRenderObject() as RenderBox;

    return box.globalToLocal(point);
  }

  void _settleAnimationChanged() {
    setState(() {
      _scale = _scaleTween.transform(_settleController.value);
      final nextView = _viewTween.transform(_settleController.value);
      if (nextView != null) {
        _view = nextView;
      }
    });
  }

  Rect _calculateDefaultArea({
    required double viewWidth,
    required double viewHeight,
  }) {
    final imageWidth = widget.size.width;
    final imageHeight = widget.size.height;

    double height;
    double width;
    if ((widget.aspectRatio ?? 1.0) < 1) {
      height = 1.0;
      width =
          ((widget.aspectRatio ?? 1.0) * imageHeight * viewHeight * height) /
              imageWidth /
              viewWidth;
      if (width > 1.0) {
        width = 1.0;
        height = (imageWidth * viewWidth * width) /
            (imageHeight * viewHeight * (widget.aspectRatio ?? 1.0));
      }
    } else {
      width = 1.0;
      height = (imageWidth * viewWidth * width) /
          (imageHeight * viewHeight * (widget.aspectRatio ?? 1.0));
      if (height > 1.0) {
        height = 1.0;
        width =
            ((widget.aspectRatio ?? 1.0) * imageHeight * viewHeight * height) /
                imageWidth /
                viewWidth;
      }
    }
    final aspectRatio = _maxAreaWidthMap[widget.aspectRatio];
    if (aspectRatio != null) {
      _maxAreaWidthMap[aspectRatio] = width;
    }

    return Rect.fromLTWH((1.0 - width) / 2, (1.0 - height) / 2, width, height);
  }

  void _updateImage() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      final boundaries = _boundaries;
      if (boundaries == null) {
        return;
      }

      setState(() {
        _ratio = max(
          boundaries.width / widget.size.width,
          boundaries.height / widget.size.height,
        );

        // initialize internal parameters if exists
        if (widget.initialParam != null) {
          _view = widget.initialParam!.view;
          _area = widget.initialParam!.area;
          _scale = widget.initialParam!.scale;
          return;
        }

        _scale = 1;

        _updateView(boundaries);
      });
    });

    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _updateView([Size? b]) {
    final boundaries = b ?? _boundaries;
    if (boundaries == null) {
      return;
    }

    final viewWidth = boundaries.width / (widget.size.width * _scale * _ratio);
    final viewHeight =
        boundaries.height / (widget.size.height * _scale * _ratio);

    setState(() {
      _area =
          _calculateDefaultArea(viewWidth: viewWidth, viewHeight: viewHeight);
      _view = Rect.fromLTWH(
        (viewWidth - 1.0) / 2,
        (viewHeight - 1.0) / 2,
        viewWidth,
        viewHeight,
      );
      // disable initial magnification
      _scale = _minimumScale ?? 1.0;
      _view = _getViewInBoundaries(_scale);
    });
  }

  _CropHandleSide _hitCropHandle(Offset? localPoint) {
    final boundaries = _boundaries;
    if (localPoint == null || boundaries == null) {
      return _CropHandleSide.none;
    }

    final viewRect = Rect.fromLTWH(
      boundaries.width * _area.left,
      boundaries.height * _area.top,
      boundaries.width * _area.width,
      boundaries.height * _area.height,
    ).deflate(cropHandleSize / 2);

    if (widget.disableResize) {
      return _CropHandleSide.none;
    }

    if (Rect.fromLTWH(
      viewRect.left - _kCropHandleHitSize / 2,
      viewRect.top - _kCropHandleHitSize / 2,
      _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.topLeft;
    }

    if (Rect.fromLTWH(
      viewRect.right - _kCropHandleHitSize / 2,
      viewRect.top - _kCropHandleHitSize / 2,
      _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.topRight;
    }

    if (Rect.fromLTWH(
      viewRect.left - _kCropHandleHitSize / 2,
      viewRect.bottom - _kCropHandleHitSize / 2,
      _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.bottomLeft;
    }

    if (Rect.fromLTWH(
      viewRect.right - _kCropHandleHitSize / 2,
      viewRect.bottom - _kCropHandleHitSize / 2,
      _kCropHandleHitSize,
      _kCropHandleHitSize,
    ).contains(localPoint)) {
      return _CropHandleSide.bottomRight;
    }

    return _CropHandleSide.none;
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _activate();
    _settleController.stop(canceled: false);
    _lastFocalPoint = details.focalPoint;
    _action = _CropAction.none;
    _handle = _hitCropHandle(_getLocalPoint(details.focalPoint));
    _startScale = _scale;
    _startView = _view;
  }

  Rect _getViewInBoundaries(double scale) =>
      Offset(
        max(
          min(
            _view.left,
            _area.left * _view.width / scale,
          ),
          _area.right * _view.width / scale - 1.0,
        ),
        max(
          min(
            _view.top,
            _area.top * _view.height / scale,
          ),
          _area.bottom * _view.height / scale - 1.0,
        ),
      ) &
      _view.size;

  double get _maximumScale => widget.maximumScale;

  double? get _minimumScale {
    final boundaries = _boundaries;
    if (boundaries == null || widget.size == Size.zero) {
      return null;
    }

    final scaleX =
        boundaries.width * _area.width / (widget.size.width * _ratio);
    final scaleY =
        boundaries.height * _area.height / (widget.size.height * _ratio);
    return min(_maximumScale, max(scaleX, scaleY));
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _deactivate();
    final minimumScale = _minimumScale;
    if (minimumScale == null) {
      return;
    }

    final targetScale = _scale.clamp(minimumScale, _maximumScale);
    _scaleTween = Tween<double>(
      begin: _scale,
      end: targetScale,
    );

    _startView = _view;
    _viewTween = RectTween(
      begin: _view,
      end: _getViewInBoundaries(targetScale),
    );

    _settleController.value = 0.0;
    _settleController.animateTo(
      1.0,
      curve: Curves.fastOutSlowIn,
      duration: const Duration(milliseconds: 350),
    );
  }

  void _updateArea({
    required _CropHandleSide cropHandleSide,
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    if (widget.size == Size.zero) {
      return;
    }

    double areaLeft = _area.left + (left ?? 0.0);
    double areaBottom = _area.bottom + (bottom ?? 0.0);
    double areaTop = _area.top + (top ?? 0.0);
    double areaRight = _area.right + (right ?? 0.0);
    double width = areaRight - areaLeft;
    double height = (widget.size.width * _view.width * width) /
        (widget.size.height * _view.height * (widget.aspectRatio ?? 1.0));
    final maxAreaWidth = _maxAreaWidthMap[widget.aspectRatio];
    if ((height >= 1.0 || width >= 1.0) && maxAreaWidth != null) {
      height = 1.0;

      if (cropHandleSide == _CropHandleSide.bottomLeft ||
          cropHandleSide == _CropHandleSide.topLeft) {
        areaLeft = areaRight - maxAreaWidth;
      } else {
        areaRight = areaLeft + maxAreaWidth;
      }
    }

    // ensure minimum rectangle
    if (areaRight - areaLeft < _kCropMinFraction) {
      if (left != null) {
        areaLeft = areaRight - _kCropMinFraction;
      } else {
        areaRight = areaLeft + _kCropMinFraction;
      }
    }

    if (areaBottom - areaTop < _kCropMinFraction) {
      if (top != null) {
        areaTop = areaBottom - _kCropMinFraction;
      } else {
        areaBottom = areaTop + _kCropMinFraction;
      }
    }

    // adjust to aspect ratio if needed
    final aspectRatio = widget.aspectRatio;
    if (aspectRatio != null && aspectRatio > 0.0) {
      if (top != null) {
        areaTop = areaBottom - height;
        if (areaTop < 0.0) {
          areaTop = 0.0;
          areaBottom = height;
        }
      } else {
        areaBottom = areaTop + height;
        if (areaBottom > 1.0) {
          areaTop = 1.0 - height;
          areaBottom = 1.0;
        }
      }
    }

    // ensure to remain within bounds of the view
    if (areaLeft < 0.0) {
      areaLeft = 0.0;
      areaRight = _area.width;
    } else if (areaRight > 1.0) {
      areaLeft = 1.0 - _area.width;
      areaRight = 1.0;
    }

    if (areaTop < 0.0) {
      areaTop = 0.0;
      areaBottom = _area.height;
    } else if (areaBottom > 1.0) {
      areaTop = 1.0 - _area.height;
      areaBottom = 1.0;
    }

    setState(() {
      _area = Rect.fromLTRB(areaLeft, areaTop, areaRight, areaBottom);
    });
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_action == _CropAction.none) {
      if (_handle == _CropHandleSide.none) {
        _action = pointers == 2 ? _CropAction.scaling : _CropAction.moving;
      } else {
        _action = _CropAction.cropping;
      }
    }

    if (_action == _CropAction.cropping) {
      final boundaries = _boundaries;
      if (boundaries == null) {
        return;
      }

      final delta = details.focalPoint - _lastFocalPoint;
      _lastFocalPoint = details.focalPoint;

      final dx = delta.dx / boundaries.width;
      final dy = delta.dy / boundaries.height;

      if (_handle == _CropHandleSide.topLeft) {
        _updateArea(left: dx, top: dy, cropHandleSide: _CropHandleSide.topLeft);
      } else if (_handle == _CropHandleSide.topRight) {
        _updateArea(
            top: dy, right: dx, cropHandleSide: _CropHandleSide.topRight);
      } else if (_handle == _CropHandleSide.bottomLeft) {
        _updateArea(
            left: dx, bottom: dy, cropHandleSide: _CropHandleSide.bottomLeft);
      } else if (_handle == _CropHandleSide.bottomRight) {
        _updateArea(
            right: dx, bottom: dy, cropHandleSide: _CropHandleSide.bottomRight);
      }
    } else if (_action == _CropAction.moving) {
      final delta = details.focalPoint - _lastFocalPoint;
      _lastFocalPoint = details.focalPoint;

      setState(() {
        _view = _view.translate(
          delta.dx / (widget.size.width * _scale * _ratio),
          delta.dy / (widget.size.height * _scale * _ratio),
        );
      });
    } else if (_action == _CropAction.scaling) {
      final boundaries = _boundaries;
      if (boundaries == null) {
        return;
      }

      setState(() {
        _scale = _startScale * details.scale;

        final dx = boundaries.width *
            (1.0 - details.scale) /
            (widget.size.width * _scale * _ratio);
        final dy = boundaries.height *
            (1.0 - details.scale) /
            (widget.size.height * _scale * _ratio);

        _view = Rect.fromLTWH(
          _startView.left + dx / 2,
          _startView.top + dy / 2,
          _startView.width,
          _startView.height,
        );
      });
    }
  }
}

Rect _getRect(Size size, double cropHandleSize) => Rect.fromLTWH(
      cropHandleSize / 2,
      cropHandleSize / 2,
      size.width - cropHandleSize,
      size.height - cropHandleSize,
    );

class _CropPainter extends CustomPainter {
  final Rect view;
  final double ratio;
  final Rect area;
  final double scale;
  final double active;
  final Color backgroundColor;
  final bool disableResize;
  final double cropHandleSize;

  _CropPainter({
    required this.view,
    required this.ratio,
    required this.area,
    required this.scale,
    required this.active,
    required this.backgroundColor,
    required this.disableResize,
    required this.cropHandleSize,
  });

  @override
  bool shouldRepaint(_CropPainter oldDelegate) {
    return oldDelegate.view != view ||
        oldDelegate.ratio != ratio ||
        oldDelegate.area != area ||
        oldDelegate.active != active ||
        oldDelegate.scale != scale;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = _getRect(size, cropHandleSize);

    canvas.save();
    canvas.translate(rect.left, rect.top);

    final paint = Paint()..isAntiAlias = false;

    paint.color = backgroundColor.withOpacity(
        _kCropOverlayActiveOpacity * active +
            backgroundColor.opacity * (1.0 - active));
    final boundaries = Rect.fromLTWH(
      rect.width * area.left,
      rect.height * area.top,
      rect.width * area.width,
      rect.height * area.height,
    );
    canvas.drawRect(Rect.fromLTRB(0.0, 0.0, rect.width, boundaries.top), paint);
    canvas.drawRect(
        Rect.fromLTRB(0.0, boundaries.bottom, rect.width, rect.height), paint);
    canvas.drawRect(
        Rect.fromLTRB(0.0, boundaries.top, boundaries.left, boundaries.bottom),
        paint);
    canvas.drawRect(
        Rect.fromLTRB(
            boundaries.right, boundaries.top, rect.width, boundaries.bottom),
        paint);

    if (boundaries.isEmpty == false) {
      _drawGrid(canvas, boundaries);
      _drawHandles(canvas, boundaries);
    }

    canvas.restore();
  }

  void _drawHandles(Canvas canvas, Rect boundaries) {
    final paint = Paint()
      ..isAntiAlias = true
      ..color = _kCropHandleColor;

    // do not show handles if cannot be resized
    if (disableResize) return;

    canvas.drawOval(
      Rect.fromLTWH(
        boundaries.left - cropHandleSize / 2,
        boundaries.top - cropHandleSize / 2,
        cropHandleSize,
        cropHandleSize,
      ),
      paint,
    );

    canvas.drawOval(
      Rect.fromLTWH(
        boundaries.right - cropHandleSize / 2,
        boundaries.top - cropHandleSize / 2,
        cropHandleSize,
        cropHandleSize,
      ),
      paint,
    );

    canvas.drawOval(
      Rect.fromLTWH(
        boundaries.right - cropHandleSize / 2,
        boundaries.bottom - cropHandleSize / 2,
        cropHandleSize,
        cropHandleSize,
      ),
      paint,
    );

    canvas.drawOval(
      Rect.fromLTWH(
        boundaries.left - cropHandleSize / 2,
        boundaries.bottom - cropHandleSize / 2,
        cropHandleSize,
        cropHandleSize,
      ),
      paint,
    );
  }

  void _drawGrid(Canvas canvas, Rect boundaries) {
    if (active == 0.0) return;

    final paint = Paint()
      ..isAntiAlias = false
      ..color = _kCropGridColor.withOpacity(_kCropGridColor.opacity * active)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path()
      ..moveTo(boundaries.left, boundaries.top)
      ..lineTo(boundaries.right, boundaries.top)
      ..lineTo(boundaries.right, boundaries.bottom)
      ..lineTo(boundaries.left, boundaries.bottom)
      ..lineTo(boundaries.left, boundaries.top);

    for (var column = 1; column < _kCropGridColumnCount; column++) {
      path
        ..moveTo(
            boundaries.left + column * boundaries.width / _kCropGridColumnCount,
            boundaries.top)
        ..lineTo(
            boundaries.left + column * boundaries.width / _kCropGridColumnCount,
            boundaries.bottom);
    }

    for (var row = 1; row < _kCropGridRowCount; row++) {
      path
        ..moveTo(boundaries.left,
            boundaries.top + row * boundaries.height / _kCropGridRowCount)
        ..lineTo(boundaries.right,
            boundaries.top + row * boundaries.height / _kCropGridRowCount);
    }

    canvas.drawPath(path, paint);
  }
}
