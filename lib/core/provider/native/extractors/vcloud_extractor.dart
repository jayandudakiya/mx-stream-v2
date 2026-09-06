import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import '../internal/native_models.dart';
import '../provider_config.dart';

/// Resolves VegaMovies/RogMovies download-page links (V-Cloud, HubCloud,
/// GDFlix, ...) down to final playable stream links.
///
/// Ported verbatim from MXStream's
/// `functions/fetchers/providers/VegaMovies/extractors/vcloud_extractor.dart`.
class VCloudExtractor {
  static String getBaseUrl(String url) {
    try {
      final parsed = Uri.parse(url);
      return '${parsed.scheme}://${parsed.host}';
    } catch (_) {
      return url;
    }
  }

  static String _decodeBase64Clean(String input) {
    String clean = input.trim().replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '');
    while (clean.length % 4 != 0) {
      clean += '=';
    }
    return utf8.decode(base64.decode(clean));
  }

  static Future<String?> _resolveRedirectUrl(String startUrl, {int maxRedirects = 7}) async {
    String currentUrl = startUrl;
    int loopCount = 0;
    final client = http.Client();

    try {
      while (loopCount < maxRedirects) {
        final request = http.Request('HEAD', Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers['User-Agent'] = ProviderConfig.defaultUserAgent;
        final response = await client.send(request).timeout(const Duration(seconds: 10));

        final location = response.headers['location'];
        if (location == null || location.isEmpty) break;

        currentUrl = location.startsWith('http')
            ? location
            : Uri.parse(currentUrl).resolve(location).toString();
        loopCount++;
      }
    } catch (_) {
    } finally {
      client.close();
    }
    return currentUrl;
  }

  static Future<List<StreamLink>> extractVCloudStream(String url) async {
    final List<StreamLink> streams = [];

    try {
      String baseUrl = getBaseUrl(url);
      final sourceKey = url.contains('hubcloud') ? 'hubcloud' : 'vcloud';

      // Resolve dynamic base domain
      final latestBaseUrl = await ProviderConfig.resolveBaseUrl(sourceKey);
      String targetUrl = url;
      if (latestBaseUrl.isNotEmpty && baseUrl != latestBaseUrl) {
        targetUrl = url.replaceAll(baseUrl, latestBaseUrl);
        baseUrl = latestBaseUrl;
      }

      // Fetch Step 1 Document
      final res1 = await http.get(
        Uri.parse(targetUrl),
        headers: {
          "User-Agent": ProviderConfig.defaultUserAgent,
          "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
      ).timeout(const Duration(seconds: 20));

      if (res1.statusCode != 200) return streams;
      final doc1 = parser.parse(res1.body);

      String? secondaryLink;
      if (targetUrl.contains('/video/')) {
        final vdLink = doc1.querySelector('div.vd > center > a');
        secondaryLink = vdLink?.attributes['href'];
      } else {
        final scripts = doc1.querySelectorAll('script');
        for (var script in scripts) {
          final text = script.text;

          // Double atob pattern: var url = atob(atob('...'))
          final matchAtob = RegExp(
            r'''atob\s*\(\s*atob\s*\(\s*['"]([^'"]+)['"]\s*\)\s*\)''',
            caseSensitive: false,
          ).firstMatch(text);

          if (matchAtob != null && matchAtob.group(1) != null) {
            try {
              final raw = matchAtob.group(1)!;
              final d1 = _decodeBase64Clean(raw);
              final d2 = _decodeBase64Clean(d1);
              if (d2.startsWith('http') || d2.startsWith('/')) {
                secondaryLink = d2;
                break;
              }
            } catch (_) {}
          }

          // Single direct url pattern: var url = 'https://...'
          final matchVar = RegExp(
            r'''var\s+url\s*=\s*['"](https?://[^'"]+)['"]''',
            caseSensitive: false,
          ).firstMatch(text);

          if (matchVar != null && matchVar.group(1) != null) {
            secondaryLink = matchVar.group(1);
            break;
          }
        }
      }

      if (secondaryLink == null || secondaryLink.isEmpty) return streams;

      if (!secondaryLink.startsWith('http')) {
        secondaryLink = '$baseUrl$secondaryLink';
      }

      // Fetch Step 2 Document (Button cards) with fresh connection
      final res2 = await http.get(
        Uri.parse(secondaryLink),
        headers: {
          "User-Agent": ProviderConfig.defaultUserAgent,
          "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
      ).timeout(const Duration(seconds: 20));

      if (res2.statusCode != 200) return streams;
      final doc2 = parser.parse(res2.body);

      final headerText = doc2.querySelector('div.card-header')?.text.trim() ?? '';
      final sizeText = doc2.querySelector('i#size')?.text.trim() ?? '';
      final qualityLabel = headerText.isNotEmpty
          ? (sizeText.isNotEmpty ? '$headerText [$sizeText]' : headerText)
          : (sizeText.isNotEmpty ? '[$sizeText]' : 'HD');

      final buttons = doc2.querySelectorAll('h2 a.btn');
      final asyncTasks = <Future<void>>[];

      for (var btn in buttons) {
        final link = btn.attributes['href'] ?? '';
        final text = btn.text.trim();

        if (link.isEmpty) continue;

        if (text.contains('FSL Server')) {
          streams.add(StreamLink(
            name: 'V-Cloud [FSL Server]',
            streamUrl: link,
            quality: qualityLabel,
            isHls: link.contains('.m3u8'),
          ));
        } else if (text.contains('FSLv2')) {
          streams.add(StreamLink(
            name: 'V-Cloud [FSLv2 Server]',
            streamUrl: link,
            quality: qualityLabel,
            isHls: link.contains('.m3u8'),
          ));
        } else if (text.contains('Mega Server')) {
          streams.add(StreamLink(
            name: 'V-Cloud [Mega Server]',
            streamUrl: link,
            quality: qualityLabel,
            isHls: false,
          ));
        } else if (text.contains('Download File')) {
          streams.add(StreamLink(
            name: 'V-Cloud [Direct Download]',
            streamUrl: link,
            quality: qualityLabel,
            isHls: link.contains('.m3u8'),
          ));
        } else if (link.contains('pixeldra')) {
          final pxlMatch = RegExp(r'''var\s+pxl\s*=\s*['"]([^'"]+)['"]''').firstMatch(res2.body);
          final pixelLink = pxlMatch?.group(1);
          if (pixelLink != null && pixelLink.isNotEmpty) {
            final pxlBase = pixelLink.startsWith('http')
                ? getBaseUrl(pixelLink)
                : 'https://pixeldrain.dev';
            final fileId = pixelLink.split('/').last.split('?').first;
            final finalUrl = pixelLink.toLowerCase().contains('download')
                ? pixelLink
                : '$pxlBase/api/file/$fileId?download';
            streams.add(StreamLink(
              name: 'V-Cloud [Pixeldrain]',
              streamUrl: finalUrl,
              quality: qualityLabel,
              isHls: false,
            ));
          }
        } else if (text.contains('BuzzServer') || text.contains('Buzz Server')) {
          asyncTasks.add(() async {
            final client = http.Client();
            try {
              // Must not follow redirects: the hx-redirect header only exists
              // on the intermediate response and is lost once it is followed.
              final buzzRequest = http.Request('GET', Uri.parse('$link/download'))
                ..followRedirects = false
                ..headers['User-Agent'] = ProviderConfig.defaultUserAgent
                ..headers['Referer'] = link;
              final buzzReq = await client
                  .send(buzzRequest)
                  .timeout(const Duration(seconds: 15));
              final hxRedirect = buzzReq.headers['hx-redirect'];
              if (hxRedirect != null && hxRedirect.isNotEmpty) {
                final buzzBase = getBaseUrl(link);
                final finalBuzzUrl = hxRedirect.startsWith('http') ? hxRedirect : '$buzzBase$hxRedirect';
                streams.add(StreamLink(
                  name: 'V-Cloud [BuzzServer]',
                  streamUrl: finalBuzzUrl,
                  quality: qualityLabel,
                  isHls: finalBuzzUrl.contains('.m3u8'),
                ));
              }
            } catch (_) {
            } finally {
              client.close();
            }
          }());
        } else if (text.contains('Gofile')) {
          streams.add(StreamLink(
            name: 'V-Cloud [Gofile]',
            streamUrl: link,
            quality: qualityLabel,
            isHls: false,
          ));
        } else if (text.contains('Server : 10Gbps') || text.contains('10Gbps Server')) {
          if (link.contains('link=')) {
            final redirectUrl = link.split('link=')[1];
            streams.add(StreamLink(
              name: 'V-Cloud [10Gbps Server]',
              streamUrl: redirectUrl,
              quality: qualityLabel,
              isHls: redirectUrl.contains('.m3u8'),
            ));
          } else {
            asyncTasks.add(() async {
              try {
                String? redirectUrl = await _resolveRedirectUrl(link);
                if (redirectUrl != null && redirectUrl.isNotEmpty) {
                  if (redirectUrl.contains('link=')) {
                    redirectUrl = redirectUrl.split('link=')[1];
                  }
                  streams.add(StreamLink(
                    name: 'V-Cloud [10Gbps Server]',
                    streamUrl: redirectUrl,
                    quality: qualityLabel,
                    isHls: redirectUrl.contains('.m3u8'),
                  ));
                }
              } catch (_) {}
            }());
          }
        }
      }

      if (asyncTasks.isNotEmpty) {
        await Future.wait(asyncTasks);
      }
    } catch (_) {}

    return streams;
  }
}
