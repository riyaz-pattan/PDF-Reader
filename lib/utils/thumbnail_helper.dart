import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ThumbnailHelper {
  static Future<File> getThumbnailFile(String pdfPath) async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/pdf_thumbnails');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    
    // Hash the path to create a safe filename
    final hashedPath = base64Url.encode(utf8.encode(pdfPath));
    return File('${cacheDir.path}/$hashedPath.png');
  }
}
