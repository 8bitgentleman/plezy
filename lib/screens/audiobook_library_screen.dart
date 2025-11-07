import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import '../models/plex_library.dart';
import '../models/plex_metadata.dart';
import '../client/plex_client.dart';
import '../providers/plex_client_provider.dart';
import '../providers/settings_provider.dart';
import '../services/settings_service.dart';
import '../utils/provider_extensions.dart';
import '../utils/app_logger.dart';
import '../widgets/media_card.dart';
import '../widgets/desktop_app_bar.dart';
import '../mixins/refreshable.dart';
import '../mixins/item_updatable.dart';

/// Screen for browsing audiobook libraries
///
/// Displays authors (type: "artist") in an audiobook library.
/// Each author card navigates to the author's books when tapped.
class AudiobookLibraryScreen extends StatefulWidget {
  final PlexLibrary library;

  const AudiobookLibraryScreen({
    super.key,
    required this.library,
  });

  @override
  State<AudiobookLibraryScreen> createState() => _AudiobookLibraryScreenState();
}

class _AudiobookLibraryScreenState extends State<AudiobookLibraryScreen>
    with Refreshable, ItemUpdatable {
  @override
  PlexClient get client => context.clientSafe;

  List<PlexMetadata> _authors = [];
  bool _isLoadingAuthors = false;
  String? _errorMessage;

  // Pagination state
  int _currentPage = 0;
  bool _hasMoreItems = true;
  CancelToken? _cancelToken;
  int _requestId = 0;
  static const int _pageSize = 1000;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  /// Helper method to get user-friendly error message from exception
  String _getErrorMessage(dynamic error, String context) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timeout while loading $context';
        case DioExceptionType.connectionError:
          return 'Unable to connect to Plex server';
        default:
          appLogger.e('Error loading $context', error: error);
          return 'Failed to load $context: ${error.message}';
      }
    }

    appLogger.e('Unexpected error in $context', error: error);
    return 'Failed to load $context: $error';
  }

  Future<void> _loadContent() async {
    // Cancel any existing requests
    _cancelToken?.cancel();
    _cancelToken = CancelToken();
    final currentRequestId = ++_requestId;

    setState(() {
      _isLoadingAuthors = true;
      _errorMessage = null;
      _currentPage = 0;
      _hasMoreItems = true;
      _authors = [];
    });

    try {
      final clientProvider = Provider.of<PlexClientProvider>(
        context,
        listen: false,
      );
      final client = clientProvider.client;
      if (client == null) {
        throw Exception('No client available');
      }

      // Load pages sequentially
      await _loadAllPagesSequentially(
        currentRequestId,
        client,
      );
    } catch (e) {
      // Ignore cancellation errors
      if (e is DioException && e.type == DioExceptionType.cancel) {
        return;
      }

      setState(() {
        _errorMessage = _getErrorMessage(e, 'audiobook library');
        _isLoadingAuthors = false;
      });
    }
  }

  /// Load all pages sequentially until all items are fetched
  Future<void> _loadAllPagesSequentially(
    int requestId,
    PlexClient client,
  ) async {
    while (_hasMoreItems && requestId == _requestId) {
      try {
        final items = await client.getLibraryContent(
          widget.library.key,
          start: _currentPage * _pageSize,
          size: _pageSize,
          cancelToken: _cancelToken,
        );

        // Check if request is still valid
        if (requestId != _requestId) {
          return; // Request was superseded
        }

        setState(() {
          _authors.addAll(items);
          _currentPage++;
          _hasMoreItems = items.length >= _pageSize;

          // Mark as not loading if this is the last page
          if (!_hasMoreItems) {
            _isLoadingAuthors = false;
          }
        });
      } catch (e) {
        // Check if it's a cancellation
        if (e is DioException && e.type == DioExceptionType.cancel) {
          return;
        }

        // For other errors, update state and rethrow
        setState(() {
          _isLoadingAuthors = false;
          _hasMoreItems = false;
        });
        rethrow;
      }
    }
  }

  @override
  void updateItemInLists(String ratingKey, PlexMetadata updatedMetadata) {
    final index = _authors.indexWhere((item) => item.ratingKey == ratingKey);
    if (index != -1) {
      _authors[index] = updatedMetadata;
    }
  }

  @override
  void refresh() {
    _loadContent();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          DesktopSliverAppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.headphones, size: 20),
                const SizedBox(width: 8),
                Text(widget.library.title),
              ],
            ),
            pinned: true,
            floating: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            scrolledUnderElevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, semanticLabel: 'Refresh'),
                onPressed: refresh,
              ),
            ],
          ),

          // Content
          if (_isLoadingAuthors && _authors.isEmpty)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(_errorMessage!),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadContent,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_authors.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_open, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No authors found'),
                  ],
                ),
              ),
            )
          else ...[
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                if (settingsProvider.viewMode == ViewMode.list) {
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final author = _authors[index];
                        return MediaCard(
                          key: Key(author.ratingKey),
                          item: author,
                          onRefresh: updateItem,
                        );
                      }, childCount: _authors.length),
                    ),
                  );
                } else {
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: _getMaxCrossAxisExtent(
                          context,
                          settingsProvider.libraryDensity,
                        ),
                        childAspectRatio: 2 / 3.3,
                        crossAxisSpacing: 0,
                        mainAxisSpacing: 0,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final author = _authors[index];
                        return MediaCard(
                          key: Key(author.ratingKey),
                          item: author,
                          onRefresh: updateItem,
                        );
                      }, childCount: _authors.length),
                    ),
                  );
                }
              },
            ),

            // Show loading indicator if there are more items to load
            if (_hasMoreItems && _isLoadingAuthors)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(
                        'Loading authors... (${_authors.length} loaded)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  double _getMaxCrossAxisExtent(BuildContext context, LibraryDensity density) {
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = 16.0; // 8px left + 8px right
    final availableWidth = screenWidth - padding;

    if (screenWidth >= 900) {
      // Wide screens (desktop/large tablet landscape): Responsive division
      double divisor;
      double maxItemWidth;

      switch (density) {
        case LibraryDensity.comfortable:
          divisor = 6.5;
          maxItemWidth = 280;
          break;
        case LibraryDensity.normal:
          divisor = 8.0;
          maxItemWidth = 200;
          break;
        case LibraryDensity.compact:
          divisor = 10.0;
          maxItemWidth = 160;
          break;
      }

      return (availableWidth / divisor).clamp(0, maxItemWidth);
    } else if (screenWidth >= 600) {
      // Medium screens (tablets): Fixed 4-5-6 items
      int targetItemCount = switch (density) {
        LibraryDensity.comfortable => 4,
        LibraryDensity.normal => 5,
        LibraryDensity.compact => 6,
      };
      return availableWidth / targetItemCount;
    } else {
      // Small screens (phones): Fixed 2-3-4 items
      int targetItemCount = switch (density) {
        LibraryDensity.comfortable => 2,
        LibraryDensity.normal => 3,
        LibraryDensity.compact => 4,
      };
      return availableWidth / targetItemCount;
    }
  }
}
