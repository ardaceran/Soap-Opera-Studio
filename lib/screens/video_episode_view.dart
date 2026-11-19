import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme.dart';

/// Plays a generated episode MP4 (9:16, captions burned in by the worker).
/// Tap to pause/play. [onFinished] runs once when the episode ends
/// (the player screen opens the vote there).
class VideoEpisodeView extends StatefulWidget {
  const VideoEpisodeView({
    super.key,
    required this.url,
    required this.label,
    this.onFinished,
    this.onVote,
  });

  final String url;
  final String label;
  final VoidCallback? onFinished;
  final VoidCallback? onVote;

  @override
  State<VideoEpisodeView> createState() => _VideoEpisodeViewState();
}

class _VideoEpisodeViewState extends State<VideoEpisodeView> {
  late final VideoPlayerController _video;
  bool _finished = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _video = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _video.addListener(_onTick);
    _video.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _video.play();
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  void _onTick() {
    final v = _video.value;
    if (v.hasError && _error == null) {
      setState(() => _error = v.errorDescription ?? 'Video could not be played');
      return;
    }
    final ended = v.isInitialized &&
        v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 200);
    if (ended && !_finished) {
      _finished = true;
      widget.onFinished?.call();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _video.removeListener(_onTick);
    _video.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!_video.value.isInitialized) return;
    if (_video.value.isPlaying) {
      _video.pause();
    } else {
      if (_finished) {
        _finished = false;
        _video.seekTo(Duration.zero);
      }
      _video.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _video.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: AspectRatio(
            aspectRatio: ready ? _video.value.aspectRatio : 9 / 16,
            child: GestureDetector(
              onTap: _toggle,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Could not play the episode:\n$_error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    )
                  else if (!ready)
                    const Center(child: CircularProgressIndicator())
                  else
                    VideoPlayer(_video),
                  if (ready)
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: VideoProgressIndicator(
                        _video,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 24,
                    left: 16,
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome, size: 14, color: kGold),
                        const SizedBox(width: 4),
                        Text(
                          widget.label,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 20,
                    right: 4,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  if (widget.onVote != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24,
                      child: FilledButton.icon(
                        onPressed: widget.onVote,
                        icon: const Icon(Icons.how_to_vote),
                        label: const Text('Vote for the next episode'),
                      ),
                    ),
                  if (ready && !_video.value.isPlaying && _error == null)
                    const Center(
                      child: Icon(Icons.play_arrow,
                          size: 80, color: Colors.white70),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
