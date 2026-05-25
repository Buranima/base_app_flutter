import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Permission.camera.request();
  await Permission.microphone.request();
  await Permission.photos.request();
  await Permission.videos.request();
  await Permission.audio.request();
  await Permission.storage.request();
  await Permission.notification.request();

  await FlutterDownloader.initialize(debug: true, ignoreSsl: false);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebAppScreen(),
    );
  }
}

class WebAppScreen extends StatefulWidget {
  const WebAppScreen({super.key});

  @override
  State<WebAppScreen> createState() => _WebAppScreenState();
}

class _WebAppScreenState extends State<WebAppScreen> {
  InAppWebViewController? controller;

  StreamSubscription<List<ConnectivityResult>>? connectivitySubscription;
  Timer? reconnectTimer;

  bool isLoading = true;
  bool hasError = false;
  bool isOffline = false;

  final String webUrl = 'https://webcamtests.com/';
  String lastUrl = 'https://webcamtests.com/';

  @override
  void initState() {
    super.initState();
    setupConnectivityListener();
  }

  Future<void> setupConnectivityListener() async {
    final currentStatus = await Connectivity().checkConnectivity();
    handleConnectivityChanged(currentStatus);

    connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      handleConnectivityChanged,
    );
  }

  void handleConnectivityChanged(List<ConnectivityResult> results) {
    final bool noNetwork = results.contains(ConnectivityResult.none);

    if (!mounted) return;

    if (noNetwork) {
      reconnectTimer?.cancel();

      setState(() {
        isOffline = true;
        hasError = true;
        isLoading = false;
      });

      return;
    }

    if (isOffline || hasError) {
      reconnectTimer?.cancel();

      reconnectTimer = Timer(const Duration(seconds: 2), () async {
        if (!mounted) return;

        setState(() {
          isOffline = false;
          hasError = false;
          isLoading = true;
        });

        final String reloadUrl = lastUrl.startsWith('data:') || lastUrl.isEmpty
            ? webUrl
            : lastUrl;

        await controller?.loadUrl(
          urlRequest: URLRequest(url: WebUri(reloadUrl)),
        );
      });
    }
  }

  Future<void> reloadWeb() async {
    final status = await Connectivity().checkConnectivity();

    if (status.contains(ConnectivityResult.none)) {
      setState(() {
        isOffline = true;
        hasError = true;
        isLoading = false;
      });
      return;
    }

    setState(() {
      isOffline = false;
      hasError = false;
      isLoading = true;
    });

    final String reloadUrl = lastUrl.startsWith('data:') || lastUrl.isEmpty
        ? webUrl
        : lastUrl;

    await controller?.loadUrl(urlRequest: URLRequest(url: WebUri(reloadUrl)));
  }

  Future<void> downloadFile(DownloadStartRequest request) async {
    final String url = request.url.toString();

    Directory downloadDir;

    if (Platform.isAndroid) {
      downloadDir = Directory('/storage/emulated/0/Download');
    } else {
      downloadDir = await getApplicationDocumentsDirectory();
    }

    await FlutterDownloader.enqueue(
      url: url,
      savedDir: downloadDir.path,
      fileName: request.suggestedFilename,
      showNotification: true,
      openFileFromNotification: true,
      saveInPublicStorage: true,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('เริ่มดาวน์โหลดไฟล์แล้ว')));
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: SafeArea(
        top: true,
        bottom: true,
        child: Stack(
          children: [
            Opacity(
              opacity: (!hasError) ? 1.0 : 0.0,

              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(webUrl)),

                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  javaScriptCanOpenWindowsAutomatically: true,

                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,

                  allowFileAccess: true,
                  allowContentAccess: true,
                  allowFileAccessFromFileURLs: true,
                  allowUniversalAccessFromFileURLs: true,

                  databaseEnabled: true,
                  domStorageEnabled: true,
                  cacheEnabled: true,
                  clearCache: false,

                  useOnDownloadStart: true,
                  useShouldOverrideUrlLoading: true,
                  supportMultipleWindows: true,

                  builtInZoomControls: false,
                  displayZoomControls: false,
                  transparentBackground: false,
                ),

                onWebViewCreated: (webController) {
                  controller = webController;
                },

                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  return NavigationActionPolicy.ALLOW;
                },

                onLoadStart: (controller, url) {
                  lastUrl = url?.toString() ?? webUrl;

                  setState(() {
                    isLoading = true;
                  });
                },

                onLoadStop: (controller, url) {
                  lastUrl = url?.toString() ?? webUrl;

                  if (!isOffline) {
                    setState(() {
                      isLoading = false;
                      hasError = false;
                    });
                  }
                },

                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame ?? false) {
                    setState(() {
                      hasError = true;
                      isOffline = true;
                      isLoading = false;
                    });
                  }
                },

                onPermissionRequest: (controller, request) async {
                  return PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },

                onDownloadStartRequest: (controller, request) async {
                  await downloadFile(request);
                },

                onCreateWindow: (controller, createWindowRequest) async {
                  final url = createWindowRequest.request.url;

                  if (url != null) {
                    await controller.loadUrl(urlRequest: URLRequest(url: url));
                  }

                  return true;
                },

                onConsoleMessage: (controller, consoleMessage) {
                  debugPrint('WEB CONSOLE: ${consoleMessage.message}');
                },
              ),
            ),

            if (isLoading && !hasError)
              Container(
                color: Colors.white,
                width: double.infinity,
                height: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/icon/logo.png',
                      width: 120,
                      height: 120,
                    ),
                    const SizedBox(height: 30),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    const Text('กำลังโหลด...', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),

            if (hasError)
              Container(
                color: Colors.white,
                width: double.infinity,
                height: double.infinity,

                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),

                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.wifi_off,
                          size: 72,
                          color: Colors.grey,
                        ),

                        const SizedBox(height: 20),

                        Text(
                          isOffline
                              ? 'ไม่มีอินเทอร์เน็ต'
                              : 'ไม่สามารถโหลดหน้าเว็บได้',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 12),

                        const Text(
                          'กรุณาตรวจสอบการเชื่อมต่อ\nแล้วลองอีกครั้ง',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),

                        const SizedBox(height: 24),

                        ElevatedButton(
                          onPressed: reloadWeb,
                          child: const Text('ลองอีกครั้ง'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
