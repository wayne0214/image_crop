import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insta_assets_crop/insta_assets_crop.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:video_player/video_player.dart';

enum PickedFileType { image, video }

class PickedFile {
  const PickedFile({
    required this.file,
    required this.size,
    required this.type,
  });

  static Future<PickedFile> create(XFile xfile) async {
    final String? mimeType = lookupMimeType(xfile.path);
    final bool isImage = mimeType?.startsWith('image/') ?? false;
    final bool isVideo = mimeType?.startsWith('video/') ?? false;

    Size? size;

    if (isImage) {
      final decodedImage = await decodeImageFromList(await xfile.readAsBytes());
      final height = decodedImage.height;
      final width = decodedImage.width;
      size = Size(width.toDouble(), height.toDouble());
    }

    return PickedFile(
      file: File(xfile.path),
      size: size,
      type: isImage
          ? PickedFileType.image
          : isVideo
              ? PickedFileType.video
              : null,
    );
  }

  PickedFile copyWithSize(Size newSize) =>
      PickedFile(file: file, size: newSize, type: type);

  Future<FileSystemEntity> delete() => file.delete();

  final File file;
  final Size? size;
  final PickedFileType? type;

  bool get isVideo => type == PickedFileType.video;
}

void main() {
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(MaterialApp(title: 'Insta Assets Crop Example', home: MyApp()));
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final cropKey = GlobalKey<CropState>();
  PickedFile? _pickedFile;
  VideoPlayerController? videoController;

  bool get isVideo => _pickedFile?.isVideo ?? false;
  bool get isPlaying => videoController?.value.isPlaying ?? false;

  @override
  void dispose() {
    super.dispose();
    _pickedFile?.delete();
    videoController?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SafeArea(
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20.0),
          child: _pickedFile == null
              ? Center(child: _buildOpenFile())
              : _buildCroppingFile(),
        ),
      ),
    );
  }

  Widget _buildCroppingFile() {
    return Column(
      children: <Widget>[
        if (_pickedFile != null)
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!isVideo) return;

                if (videoController == null) return;
                if (isPlaying) {
                  videoController?.pause();
                  return;
                }
                if (videoController?.value.duration ==
                    videoController?.value.position) {
                  videoController
                    ?..seekTo(Duration.zero)
                    ..play();
                  return;
                }
                videoController?.play();
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_pickedFile?.size != null)
                    Crop(
                      child: isVideo
                          ? VideoPlayer(videoController!)
                          : Image.file(_pickedFile!.file),
                      size: _pickedFile!.size!,
                      key: cropKey,
                      disableResize: true,
                      aspectRatio: 1,
                    ),
                  if (isVideo && videoController != null)
                    AnimatedBuilder(
                      animation: videoController!,
                      builder: (_, __) => AnimatedOpacity(
                        opacity: isPlaying ? 0 : 1,
                        duration: kThemeAnimationDuration,
                        child: CircleAvatar(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.black.withOpacity(0.7),
                          radius: 24,
                          child: const Icon(Icons.play_arrow_rounded, size: 40),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.only(top: 20.0),
          alignment: AlignmentDirectional.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              TextButton(
                child: Text('Crop Image'),
                style: TextButton.styleFrom(
                  disabledForegroundColor: Colors.white30,
                  foregroundColor: Colors.white,
                  textStyle: Theme.of(context).textTheme.labelLarge,
                ),
                onPressed: isVideo ? null : _cropImage,
              ),
              _buildOpenFile(),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildOpenFile() {
    return TextButton(
      child: Text(
        'Open File',
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Colors.white),
      ),
      onPressed: () => _openFile(),
    );
  }

  Future<void> _openFile() async {
    final xfile = await ImagePicker().pickMedia();

    if (xfile == null) return;

    final file = await PickedFile.create(xfile);

    if (file.type == null) {
      throw 'Error file type not supported (only image or video)';
    }

    _pickedFile?.delete();

    if (file.isVideo) {
      videoController?.dispose();
      videoController = null;
      videoController = VideoPlayerController.file(file.file);

      await videoController?.initialize();
      videoController?.setLooping(true);
      videoController?.play();

      final size = videoController?.value.size;
      if (size == null) {
        throw 'Error cannot determine video size';
      }

      setState(() {
        _pickedFile = file.copyWithSize(size);
      });
    } else {
      setState(() {
        _pickedFile = file;
      });
    }
  }

  Future<void> _cropImage() async {
    final scale = cropKey.currentState?.scale;
    final area = cropKey.currentState?.area;
    if (area == null) {
      // cannot crop, widget is not setup
      return;
    }

    if (_pickedFile == null) {
      throw 'error file is null';
    }

    // scale up to use maximum possible number of pixels
    // this will sample image in higher resolution to make cropped image larger
    final sample = await InstaAssetsCrop.sampleImage(
      file: _pickedFile!.file,
      preferredSize: (2000 / (scale ?? 1.0)).round(),
    );

    final file = await InstaAssetsCrop.cropImage(
      file: sample,
      area: area,
    );

    sample.delete();
    debugPrint('$file');

    showDialog(
      context: context,
      builder: (context) => Image.file(file),
    );
  }
}
