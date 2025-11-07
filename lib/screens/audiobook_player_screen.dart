import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:audio_session/audio_session.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/plex_metadata.dart';
import '../providers/plex_client_provider.dart';
import '../utils/provider_extensions.dart';
import '../utils/app_logger.dart';
import '../services/settings_service.dart';
import '../services/media_service_manager.dart';
import '../services/sleep_timer_service.dart';
import '../utils/orientation_helper.dart';
import '../widgets/video_controls/sheets/playback_speed_sheet.dart';
import '../widgets/video_controls/sheets/chapter_sheet.dart';
import '../widgets/video_controls/sheets/sleep_timer_sheet.dart';

class AudiobookPlayerScreen extends StatefulWidget {
  final PlexMetadata metadata;
  final List<PlexMetadata>? playlist;
  final int initialIndex;

  const AudiobookPlayerScreen({
    super.key,
    required this.metadata,
    this.playlist,
    this.initialIndex = 0,
  });

  @override
  State<AudiobookPlayerScreen> createState() => _AudiobookPlayerScreenState();
}

class _AudiobookPlayerScreenState extends State<AudiobookPlayerScreen> {
  Player? player;
  bool _isPlayerInitialized = false;
  Timer? _progressTimer;
  PlexClientProvider? _cachedClientProvider;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  // Current playback state
  PlexMetadata? _currentMetadata;
  int _currentIndex = 0;
  List<PlexMetadata> _currentPlaylist = [];

  // Playback state streams
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<double>? _rateSubscription;

  // Current playback values
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();

    // Initialize playlist
    if (widget.playlist != null && widget.playlist!.isNotEmpty) {
      _currentPlaylist = widget.playlist!;
      _currentIndex = widget.initialIndex.clamp(0, _currentPlaylist.length - 1);
      _currentMetadata = _currentPlaylist[_currentIndex];
    } else {
      _currentPlaylist = [widget.metadata];
      _currentIndex = 0;
      _currentMetadata = widget.metadata;
    }

    appLogger.d('AudiobookPlayerScreen initialized for: ${_currentMetadata?.title}');

    // Initialize player asynchronously
    _initializePlayer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Cache provider reference for safe access in dispose()
    try {
      _cachedClientProvider = context.plexClient;
    } catch (e) {
      appLogger.w('Failed to cache PlexClientProvider', error: e);
      _cachedClientProvider = null;
    }
  }

  Future<void> _initializePlayer() async {
    try {
      // Load settings
      final settingsService = await SettingsService.getInstance();
      final bufferSizeMB = settingsService.getBufferSize();
      final bufferSizeBytes = bufferSizeMB * 1024 * 1024;
      final debugLoggingEnabled = settingsService.getEnableDebugLogging();

      // Create player with configuration
      player = Player(
        configuration: PlayerConfiguration(
          bufferSize: bufferSizeBytes,
          logLevel: debugLoggingEnabled ? MPVLogLevel.debug : MPVLogLevel.error,
        ),
      );

      // Initialize audio session for audiobook playback
      await _initializeAudioSession();

      // Update media service manager with new player
      await _updateMediaService();

      // Notify that player is ready
      if (mounted) {
        setState(() {
          _isPlayerInitialized = true;
        });
      }

      // Start playback
      await _startPlayback();

      // Listen to playback state changes
      _positionSubscription = player!.stream.position.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      });

      _durationSubscription = player!.stream.duration.listen((duration) {
        if (mounted) {
          setState(() {
            _duration = duration;
          });
        }
      });

      _playingSubscription = player!.stream.playing.listen((isPlaying) {
        if (mounted) {
          setState(() {
            _isPlaying = isPlaying;
          });
        }
        _onPlayingStateChanged(isPlaying);
      });

      _completedSubscription = player!.stream.completed.listen((completed) {
        if (completed) {
          _onPlaybackCompleted();
        }
      });

      _rateSubscription = player!.stream.rate.listen((rate) {
        if (mounted) {
          setState(() {
            _playbackSpeed = rate;
          });
        }
      });

      // Start periodic progress updates
      _startProgressTracking();
    } catch (e) {
      appLogger.e('Failed to initialize player', error: e);
      if (mounted) {
        setState(() {
          _isPlayerInitialized = false;
        });
      }
    }
  }

  Future<void> _initializeAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio, // Optimized for audiobooks
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech, // Optimized for voice
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ));

      // Handle interruptions (phone calls, other apps, etc.)
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          player?.pause();
          appLogger.i('Playback paused due to interruption');
        }
      });

      // Handle audio becoming noisy (headphones unplugged)
      session.becomingNoisyEventStream.listen((_) {
        player?.pause();
        appLogger.i('Playback paused due to audio becoming noisy (headphones unplugged?)');
      });
    } catch (e) {
      appLogger.w('Failed to configure audio session', error: e);
    }
  }

  Future<void> _updateMediaService() async {
    if (!mounted) return;

    try {
      final mediaService = MediaServiceManager.instance;

      // Build thumbnail URL if available
      String? thumbnailUrl;
      final clientProvider = context.plexClient;
      final client = clientProvider.client;

      if (_currentMetadata?.thumb != null && client != null) {
        final baseUrl = client.config.baseUrl;
        final token = client.config.token;
        if (token != null) {
          thumbnailUrl = '$baseUrl${_currentMetadata!.thumb}?X-Plex-Token=$token';
        }
      }

      // Set mediaItem FIRST before updating player
      if (_currentMetadata != null) {
        mediaService.updateMediaItem(_currentMetadata!, thumbnailUrl);
      }

      if (!mounted) return;

      await mediaService.updatePlayer(
        player: player,
        onNext: _hasNextTrack ? _playNext : null,
        onPrevious: _hasPreviousTrack ? _playPrevious : null,
      );
    } catch (e) {
      appLogger.w('Failed to update media service', error: e);
    }
  }

  Future<void> _startPlayback() async {
    try {
      final clientProvider = context.plexClient;
      final client = clientProvider.client;
      if (client == null) {
        throw Exception('No client available');
      }

      if (_currentMetadata == null) {
        throw Exception('No metadata available');
      }

      // Get the audio file URL
      final audioUrl = await client.getVideoUrl(_currentMetadata!.ratingKey);

      if (audioUrl != null) {
        // Open audio file
        await player!.open(Media(audioUrl), play: false);

        // Wait for media to be ready
        int attempts = 0;
        while (player!.state.duration.inMilliseconds == 0 && attempts < 100) {
          await Future.delayed(const Duration(milliseconds: 100));
          attempts++;
        }

        // Set up playback position if resuming
        if (_currentMetadata!.viewOffset != null && _currentMetadata!.viewOffset! > 0) {
          final resumePosition = Duration(milliseconds: _currentMetadata!.viewOffset!);
          await player!.seek(resumePosition);
        }

        // Start playback
        await player!.play();

        // Force media service state update
        MediaServiceManager.instance.forceStateUpdate();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not find audio file')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    // Stop progress tracking
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();

    // Cancel stream subscriptions
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _rateSubscription?.cancel();

    // Stop media service and clear OS controls
    MediaServiceManager.instance.stop();

    // Send final stopped state
    _sendProgress('stopped');

    // Restore system UI
    OrientationHelper.restoreSystemUI();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);

    player?.dispose();
    super.dispose();
  }

  void _startProgressTracking() {
    // Send progress update every 10 seconds
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (player?.state.playing ?? false) {
        _sendProgress('playing');
      }
    });
  }

  void _onPlayingStateChanged(bool isPlaying) {
    _sendProgress(isPlaying ? 'playing' : 'paused');
  }

  void _sendProgress(String state) {
    if (player == null || _currentMetadata == null) return;

    final position = player!.state.position.inMilliseconds;
    final duration = player!.state.duration.inMilliseconds;

    if (duration > 0) {
      final clientProvider = _cachedClientProvider;
      final client = clientProvider?.client;
      if (client == null) return;

      client
          .updateProgress(
            _currentMetadata!.ratingKey,
            time: position,
            state: state,
            duration: duration,
          )
          .catchError((error) {
            // Silently handle errors
          });
    }
  }

  void _onPlaybackCompleted() {
    if (_hasNextTrack) {
      // Auto-play next chapter
      _playNext();
    } else {
      // Playback finished
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    }
  }

  bool get _hasNextTrack => _currentIndex < _currentPlaylist.length - 1;
  bool get _hasPreviousTrack => _currentIndex > 0;

  Future<void> _playNext() async {
    if (!_hasNextTrack) return;

    setState(() {
      _currentIndex++;
      _currentMetadata = _currentPlaylist[_currentIndex];
    });

    await _stopAndStartNewTrack();
  }

  Future<void> _playPrevious() async {
    if (!_hasPreviousTrack) return;

    setState(() {
      _currentIndex--;
      _currentMetadata = _currentPlaylist[_currentIndex];
    });

    await _stopAndStartNewTrack();
  }

  Future<void> _playChapterAtIndex(int index) async {
    if (index < 0 || index >= _currentPlaylist.length) return;
    if (index == _currentIndex) return; // Already playing this chapter

    setState(() {
      _currentIndex = index;
      _currentMetadata = _currentPlaylist[_currentIndex];
    });

    await _stopAndStartNewTrack();
  }

  Future<void> _stopAndStartNewTrack() async {
    // Pause current playback
    player?.pause();
    _progressTimer?.cancel();
    _sendProgress('stopped');

    // Update media service with new track
    await _updateMediaService();

    // Start new track
    await _startPlayback();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      player?.pause();
    } else {
      player?.play();
    }
  }

  void _seekRelative(Duration offset) {
    if (player == null) return;
    final newPosition = _position + offset;
    // Clamp position manually since Duration doesn't have clamp method
    final clampedPosition = Duration(
      milliseconds: newPosition.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );
    player!.seek(clampedPosition);
  }

  void _showControlsTemporarily() {
    setState(() {
      _showControls = true;
    });

    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _showPlaybackSpeedSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => PlaybackSpeedSheet(player: player!),
    );
  }

  void _showChaptersSheet() {
    // For audiobooks, show playlist as chapter list
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chapters',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _currentPlaylist.length,
                itemBuilder: (context, index) {
                  final chapter = _currentPlaylist[index];
                  final isCurrentChapter = index == _currentIndex;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isCurrentChapter ? Colors.blue : Colors.grey[700],
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isCurrentChapter ? Colors.white : Colors.white70,
                          fontWeight: isCurrentChapter ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    title: Text(
                      chapter.title,
                      style: TextStyle(
                        color: isCurrentChapter ? Colors.white : Colors.white70,
                        fontWeight: isCurrentChapter ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _playChapterAtIndex(index);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSleepTimerSheet() {
    // SleepTimerSheet handles the timer internally
    showModalBottomSheet(
      context: context,
      builder: (context) => SleepTimerSheet(
        player: player!,
        defaultDuration: 30, // Default 30 minutes
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while player initializes
    if (!_isPlayerInitialized || player == null || _currentMetadata == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          if (_showControls) {
            setState(() {
              _showControls = false;
            });
            _hideControlsTimer?.cancel();
          } else {
            _showControlsTemporarily();
          }
        },
        child: SafeArea(
          child: Stack(
            children: [
              // Main content
              Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 60), // Space for app bar

                        // Album art
                        _buildAlbumArt(),
                        const SizedBox(height: 40),

                        // Book title
                        Text(
                          _currentMetadata!.parentTitle ?? _currentMetadata!.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),

                        // Author
                        if (_currentMetadata!.grandparentTitle != null)
                          Text(
                            _currentMetadata!.grandparentTitle!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 16),

                        // Current chapter
                        Text(
                          _currentMetadata!.title,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 40),

                        // Timeline scrubber
                        _buildTimeline(),
                        const SizedBox(height: 32),

                        // Playback controls
                        _buildPlaybackControls(),
                        const SizedBox(height: 32),

                        // Additional controls
                        _buildAdditionalControls(),
                      ],
                    ),
                  ),
                ),
              ),

              // Top app bar (show/hide with controls)
              if (_showControls)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumArt() {
    final clientProvider = context.watch<PlexClientProvider>();
    final client = clientProvider.client;

    // Use parent thumb (book cover) if available, otherwise use track thumb
    final thumbUrl = _currentMetadata!.parentThumb ?? _currentMetadata!.thumb;

    if (thumbUrl != null && client != null) {
      return Container(
        width: 300,
        height: 300,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CachedNetworkImage(
            imageUrl: client.getThumbnailUrl(thumbUrl),
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: Colors.grey[900],
              child: const Center(
                child: Icon(Icons.headphones, size: 100, color: Colors.white30),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey[900],
              child: const Center(
                child: Icon(Icons.headphones, size: 100, color: Colors.white30),
              ),
            ),
          ),
        ),
      );
    } else {
      return Container(
        width: 300,
        height: 300,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Icon(Icons.headphones, size: 100, color: Colors.white30),
        ),
      );
    }
  }

  Widget _buildTimeline() {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white30,
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: _duration.inMilliseconds > 0
                ? _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble())
                : 0,
            min: 0,
            max: _duration.inMilliseconds.toDouble(),
            onChanged: (value) {
              player?.seek(Duration(milliseconds: value.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous track
        IconButton(
          icon: const Icon(Icons.skip_previous),
          iconSize: 48,
          color: _hasPreviousTrack ? Colors.white : Colors.white30,
          onPressed: _hasPreviousTrack ? _playPrevious : null,
        ),
        const SizedBox(width: 16),

        // Rewind 30s
        IconButton(
          icon: const Icon(Icons.replay_30),
          iconSize: 48,
          color: Colors.white,
          onPressed: () => _seekRelative(const Duration(seconds: -30)),
        ),
        const SizedBox(width: 24),

        // Play/Pause
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            iconSize: 56,
            color: Colors.black,
            onPressed: _togglePlayPause,
          ),
        ),
        const SizedBox(width: 24),

        // Forward 30s
        IconButton(
          icon: const Icon(Icons.forward_30),
          iconSize: 48,
          color: Colors.white,
          onPressed: () => _seekRelative(const Duration(seconds: 30)),
        ),
        const SizedBox(width: 16),

        // Next track
        IconButton(
          icon: const Icon(Icons.skip_next),
          iconSize: 48,
          color: _hasNextTrack ? Colors.white : Colors.white30,
          onPressed: _hasNextTrack ? _playNext : null,
        ),
      ],
    );
  }

  Widget _buildAdditionalControls() {
    final sleepTimer = SleepTimerService();
    final isSleepTimerActive = sleepTimer.isActive;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Playback speed
        _buildControlButton(
          label: '${_playbackSpeed}x',
          onPressed: _showPlaybackSpeedSheet,
        ),

        // Sleep timer
        _buildControlButton(
          icon: isSleepTimerActive ? Icons.bedtime : Icons.bedtime_outlined,
          label: isSleepTimerActive ? 'Active' : 'Sleep',
          onPressed: _showSleepTimerSheet,
        ),

        // Chapters
        _buildControlButton(
          icon: Icons.list,
          label: 'Chapters',
          onPressed: _showChaptersSheet,
        ),
      ],
    );
  }

  Widget _buildControlButton({
    IconData? icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20),
            const SizedBox(width: 8),
          ],
          Text(label),
        ],
      ),
    );
  }
}
