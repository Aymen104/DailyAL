import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/theme/theme.dart';
import 'package:flutter/material.dart';

import 'fadingeffect.dart';

class Background extends StatelessWidget {
  final BuildContext context;
  final String? url;
  final double? height;
  final double? width;
  final bool isNetworkImage;
  final bool showLocalFile;
  final bool forceBg;
  final Color? bgColor;

  /// Alpha (0-255) of the background-colour wash at the TOP of the image; the
  /// bottom is always 255 (fully opaque). The page-wide default of 200 leaves
  /// only ~20% of a wallpaper showing, which is right where text is laid over
  /// it, but a surface whose artwork IS the point - the details hero - passes
  /// a lower value so the key art is actually visible.
  final int fadeStart;

  /// How the image is inscribed in the box. [BoxFit.cover] is right for a
  /// page-wide wallpaper because it always fills, but a wide key-art strip
  /// dropped in a tall box gets scaled up and cropped until nothing legible
  /// survives (a 1900x400 banner in a 1080x1263 box lands at 3.16x with 82%
  /// of its width thrown away). A hero passes [BoxFit.contain] instead so the
  /// whole image stays recognisable.
  final BoxFit fit;

  /// Where the inscribed image sits. Heroes anchor to the top so the art reads
  /// as a band behind the header rather than floating in the middle of it.
  final Alignment alignment;

  const Background({
    required this.context,
    this.url,
    this.height,
    this.showLocalFile = false,
    this.forceBg = false,
    this.bgColor,
    this.isNetworkImage = true,
    this.width = double.infinity,
    this.fadeStart = 200,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });
  @override
  Widget build(BuildContext c) {
    return (user.pref.showBg || forceBg || showLocalFile)
        ? Stack(
            children: [
              Container(
                color: bgColor ?? Theme.of(context).scaffoldBackgroundColor,
              ),
              Container(
                width: width,
                height: showLocalFile
                    ? null
                    : (height ?? MediaQuery.of(context).size.height / 1.9),
                child: CustomPaint(
                  foregroundPainter: FadingEffect(
                    color: bgColor ?? Theme.of(context).scaffoldBackgroundColor,
                    start: fadeStart,
                    end: 255,
                  ),
                  child: showLocalFile
                      ? Image.file(
                          File(url!),
                          fit: fit,
                          alignment: alignment,
                        )
                      : url == null || !isNetworkImage
                          ? Image.asset(
                              url ??
                                  backgroundMap[user.theme.background] ??
                                  "assets/images/fall.jpg",
                              fit: fit,
                              alignment: alignment,
                            )
                          : CachedNetworkImage(
                              imageUrl: url!,
                              fit: fit,
                              alignment: alignment,
                            ),
                ),
              )
            ],
          )
        : Container(
            color: bgColor ?? Theme.of(context).scaffoldBackgroundColor,
          );
  }
}
