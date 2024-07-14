part of insta_assets_crop;

class CropTransform extends StatelessWidget {
  const CropTransform({
    super.key,
    required this.ratio,
    required this.scale,
    required this.view,
    required this.childSize,
    required this.getRect,
    required this.child,
    this.layoutSize,
  });

  final Rect view;
  final double ratio, scale;
  final Size? layoutSize;
  final Size childSize;

  final Rect Function(Size size) getRect;

  final Widget child;

  Widget buildTransform(Size size) {
    final rect = getRect(size);

    final dst = Rect.fromLTWH(
      view.left * childSize.width * scale * ratio,
      view.top * childSize.height * scale * ratio,
      childSize.width * scale * ratio,
      childSize.height * scale * ratio,
    );

    final double translateX = dst.left;
    final double translateY = dst.top;

    return Transform.translate(
      offset: Offset(rect.left, rect.top),
      child: ClipRect(
        // clip grid
        clipper: CropClipper(rect),
        child: Transform.translate(
          offset: Offset(translateX, translateY),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(size: childSize, child: child),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (childSize == Size.zero) return const SizedBox.shrink();

    if (layoutSize != null) return buildTransform(layoutSize!);

    return LayoutBuilder(builder: (_, constraints) {
      final size = constraints.biggest;
      return buildTransform(size);
    });
  }
}

class CropClipper extends CustomClipper<Rect> {
  const CropClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0.0, 0.0, rect.width, rect.height);

  @override
  bool shouldReclip(covariant CropClipper oldClipper) => oldClipper != this;
}
