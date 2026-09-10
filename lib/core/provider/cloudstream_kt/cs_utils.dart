/// The free functions Kotlin CloudStream providers pull in from
/// `com.lagradost.cloudstream3.*` — URL fixing, base64, the p.a.c.k.e.d
/// unpacker, AES, quality parsing.
///
/// Everything here is pure and synchronous, so it is also where the porting
/// notes live for anything whose Kotlin form does not translate literally.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/api.dart';

import 'cs_types.dart';

/// `getBaseUrl(url)` — scheme + host, or the input when it will not parse.
String getBaseUrl(String url) {
  try {
    final u = Uri.parse(url);
    if (u.scheme.isEmpty || u.host.isEmpty) return url;
    return '${u.scheme}://${u.host}';
  } catch (_) {
    return url;
  }
}

/// `fixUrl(url, domain)` — absolutises a site-relative href.
String fixUrl(String url, String domain) {
  if (url.isEmpty) return '';
  if (url.startsWith('http')) return url;
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('/')) return '${domain.replaceAll(RegExp(r'/$'), '')}$url';
  return '${domain.replaceAll(RegExp(r'/$'), '')}/$url';
}

/// `fixUrlNull` — null in, null out; empty in, null out.
String? fixUrlNull(String? url, String domain) {
  if (url == null || url.trim().isEmpty) return null;
  final fixed = fixUrl(url.trim(), domain);
  return fixed.isEmpty ? null : fixed;
}

/// `base64Decode` — tolerant of the unpadded and whitespace-laden strings
/// these sites emit, which Dart's own decoder rejects outright.
String csBase64Decode(String input) {
  try {
    var clean = input.trim().replaceAll(RegExp(r'\s'), '');
    clean = clean.replaceAll('-', '+').replaceAll('_', '/');
    while (clean.length % 4 != 0) {
      clean += '=';
    }
    return utf8.decode(base64.decode(clean), allowMalformed: true);
  } catch (_) {
    return '';
  }
}

/// Bytes form of [csBase64Decode], for keys rather than text.
Uint8List csBase64DecodeBytes(String input) {
  try {
    var clean = input.trim().replaceAll(RegExp(r'\s'), '');
    clean = clean.replaceAll('-', '+').replaceAll('_', '/');
    while (clean.length % 4 != 0) {
      clean += '=';
    }
    return base64.decode(clean);
  } catch (_) {
    return Uint8List(0);
  }
}

String csBase64Encode(String input) => base64.encode(utf8.encode(input));

/// ROT13 — HDHub4u's `pen()`.
String rot13(String value) => value.split('').map((c) {
      final u = c.codeUnitAt(0);
      if (u >= 65 && u <= 90) return String.fromCharCode((u - 65 + 13) % 26 + 65);
      if (u >= 97 && u <= 122) return String.fromCharCode((u - 97 + 13) % 26 + 97);
      return c;
    }).join();

/// AES/CBC/PKCS5 decrypt of a hex-encoded payload — the VidStack player's
/// `/api/v1/video` response. Returns null when the key/IV pair is wrong, which
/// is the caller's signal to try the next IV.
String? aesDecryptHex(String hexInput, String key, String iv) {
  try {
    final data = _hexToBytes(hexInput);
    if (data.isEmpty || data.length % 16 != 0) return null;
    final cipher = CBCBlockCipher(AESEngine())
      ..init(
        false,
        ParametersWithIV(KeyParameter(Uint8List.fromList(utf8.encode(key))),
            Uint8List.fromList(utf8.encode(iv))),
      );
    final out = Uint8List(data.length);
    for (var offset = 0; offset < data.length; offset += 16) {
      cipher.processBlock(data, offset, out, offset);
    }
    // Strip PKCS#5/7 padding; a bogus pad byte means the wrong key or IV.
    final pad = out.isEmpty ? 0 : out.last;
    if (pad <= 0 || pad > 16 || pad > out.length) return null;
    return utf8.decode(out.sublist(0, out.length - pad), allowMalformed: true);
  } catch (_) {
    return null;
  }
}

Uint8List _hexToBytes(String hex) {
  final clean = hex.trim();
  if (clean.length % 2 != 0) return Uint8List(0);
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final b = int.tryParse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    if (b == null) return Uint8List(0);
    out[i] = b;
  }
  return out;
}

const String _packAlphabet =
    '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// Unpacks Dean Edwards' `eval(function(p,a,c,k,e,d){...})` — how every
/// StreamWish/VidHide/Filesim-family player hides its `sources:[{file:...}]`.
/// Returns null when [source] holds no packed block.
String? unpackJs(String source) {
  final start = source.indexOf('eval(function(p,a,c,k,e,d)');
  if (start < 0) return null;
  final body = source.substring(start);
  final m = RegExp(
    r"\}\s*\(\s*'(.*?)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'(.*?)'\s*\.split\('\|'\)",
    dotAll: true,
  ).firstMatch(body);
  if (m == null) return null;

  final payload = m.group(1)!.replaceAll(r"\'", "'").replaceAll(r'\\', r'\');
  final radix = int.tryParse(m.group(2)!) ?? 36;
  final count = int.tryParse(m.group(3)!) ?? 0;
  final words = m.group(4)!.split('|');

  String toBase(int n) {
    if (n == 0) return '0';
    final buf = StringBuffer();
    var v = n;
    while (v > 0) {
      buf.write(_packAlphabet[v % radix]);
      v ~/= radix;
    }
    return buf.toString().split('').reversed.join();
  }

  final table = <String, String>{};
  for (var i = 0; i < count; i++) {
    final key = toBase(i);
    final word = i < words.length ? words[i] : '';
    table[key] = word.isEmpty ? key : word;
  }
  return payload.replaceAllMapped(
    RegExp(r'\b\w+\b'),
    (match) => table[match.group(0)] ?? match.group(0)!,
  );
}

/// `getQualityFromString` — the ladder value a quality word implies.
int getQualityFromString(String? text) {
  final s = (text ?? '').toLowerCase();
  if (s.contains('2160') || s.contains('4k') || s.contains('uhd')) return Qualities.p2160;
  if (s.contains('1440') || s.contains('qhd')) return Qualities.p1440;
  if (s.contains('1080') || s.contains('fullhd')) return Qualities.p1080;
  if (s.contains('720')) return Qualities.p720;
  if (s.contains('480')) return Qualities.p480;
  if (s.contains('360')) return Qualities.p360;
  return Qualities.unknown;
}

/// `getIndexQuality` — the first `<digits>p` in a release string.
int getIndexQuality(String? text, {int fallback = Qualities.unknown}) {
  final m = RegExp(r'(\d{3,4})[pP]').firstMatch(text ?? '');
  final v = m == null ? null : int.tryParse(m.group(1)!);
  return v ?? fallback;
}

/// `getSearchQuality` — the poster badge a release string implies.
SearchQuality? getSearchQuality(String? check) {
  final s = (check ?? '').toLowerCase();
  if (s.isEmpty) return null;
  if (RegExp(r'\b(4k|ds4k|uhd|2160p)\b').hasMatch(s)) return SearchQuality.uhd;
  if (RegExp(r'\b(hdts|hdcam|hdtc)\b').hasMatch(s)) return SearchQuality.hdCam;
  if (RegExp(r'\b(camrip|cam[- ]?rip)\b').hasMatch(s)) return SearchQuality.camRip;
  if (RegExp(r'\bcam\b').hasMatch(s)) return SearchQuality.cam;
  if (RegExp(r'\b(web[- ]?dl|webrip|webdl)\b').hasMatch(s)) return SearchQuality.webRip;
  if (RegExp(r'\b(bluray|bdrip|blu[- ]?ray|remux)\b').hasMatch(s)) return SearchQuality.blueRay;
  if (RegExp(r'\b(1440p|qhd)\b').hasMatch(s)) return SearchQuality.blueRay;
  if (RegExp(r'\b(1080p|fullhd)\b').hasMatch(s)) return SearchQuality.hd;
  if (RegExp(r'\b720p\b').hasMatch(s)) return SearchQuality.sd;
  if (RegExp(r'\b(hdrip|hdtv)\b').hasMatch(s)) return SearchQuality.hd;
  if (RegExp(r'\bdvd\b').hasMatch(s)) return SearchQuality.dvd;
  return null;
}

/// `cleanTitle(filename)` — trims a scene filename down to the informative
/// middle (`…1080p.WEB-DL.x264.ESub…`) for a source-row label.
String cleanFileName(String title) {
  final parts = title.split(RegExp(r'[.\-_]'));
  const quality = ['WEBRip', 'WEB-DL', 'WEB', 'BluRay', 'HDRip', 'DVDRip', 'HDTV',
      'CAM', 'TS', 'R5', 'DVDScr', 'BRRip', 'BDRip', 'DVD', 'PDTV', 'HD'];
  const audio = ['AAC', 'AC3', 'DTS', 'MP3', 'FLAC', 'DD5', 'EAC3', 'Atmos', 'DDP'];
  const subs = ['ESub', 'ESubs', 'Subs', 'MultiSub', 'NoSub', 'EnglishSub', 'HindiSub'];
  const codec = ['x264', 'x265', 'H264', 'HEVC', 'AVC'];

  bool has(String part, List<String> tags) =>
      tags.any((t) => part.toLowerCase().contains(t.toLowerCase()));

  final start = parts.indexWhere((p) => has(p, quality));
  final end = parts.lastIndexWhere(
      (p) => has(p, subs) || has(p, audio) || has(p, codec));

  if (start != -1 && end != -1 && end >= start) {
    return parts.sublist(start, end + 1).join('.');
  }
  if (start != -1) return parts.sublist(start).join('.');
  return parts.length <= 3 ? parts.join('.') : parts.sublist(parts.length - 3).join('.');
}

/// Kotlin's `amap` — map in parallel. [concurrency] caps in-flight requests so
/// a page with forty mirror links does not open forty sockets at once.
Future<List<R>> amap<T, R>(
  Iterable<T> items,
  Future<R> Function(T item) body, {
  int concurrency = 8,
}) async {
  final list = items.toList();
  final results = List<R?>.filled(list.length, null);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= list.length) return;
      results[i] = await body(list[i]);
    }
  }

  final workers = List.generate(
    list.length < concurrency ? list.length : concurrency,
    (_) => worker(),
  );
  await Future.wait(workers);
  return results.cast<R>();
}

/// [amap] that swallows per-item failures — one dead mirror must never sink
/// the rest of the batch. Failed items are dropped from the result.
Future<List<R>> amapSafe<T, R>(
  Iterable<T> items,
  Future<List<R>> Function(T item) body, {
  int concurrency = 8,
}) async {
  final batches = await amap<T, List<R>>(
    items,
    (item) async {
      try {
        return await body(item);
      } catch (_) {
        return <R>[];
      }
    },
    concurrency: concurrency,
  );
  return batches.expand((b) => b).toList();
}
