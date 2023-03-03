> **Warning**
> This repository is a fork from [image_crop](https://github.com/lykhonis/image_crop) and was modified to work with [insta_assets_picker](https://pub.dev/packages/insta_assets_picker) package.
> This means that this repository will only be updated for the means of this package.
> I don't recommend using it in your project as it probably won't be updated except for the insta_assets_picker requirement.

# Image crop for insta_assets_picker package

[![Pub](https://img.shields.io/pub/v/insta_assets_picker.svg)](https://pub.dev/packages/insta_assets_picker)

Contains all the changes needed in order to work with the `insta_assets_picker` library :

- [#75](https://github.com/lykhonis/image_crop/pull/75): fix sample image on android
- [#77](https://github.com/lykhonis/image_crop/pull/77): disable initial magnification
- [#95](https://github.com/lykhonis/image_crop/pull/95): new `disableResize` parameter
- [#96](https://github.com/lykhonis/image_crop/pull/96): new `backgroundColor` parameter
- [#97](https://github.com/lykhonis/image_crop/pull/97): new `placeholderWidget` & `onLoading` parameters
- [#98](https://github.com/lykhonis/image_crop/pull/98): new `initialParam` parameter to initialize view programmatically
- [f34bfef](https://github.com/LeGoffMael/image_crop/commit/f34bfef5eaf7aef298c475fd1a1874adaa6bcad3): fix issue on aspect ratio change, no PR made because it might not be the best fix
- [8fb0bc0](https://github.com/LeGoffMael/image_crop/commit/8fb0bc04696f95055be5f3dc32cbb8714b278a9c): fix issue with GIF, no PR for this yet since it is specific to GIF extended image provider

## Note

If the [original package](https://github.com/lykhonis/image_crop) happen to be updated, this could be deleted.