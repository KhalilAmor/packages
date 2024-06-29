import 'dart:async';
import 'dart:html';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'src/shims/dart_ui.dart' as ui;
import 'src/video_player.dart';

/// The web implementation of [VideoPlayerPlatform].
///
/// This class implements the `package:video_player` functionality for the web.
class VideoPlayerPlugin extends VideoPlayerPlatform {
  /// Registers this class as the default instance of [VideoPlayerPlatform].
  static void registerWith(Registrar registrar) {
    VideoPlayerPlatform.instance = VideoPlayerPlugin();
  }

  // Map of textureId -> VideoPlayer instances
  final Map<int, VideoPlayer> _videoPlayers = <int, VideoPlayer>{};
  // Map of textureId -> list of proxy VideoElements
  final Map<int, List<VideoElement>> _proxyVideoElements =
      <int, List<VideoElement>>{};

  // Simulate the native "textureId".
  int _textureCounter = 1;

  @override
  Future<void> init() async {
    return _disposeAllPlayers();
  }

  @override
  Future<void> dispose(int textureId) async {
    _player(textureId).dispose();
    _videoPlayers.remove(textureId);
    _proxyVideoElements.remove(textureId);
    return;
  }

  void _disposeAllPlayers() {
    for (final VideoPlayer videoPlayer in _videoPlayers.values) {
      videoPlayer.dispose();
    }
    _videoPlayers.clear();
    _proxyVideoElements.clear();
  }

  @override
  Future<int> create(DataSource dataSource) async {
    final int textureId = _textureCounter++;

    late String uri;
    switch (dataSource.sourceType) {
      case DataSourceType.network:
        uri = dataSource.uri ?? '';
        break;
      case DataSourceType.asset:
        String assetUrl = dataSource.asset!;
        if (dataSource.package != null && dataSource.package!.isNotEmpty) {
          assetUrl = 'packages/${dataSource.package}/$assetUrl';
        }
        assetUrl = ui.webOnlyAssetManager.getAssetUrl(assetUrl);
        uri = assetUrl;
        break;
      case DataSourceType.file:
        return Future<int>.error(UnimplementedError(
            'web implementation of video_player cannot play local files'));
      case DataSourceType.contentUri:
        return Future<int>.error(UnimplementedError(
            'web implementation of video_player cannot play content uri'));
    }

    final VideoElement videoElement = VideoElement()
      ..id = 'videoElement-$textureId'
      ..src = uri
      ..style.border = 'none'
      ..style.height = '100%'
      ..style.width = '100%'
      ..autoplay = false;

    final VideoPlayer player = VideoPlayer(videoElement: videoElement)
      ..initialize();

    _videoPlayers[textureId] = player;
    _proxyVideoElements[textureId] = [];

    // Listen to the main video element for synchronization
    videoElement.onTimeUpdate.listen((event) {
      _syncProxyVideos(textureId);
    });

    // Register the main video element
    ui.platformViewRegistry.registerViewFactory(
      'videoPlayer-$textureId',
      (int viewId) {
        if (viewId == 0) {
          return videoElement;
        }

        // Creating the proxy video element
        final VideoElement proxyVideoElement = VideoElement()
          ..src = videoElement.src
          ..id = 'videoElement-$textureId-proxy-$viewId'
          ..style.border = videoElement.style.border
          ..style.height = videoElement.style.height
          ..style.width = videoElement.style.width
          ..autoplay = false
          ..controls = videoElement.controls
          ..loop = videoElement.loop
          ..muted = true // Mute the proxy element
          ..volume = 0.0 // Ensure volume is set to 0
          ..playbackRate = videoElement.playbackRate
          ..currentTime = videoElement.currentTime
          ..setAttribute('playsinline', 'true');

        // Add the proxy element to the list
        _proxyVideoElements[textureId]!.add(proxyVideoElement);

        // Synchronize the state of the proxy element
        if (videoElement.paused) {
          proxyVideoElement.pause();
        } else {
          proxyVideoElement.play().catchError((Object e) {});
        }

        player.addProxyVideoElement(proxyVideoElement);
        return proxyVideoElement;
      },
    );

    return textureId;
  }

  void _syncProxyVideos(int textureId) {
    final VideoPlayer player = _player(textureId);
    final VideoElement mainVideoElement = player.videoElement;
    final List<VideoElement> proxies = _proxyVideoElements[textureId] ?? [];

    for (final proxy in proxies) {
      if ((proxy.currentTime - mainVideoElement.currentTime).abs() > 0.1) {
        proxy.currentTime = mainVideoElement.currentTime;
      }
      if (mainVideoElement.paused && !proxy.paused) {
        proxy.pause();
      } else if (!mainVideoElement.paused && proxy.paused) {
        proxy.play().catchError((Object e) {});
      }
    }
  }

  @override
  Future<void> setLooping(int textureId, bool looping) async {
    return _player(textureId).setLooping(looping);
  }

  @override
  Future<void> play(int textureId) async {
    return _player(textureId).play();
  }

  @override
  Future<void> pause(int textureId) async {
    return _player(textureId).pause();
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    return _player(textureId).setVolume(volume);
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {
    return _player(textureId).setPlaybackSpeed(speed);
  }

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    return _player(textureId).seekTo(position);
  }

  @override
  Future<Duration> getPosition(int textureId) async {
    return _player(textureId).getPosition();
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return _player(textureId).events;
  }

  // Retrieves a [VideoPlayer] by its internal `id`.
  // It must have been created earlier from the [create] method.
  VideoPlayer _player(int id) {
    return _videoPlayers[id]!;
  }

  @override
  Widget buildView(int textureId) {
    return HtmlElementView(viewType: 'videoPlayer-$textureId');
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) => Future<void>.value();
}
