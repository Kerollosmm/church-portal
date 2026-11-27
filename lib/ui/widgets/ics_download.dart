import 'package:flutter/foundation.dart' show visibleForTesting;

import 'ics_download_stub.dart' if (dart.library.js_interop) 'ics_download_web.dart' as impl;

/// Test hook invoked when [downloadIcsFile] is called (off-web tests run with
/// the no-op stub).
@visibleForTesting
void Function(String content, String filename)? debugOnIcsDownload;

/// Downloads an RFC 5545 `.ics` file in the browser via a Blob + `<a download>`.
void downloadIcsFile(String content, {String filename = 'reminder.ics'}) {
  debugOnIcsDownload?.call(content, filename);
  impl.downloadIcsFile(content, filename);
}
