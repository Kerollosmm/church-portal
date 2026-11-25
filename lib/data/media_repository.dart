// Storage of optional item images (see lib/domain/media.dart).
//
// The project is on the Firebase Spark plan, where Cloud Storage for Firebase
// cannot be provisioned, so images uploaded from a device are stored INLINE in
// Firestore: `media/{mediaId}` = {dataBase64, contentType, w, h, bytes,
// createdAt, createdBy}. Content docs only hold a small `image` map, so lists
// never download image bytes.
//
// Switching to Cloud Storage after a Blaze upgrade: see ADR-017 in
// docs/memory-bank/10-decisions-and-history.md.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/media.dart';

/// A resized + compressed image ready to be stored.
class EncodedImage {
  final Uint8List bytes;
  final String contentType;
  final int w, h;
  const EncodedImage(this.bytes, this.contentType, this.w, this.h);
  int get length => bytes.length;
}

/// Where uploaded images live. The public UI only needs [load] (inline
/// images); url / storage images are rendered straight from their URL.
abstract class MediaRepository {
  /// Value written to `image.source` for uploads.
  String get source;

  /// Inline image bytes, or null when the media doc is missing / unreadable.
  Future<Uint8List?> load(String mediaId);

  /// Stores [img] and returns the `image` map to put on the content doc.
  Future<MediaImage> upload(EncodedImage img, {String alt = ''});

  /// Deletes a stored image (callers treat failures as best effort).
  Future<void> delete(String mediaId);
}

/// Spark-plan implementation: base64 bytes in Firestore `media/{mediaId}`.
class FirestoreMediaRepository implements MediaRepository {
  final FirebaseFirestore db;

  /// Email (or uid) of the signed-in admin, stored as `createdBy`.
  final String Function() actor;
  FirestoreMediaRepository(this.db, this.actor);

  @override
  String get source => MediaSource.inline;

  @override
  Future<Uint8List?> load(String mediaId) async {
    final d = await db.doc('media/$mediaId').get();
    return decodeMediaDoc(d.data());
  }

  @override
  Future<MediaImage> upload(EncodedImage img, {String alt = ''}) async {
    if (validateMediaBytes(img.length) != null) throw const ImageTooLargeException();
    final ref = db.collection('media').doc();
    await ref.set({
      'dataBase64': base64Encode(img.bytes),
      'contentType': img.contentType,
      'w': img.w,
      'h': img.h,
      'bytes': img.length,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': actor(),
    });
    return MediaImage(source: MediaSource.inline, mediaId: ref.id, alt: alt, w: img.w, h: img.h);
  }

  @override
  Future<void> delete(String mediaId) => db.doc('media/$mediaId').delete();
}

/// Bytes of a `media/{id}` document, or null when it is not a valid image.
Uint8List? decodeMediaDoc(Map<String, dynamic>? data) {
  final b64 = data?['dataBase64'];
  final type = data?['contentType'];
  if (b64 is! String || b64.isEmpty || !MediaLimits.contentTypes.contains(type)) return null;
  try {
    return base64Decode(b64);
  } on FormatException {
    return null;
  }
}

/// Read-only Spark-plan media loader for the public UI (`media/{id}`).
/// Refuses mutations so public bootstrap never carries `FirebaseAuth` or risks
/// writing media documents with an empty `createdBy`.
class ReadOnlyMediaRepository implements MediaRepository {
  final FirebaseFirestore db;
  const ReadOnlyMediaRepository(this.db);

  @override
  String get source => MediaSource.inline;

  @override
  Future<Uint8List?> load(String mediaId) async {
    final d = await db.doc('media/$mediaId').get();
    return decodeMediaDoc(d.data());
  }

  @override
  Future<MediaImage> upload(EncodedImage img, {String alt = ''}) =>
      throw UnsupportedError('ReadOnlyMediaRepository cannot upload media.');

  @override
  Future<void> delete(String mediaId) =>
      throw UnsupportedError('ReadOnlyMediaRepository cannot delete media.');
}

/// Public read-only media backend.
MediaRepository createPublicMediaRepository(FirebaseFirestore db) => ReadOnlyMediaRepository(db);

/// Writable admin media backend.
MediaRepository createMediaRepository(FirebaseFirestore db, String Function() actor) =>
    FirestoreMediaRepository(db, actor);

class ImageTooLargeException implements Exception {
  const ImageTooLargeException();
  @override
  String toString() => 'Image is still larger than ${MediaLimits.maxBytes ~/ 1000} KB after compression.';
}

class ImageDecodeException implements Exception {
  const ImageDecodeException();
  @override
  String toString() => 'Not a supported image.';
}

/// In-memory cache of inline image bytes, keyed by media id, so each image is
/// fetched once per session even when several cards / the viewer show it.
class MediaCache {
  final int capacity;
  MediaCache({this.capacity = 60});

  final _entries = <String, Future<Uint8List?>>{};

  /// Shared app-wide instance.
  static final instance = MediaCache();

  Future<Uint8List?> get(String mediaId, Future<Uint8List?> Function(String) loader) {
    final hit = _entries.remove(mediaId);
    if (hit != null) {
      _entries[mediaId] = hit; // most recently used last
      return hit;
    }
    final f = loader(mediaId).catchError((Object _) {
      _entries.remove(mediaId); // retry on the next request
      return null;
    });
    _entries[mediaId] = f;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return f;
  }

  bool contains(String mediaId) => _entries.containsKey(mediaId);
  int get length => _entries.length;
  void evict(String mediaId) => _entries.remove(mediaId);
  void clear() => _entries.clear();
}
