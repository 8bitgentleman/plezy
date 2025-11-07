# Plezy Architecture Guide

**Modern Cross-Platform Plex Client built with Flutter**

This document serves as a comprehensive guide to Plezy's architecture, patterns, and codebase structure. It's designed to help new developers (human or AI) quickly understand how the app works and where to make changes.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Technology Stack](#technology-stack)
3. [Project Structure](#project-structure)
4. [State Management](#state-management)
5. [Navigation](#navigation)
6. [Data Models](#data-models)
7. [API Client](#api-client)
8. [Media Playback](#media-playback)
9. [Services](#services)
10. [UI Architecture](#ui-architecture)
11. [Key Patterns](#key-patterns)
12. [Development Guidelines](#development-guidelines)

---

## Project Overview

**Plezy** is a modern, cross-platform Plex client that currently supports:
- Movies
- TV Shows (with seasons and episodes)
- Media playback with advanced controls
- Library management and discovery

**Supported Platforms:**
- iOS
- Android
- macOS
- Windows (partial)
- Linux (partial)

**Core Features:**
- Library browsing with grid/list views
- Media playback with chapters, subtitles, audio tracks
- Progress tracking synced to Plex
- OS media controls and lock screen integration
- Keyboard shortcuts and gesture controls
- Sleep timer and playback speed control

---

## Technology Stack

### Core Framework
- **Flutter** - Cross-platform UI framework
- **Dart** - Programming language

### State Management
- **Riverpod** (v2.x) - Reactive state management
- **Provider pattern** - Service locator and dependency injection

### Media Playback
- **MediaKit** (v1.1.10+1) - MPV-based media player
- **media_kit_video** - Video rendering
- **audio_service** (v0.18.18) - OS media integration

### Storage
- **shared_preferences** - Key-value storage for settings
- **path_provider** - Platform-specific paths

### HTTP & Networking
- **http** package - REST API calls
- **xml** - XML parsing for Plex responses

### Code Generation
- **json_serializable** - JSON serialization
- **freezed** - Immutable data classes (if used)

---

## Project Structure

```
lib/
├── client/              # API client and network layer
│   └── plex_client.dart
├── models/              # Data models
│   ├── plex_library.dart
│   ├── plex_metadata.dart
│   ├── plex_media_info.dart
│   ├── plex_server.dart
│   └── ...
├── providers/           # Riverpod providers
│   ├── connection_provider.dart
│   ├── library_provider.dart
│   ├── hidden_libraries_provider.dart
│   └── ...
├── screens/             # Full-screen pages
│   ├── home_screen.dart
│   ├── libraries_screen.dart
│   ├── media_detail_screen.dart
│   ├── video_player_screen.dart
│   └── ...
├── services/            # Business logic and utilities
│   ├── media_kit_audio_handler.dart
│   ├── media_service_manager.dart
│   ├── sleep_timer_service.dart
│   ├── keyboard_shortcuts_service.dart
│   └── settings_service.dart
├── widgets/             # Reusable UI components
│   ├── media_card.dart
│   ├── video_controls/
│   │   ├── video_controls.dart
│   │   ├── sheets/
│   │   └── ...
│   └── ...
├── utils/               # Utility functions
│   ├── video_player_navigation.dart
│   └── ...
└── main.dart           # App entry point
```

### Directory Responsibilities

| Directory | Purpose | Examples |
|-----------|---------|----------|
| `/client/` | API communication with Plex servers | `plexClient.getLibraries()` |
| `/models/` | Data structures for Plex entities | `PlexMetadata`, `PlexLibrary` |
| `/providers/` | State management and data providers | `libraryProvider`, `connectionProvider` |
| `/screens/` | Full-screen pages/routes | Library browser, player, settings |
| `/services/` | Business logic, singletons, utilities | Audio service, sleep timer, shortcuts |
| `/widgets/` | Reusable UI components | Media cards, controls, sheets |
| `/utils/` | Helper functions and utilities | Navigation helpers, formatters |

---

## State Management

### Riverpod Architecture

Plezy uses **Riverpod** for state management with a provider-based architecture.

#### Provider Types Used

**1. StateNotifierProvider**
Used for mutable state that changes over time:

```dart
// Example: Library provider
final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
  return LibraryNotifier(ref);
});
```

**2. Provider**
Used for read-only computed values or dependencies:

```dart
// Example: Plex client provider
final plexClientProvider = Provider<PlexClient>((ref) {
  final server = ref.watch(connectionProvider);
  return PlexClient(server);
});
```

**3. FutureProvider**
Used for asynchronous data that loads once:

```dart
// Example: Fetching libraries
final librariesProvider = FutureProvider<List<PlexLibrary>>((ref) async {
  final client = ref.watch(plexClientProvider);
  return await client.getLibraries();
});
```

#### Key Providers

| Provider | File | Purpose |
|----------|------|---------|
| `connectionProvider` | `providers/connection_provider.dart` | Current Plex server connection |
| `libraryProvider` | `providers/library_provider.dart` | Library state and content |
| `hiddenLibrariesProvider` | `providers/hidden_libraries_provider.dart` | User library visibility preferences |
| `plexClientProvider` | `providers/plex_client_provider.dart` | Plex API client instance |

#### Reading State in Widgets

```dart
// Inside a ConsumerWidget
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch for changes
    final libraryState = ref.watch(libraryProvider);

    // Read once without rebuilding
    final client = ref.read(plexClientProvider);

    return Text(libraryState.title);
  }
}
```

#### Updating State

```dart
// Inside a widget or another provider
ref.read(libraryProvider.notifier).loadContent(sectionId);
```

---

## Navigation

### Navigation Pattern

Plezy uses **Flutter's Material Navigation** with imperative routing.

#### Navigation Examples

**1. Push New Screen:**
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => MediaDetailScreen(metadata: item),
  ),
);
```

**2. Replace Current Screen:**
```dart
Navigator.pushReplacement(
  context,
  MaterialPageRoute(builder: (context) => NewScreen()),
);
```

**3. Pop Back:**
```dart
Navigator.pop(context);
```

#### Navigation Utilities

**Location:** `lib/utils/video_player_navigation.dart`

**Purpose:** Centralized navigation logic for media playback

```dart
Future<void> navigateToVideoPlayer(
  BuildContext context, {
  required PlexMetadata metadata,
  List<PlexMetadata>? playlist,
  int? initialIndex,
}) async {
  // Handles navigation to video player with proper setup
}
```

#### Common Navigation Flows

**Flow 1: Library → Detail → Player**
```
LibrariesScreen (shows all libraries)
  ↓ tap library
LibraryScreen (shows media items)
  ↓ tap movie
MediaDetailScreen (shows details)
  ↓ tap play
VideoPlayerScreen (playback)
```

**Flow 2: Episode Direct Play**
```
LibraryScreen (shows episodes)
  ↓ tap episode
VideoPlayerScreen (direct playback)
```

**Flow 3: TV Show Navigation**
```
LibraryScreen (shows TV shows)
  ↓ tap show
MediaDetailScreen (show info + season list)
  ↓ tap season
SeasonDetailScreen (episode list)
  ↓ tap episode
VideoPlayerScreen (playback)
```

---

## Data Models

### Core Models

All models are in `lib/models/` and use `json_serializable` for JSON parsing.

#### PlexLibrary

**File:** `lib/models/plex_library.dart`

Represents a Plex library (Movies, TV Shows, Music, etc.)

```dart
class PlexLibrary {
  final String key;          // Library ID (e.g., "1", "2")
  final String title;        // Library name
  final String type;         // "movie", "show", "artist", "photo"
  final String? agent;       // Metadata agent (e.g., "tv.plex.agents.movie")
  final String? scanner;     // Scanner type
  final String? language;    // Library language
  final String? uuid;        // Unique identifier
  final int? updatedAt;      // Last update timestamp
  final int? createdAt;      // Creation timestamp
}
```

**Type Values:**
- `"movie"` - Movie library
- `"show"` - TV show library
- `"artist"` - Music/audiobook library
- `"photo"` - Photo library

#### PlexMetadata

**File:** `lib/models/plex_metadata.dart`

Represents any media item (movie, show, season, episode, track).

**Key Fields:**
```dart
class PlexMetadata {
  // Core identification
  final String ratingKey;        // Unique ID for this item
  final String key;              // API endpoint path
  final String type;             // "movie", "show", "season", "episode", "track"
  final String title;            // Item title

  // Content info
  final String? summary;         // Description
  final String? contentRating;   // Rating (PG-13, TV-MA, etc.)
  final double? rating;          // User rating (0-10)
  final int? year;               // Release year
  final String? studio;          // Studio/network

  // Visual assets
  final String? thumb;           // Poster/thumbnail path
  final String? art;             // Background art path
  String? clearLogo;             // Transparent logo (extracted from Image array)

  // Playback
  final int? duration;           // Duration in milliseconds
  final int? viewOffset;         // Resume position in milliseconds
  final int? viewCount;          // Number of times watched

  // Hierarchical (for TV shows)
  final String? grandparentTitle;      // Show title (for episodes)
  final String? grandparentThumb;      // Show poster
  final String? grandparentArt;        // Show art
  final String? grandparentRatingKey;  // Show ID
  final String? parentTitle;           // Season title (for episodes)
  final String? parentThumb;           // Season poster
  final String? parentRatingKey;       // Season ID
  final int? parentIndex;              // Season number
  final int? index;                    // Episode number

  // Progress tracking (for shows/seasons)
  final int? leafCount;          // Total episodes
  final int? viewedLeafCount;    // Watched episodes
}
```

**Helper Methods:**
```dart
// Smart display title (shows series name for episodes)
String get displayTitle;

// Subtitle for episodes (shows episode title when series is displayed)
String? get displaySubtitle;

// Smart poster selection with fallback
String? posterThumb({bool useSeasonPoster = false});

// Type checking
String get itemType => type.toLowerCase();
```

**Type Hierarchy:**
- `"movie"` - Standalone movie
- `"show"` - TV series (has children: seasons)
- `"season"` - Season (has children: episodes, has parent: show)
- `"episode"` - Episode (has parent: season, grandparent: show)
- `"artist"` - Music artist (has children: albums)
- `"album"` - Music album (has children: tracks, parent: artist)
- `"track"` - Music track (has parent: album, grandparent: artist)

#### PlexMediaInfo

**File:** `lib/models/plex_media_info.dart`

Represents detailed media information including streams and chapters.

```dart
class PlexMediaInfo {
  final List<PlexMedia> media;  // Media streams
}

class PlexMedia {
  final String? videoResolution;    // "1080", "4k", etc.
  final int? bitrate;               // Bitrate in kbps
  final int? width;                 // Video width
  final int? height;                // Video height
  final String? videoCodec;         // "h264", "hevc", etc.
  final String? audioCodec;         // "aac", "ac3", etc.
  final List<PlexPart> parts;       // File parts
}

class PlexPart {
  final String key;                 // File path/URL
  final int? duration;              // Duration in ms
  final String? file;               // Local file path
  final List<PlexStream> streams;   // Audio/video/subtitle streams
}

class PlexStream {
  final int? streamType;            // 1=video, 2=audio, 3=subtitle
  final String? codec;              // Stream codec
  final String? language;           // Language code
  final String? title;              // Track title
  // ... more fields
}

class PlexChapter {
  final int id;                     // Chapter ID
  final int? index;                 // Chapter number
  final int? startTimeOffset;       // Start time in ms
  final int? endTimeOffset;         // End time in ms
  final String? title;              // Chapter title
  final String? thumb;              // Chapter thumbnail
}
```

**Stream Types:**
- `streamType: 1` - Video stream
- `streamType: 2` - Audio track
- `streamType: 3` - Subtitle track

#### PlexServer

**File:** `lib/models/plex_server.dart`

Represents a Plex server connection.

```dart
class PlexServer {
  final String name;          // Server name
  final String host;          // Server URL
  final String token;         // Authentication token
  final String? machineId;    // Unique server ID
  final String? version;      // Server version
}
```

---

## API Client

### PlexClient

**File:** `lib/client/plex_client.dart`

Central API client for all Plex server communication.

#### Initialization

```dart
final client = PlexClient(
  baseUrl: 'https://192.168.1.100:32400',
  token: 'YOUR_PLEX_TOKEN',
);
```

#### Key Methods

**Library Management:**
```dart
// Get all libraries
Future<List<PlexLibrary>> getLibraries()

// Get library content (paginated)
Future<List<PlexMetadata>> getLibraryContent(
  String sectionId,
  {int start = 0, int size = 100, String? sort}
)

// Get library filters (genre, year, etc.)
Future<Map<String, dynamic>> getLibraryFilters(String sectionId)

// Get sort options for library
Future<List<Map<String, dynamic>>> getLibrarySorts(String sectionId)
```

**Metadata:**
```dart
// Get item metadata
Future<PlexMetadata> getMetadata(
  String ratingKey,
  {bool includeOnDeck = false, bool includeChapters = false}
)

// Get children (seasons for show, episodes for season)
Future<List<PlexMetadata>> getChildren(String ratingKey)

// Get media info (streams, chapters)
Future<PlexMediaInfo> getMediaInfo(String ratingKey)
```

**Discovery:**
```dart
// Get recently added items
Future<List<PlexMetadata>> getRecentlyAdded({int limit = 20})

// Get "On Deck" (continue watching)
Future<List<PlexMetadata>> getOnDeck({int limit = 20})

// Get recommendation hubs for library
Future<List<Hub>> getHubs(String sectionId, {int count = 10})

// Search
Future<List<PlexMetadata>> search(String query, {int limit = 50})
```

**Playback:**
```dart
// Mark as watched
Future<void> markWatched(String ratingKey)

// Mark as unwatched
Future<void> markUnwatched(String ratingKey)

// Update playback progress
Future<void> updateProgress(
  String ratingKey,
  {required int time, required String state, int? duration}
)
```

#### API Response Handling

All Plex API responses are XML-based and converted to JSON:

```dart
// Internal flow
HTTP Response (XML)
  ↓ xml.parse()
XML Document
  ↓ _xmlToJson()
JSON Map
  ↓ Model.fromJson()
Dart Object
```

#### Error Handling

```dart
try {
  final libraries = await client.getLibraries();
} catch (e) {
  // Handle network errors, auth failures, etc.
  print('Error: $e');
}
```

#### Filtering Logic

**Current Behavior:** Music/audiobooks are filtered out in several places:

1. **Library List** (`libraries_screen.dart:110-112`)
2. **Recently Added** (`plex_client.dart:364-368`)
3. **On Deck** (`plex_client.dart:380-384`)
4. **Hubs** (`plex_client.dart:938-942`)

**Filter Pattern:**
```dart
items.where((item) {
  final type = item.type.toLowerCase();
  return type != 'artist' && type != 'album' && type != 'track';
}).toList();
```

---

## Media Playback

### MediaKit Player

**File:** `lib/screens/video_player_screen.dart`

Plezy uses **MediaKit** with an MPV backend for media playback.

#### Player Initialization

```dart
player = Player(
  configuration: PlayerConfiguration(
    libass: true,                    // Subtitle rendering
    bufferSize: bufferSizeBytes,     // Configurable buffer
    logLevel: logLevel,              // MPVLogLevel.error or .debug
    mpvConfiguration: {
      'sub-font-size': '55',
      'sub-color': '#FFFFFFFF',
      'audio-delay': audioDelay,
      'sub-delay': subDelay,
    },
  ),
);

// Create video controller
controller = VideoController(
  player!,
  configuration: VideoControllerConfiguration(
    enableHardwareAcceleration: enableHardwareDecoding,
  ),
);
```

#### Playback Flow

```dart
// 1. Load media
await player.open(Media(videoUrl));

// 2. Set initial position (resume)
if (startPosition > 0) {
  await player.seek(Duration(milliseconds: startPosition));
}

// 3. Listen to state changes
player.stream.playing.listen((isPlaying) {
  // Update UI
});

player.stream.position.listen((position) {
  // Update progress
});

// 4. Control playback
await player.play();
await player.pause();
await player.seek(Duration(seconds: 30));
player.setRate(1.5); // Playback speed
```

#### Player Features

| Feature | Implementation | File |
|---------|----------------|------|
| Play/Pause | `player.play()` / `player.pause()` | `video_player_screen.dart` |
| Seek | `player.seek(Duration)` | `video_controls.dart` |
| Speed | `player.setRate(double)` | `playback_speed_sheet.dart` |
| Volume | `player.setVolume(double)` | `video_controls.dart` |
| Audio Track | `player.setAudioTrack(AudioTrack)` | `audio_track_sheet.dart` |
| Subtitle | `player.setSubtitleTrack(SubtitleTrack)` | `subtitle_track_sheet.dart` |
| Chapters | Manual seek to chapter start time | `chapter_sheet.dart` |

#### Audio Service Integration

**File:** `lib/services/media_kit_audio_handler.dart`

Bridges MediaKit player with OS media controls (lock screen, notifications, etc.)

```dart
class MediaKitAudioHandler extends BaseAudioHandler {
  final Player player;

  // OS calls these methods
  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> fastForward() => player.seek(
    player.state.position + Duration(seconds: 15)
  );

  // ... more controls
}
```

**Features:**
- Lock screen controls (iOS, Android, macOS)
- Notification with artwork
- Play/pause/skip controls
- Position scrubbing
- Playback speed
- Automatic state sync

#### MediaServiceManager

**File:** `lib/services/media_service_manager.dart`

Singleton that manages the audio service lifecycle.

```dart
final manager = MediaServiceManager.instance;

// Initialize (done at app startup)
await manager.init();

// Update now playing
await manager.updateMediaItem(
  title: metadata.title,
  artist: metadata.grandparentTitle,
  artUri: thumbUrl,
  duration: duration,
);

// Update playback state
await manager.updatePlaybackState(
  playing: isPlaying,
  position: currentPosition,
);
```

---

## Services

### Key Services

Services are singleton business logic components in `lib/services/`.

#### SleepTimerService

**File:** `lib/services/sleep_timer_service.dart`

Manages sleep timer functionality.

```dart
final sleepTimer = SleepTimerService();

// Start timer
sleepTimer.startTimer(
  Duration(minutes: 30),
  onComplete: () {
    // Pause playback
    player.pause();
  },
);

// Check if active
if (sleepTimer.isActive) {
  final remaining = sleepTimer.remainingTime;
}

// Cancel timer
sleepTimer.cancelTimer();

// Extend timer
sleepTimer.extendTimer(Duration(minutes: 15));
```

#### KeyboardShortcutsService

**File:** `lib/services/keyboard_shortcuts_service.dart`

Handles keyboard shortcuts for desktop platforms.

**Available Actions:**
- Play/Pause (Space)
- Seek forward/backward (Arrow keys)
- Volume up/down (↑/↓)
- Mute (M)
- Fullscreen (F)
- Speed control (</> or [/])
- Chapter navigation
- Subtitle/audio track switching

**Configuration:** Shortcuts are stored in `SettingsService` and fully customizable.

#### SettingsService

**File:** `lib/services/settings_service.dart`

Manages app settings persistence using `shared_preferences`.

**Common Settings:**
```dart
// Get setting
final bufferSize = settingsService.getBufferSize();  // returns int
final enableHW = settingsService.getEnableHardwareDecoding();  // returns bool

// Set setting
await settingsService.setBufferSize(32);
await settingsService.setEnableHardwareDecoding(true);
```

**Setting Categories:**
- Playback (buffer size, hardware decoding)
- Video (seek times, rotation lock)
- Audio (sync offset, default track language)
- Subtitles (sync offset, default language, font settings)
- Keyboard shortcuts
- Library preferences (hidden libraries, sort order)

---

## UI Architecture

### Screen Types

#### 1. List/Grid Screens

**Pattern:** Display collections of media items

**Examples:**
- `LibrariesScreen` - Show all libraries
- `LibraryScreen` - Show items in a library
- `SeasonDetailScreen` - Show episodes in a season

**Common Widgets:**
- `GridView.builder` or `ListView.builder` for scrolling
- `MediaCard` for each item
- Pagination with `ScrollController`

**Example Structure:**
```dart
class LibraryScreen extends ConsumerStatefulWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(library.title)),
      body: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.7,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          return MediaCard(item: items[index]);
        },
      ),
    );
  }
}
```

#### 2. Detail Screens

**Pattern:** Show detailed information about a single item

**Examples:**
- `MediaDetailScreen` - Movie/show details

**Common Elements:**
- Hero image with background art
- Clear logo overlay
- Metadata (year, rating, duration, etc.)
- Summary/description
- Action buttons (Play, Resume, Mark Watched)
- Related content (seasons, similar items)

#### 3. Player Screen

**Pattern:** Full-screen media playback

**Example:** `VideoPlayerScreen`

**Components:**
- `VideoController` widget (renders video)
- `VideoControls` overlay (play/pause, seek, settings)
- Gesture detectors (tap to show controls, double-tap to seek)
- Bottom sheets (settings, chapters, audio/subtitle selection)

### Widget Hierarchy

```
VideoPlayerScreen
├── Video (MediaKit VideoController)
├── GestureDetector (show/hide controls, double-tap seek)
├── VideoControls (overlay)
│   ├── Top Bar (title, back button)
│   ├── Center (play/pause button)
│   ├── Bottom Bar
│   │   ├── Timeline/Scrubber
│   │   ├── Time display
│   │   └── Control buttons
│   └── Settings Button
└── Modal Bottom Sheets
    ├── ChapterSheet
    ├── PlaybackSpeedSheet
    ├── AudioTrackSheet
    ├── SubtitleTrackSheet
    └── VideoSettingsSheet
```

### Reusable Widgets

#### MediaCard

**File:** `lib/widgets/media_card.dart`

Displays a media item (movie, show, episode) with poster and metadata.

**Usage:**
```dart
MediaCard(
  item: plexMetadata,
  onTap: () {
    // Custom tap handler
  },
)
```

**Features:**
- Poster image with fallback
- Watch status indicator (checkmark for watched, progress bar for in-progress)
- Episode/season info for TV shows
- Handles navigation automatically (episodes → player, shows → detail screen)

#### VideoControls

**File:** `lib/widgets/video_controls/video_controls.dart`

Complete video player control UI.

**Components:**
- Play/pause button
- Timeline scrubber with chapter markers
- Time display (current / total)
- Settings button (opens sheets)
- Volume control
- Fullscreen toggle

---

## Key Patterns

### 1. Type-Based Behavior

Throughout the app, behavior is determined by checking the `type` field:

```dart
final itemType = metadata.type.toLowerCase();

if (itemType == 'movie') {
  // Movie-specific logic
} else if (itemType == 'show') {
  // Show-specific logic
} else if (itemType == 'episode') {
  // Episode-specific logic
}
```

**Common Type Checks:**
```dart
// Check if playable
if (itemType == 'episode' || itemType == 'movie') {
  navigateToVideoPlayer(context, metadata: item);
}

// Check if has children
if (itemType == 'show' || itemType == 'season') {
  final children = await client.getChildren(item.ratingKey);
}

// Filter by type
final moviesOnly = items.where((item) =>
  item.type.toLowerCase() == 'movie'
).toList();
```

### 2. Hierarchical Navigation

TV shows use a parent/grandparent structure:

```dart
// Episode → Season → Show
if (metadata.type == 'episode') {
  final showTitle = metadata.grandparentTitle;      // Show name
  final seasonTitle = metadata.parentTitle;         // Season name
  final episodeTitle = metadata.title;              // Episode name

  final showPoster = metadata.grandparentThumb;     // Show poster
  final seasonPoster = metadata.parentThumb;        // Season poster
}
```

### 3. Smart Display Logic

Use helper methods for consistent display:

```dart
// Always use displayTitle for consistent behavior
Text(metadata.displayTitle);  // Shows series name for episodes

// Show subtitle when relevant
if (metadata.displaySubtitle != null) {
  Text(metadata.displaySubtitle!);  // Shows episode name when series is displayed
}

// Poster with fallback
final posterUrl = metadata.posterThumb(useSeasonPoster: true);
```

### 4. Progress Tracking

Progress is tracked at multiple levels:

```dart
// Individual item progress
final progress = metadata.viewOffset ?? 0;
final duration = metadata.duration ?? 1;
final percentage = progress / duration;

// Series/season progress
final totalEpisodes = metadata.leafCount ?? 0;
final watchedEpisodes = metadata.viewedLeafCount ?? 0;
final showProgress = watchedEpisodes / totalEpisodes;
```

### 5. Async Data Loading

Use FutureBuilder or AsyncValue for loading states:

```dart
// Using FutureBuilder
FutureBuilder<List<PlexMetadata>>(
  future: client.getLibraryContent(sectionId),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return CircularProgressIndicator();
    }
    if (snapshot.hasError) {
      return ErrorWidget(snapshot.error);
    }
    return ListView(children: snapshot.data!.map(...));
  },
)

// Using Riverpod AsyncValue
final asyncValue = ref.watch(someProvider);
return asyncValue.when(
  data: (data) => DataWidget(data),
  loading: () => CircularProgressIndicator(),
  error: (err, stack) => ErrorWidget(err),
);
```

### 6. Pagination

Large lists are paginated:

```dart
final scrollController = ScrollController();

scrollController.addListener(() {
  if (scrollController.position.pixels >=
      scrollController.position.maxScrollExtent * 0.8) {
    // Load more items
    loadNextPage();
  }
});
```

---

## Development Guidelines

### Adding a New Media Type

To add support for a new media type (like audiobooks):

1. **Update Filtering Logic**
   - Remove blanket exclusions in `libraries_screen.dart`
   - Update `plex_client.dart` discovery methods
   - Modify `media_card.dart` tap handling

2. **Create Type Detection**
   ```dart
   bool isAudiobook(PlexMetadata item) {
     return item.type.toLowerCase() == 'track' &&
            /* additional conditions */;
   }
   ```

3. **Add UI Screens**
   - Library screen (browse items)
   - Detail screen (show info)
   - Player screen (if different from video player)

4. **Update Navigation**
   - Add new routes in `media_card.dart` or create navigation utility
   - Handle new type in tap handlers

5. **Test API Integration**
   - Verify all necessary Plex endpoints work
   - Test pagination and filtering
   - Verify metadata fields are populated

### Adding a New Feature

1. **Determine Scope**
   - Is it a new screen? → Create in `/screens/`
   - Is it a widget? → Create in `/widgets/`
   - Is it business logic? → Create service in `/services/`
   - Is it state management? → Create provider in `/providers/`

2. **Follow Existing Patterns**
   - Use Riverpod for state
   - Use `ConsumerWidget` or `ConsumerStatefulWidget`
   - Follow Material Design principles
   - Use existing widgets where possible

3. **Add Settings if Needed**
   - Add to `SettingsService`
   - Create settings UI in settings screen
   - Provide reasonable defaults

4. **Test Across Platforms**
   - Mobile (iOS/Android)
   - Desktop (macOS/Windows/Linux)
   - Different screen sizes

### Code Style

**Import Order:**
```dart
// Flutter/Dart
import 'dart:async';
import 'package:flutter/material.dart';

// External packages
import 'package:riverpod/riverpod.dart';
import 'package:media_kit/media_kit.dart';

// Internal
import '../models/plex_metadata.dart';
import '../services/settings_service.dart';
```

**Naming Conventions:**
- Classes: `PascalCase`
- Variables/methods: `camelCase`
- Files: `snake_case.dart`
- Constants: `camelCase` or `SCREAMING_SNAKE_CASE` for compile-time constants

**Documentation:**
```dart
/// Brief description of what this does.
///
/// More detailed explanation if needed.
/// Can span multiple lines.
///
/// Example:
/// ```dart
/// final result = doSomething(param);
/// ```
void doSomething(String param) {
  // Implementation
}
```

### Testing

**Running Tests:**
```bash
flutter test
```

**Adding Tests:**
- Unit tests for services and utilities
- Widget tests for UI components
- Integration tests for complete flows

### Building for Release

**Android:**
```bash
flutter build apk --release
flutter build appbundle --release
```

**iOS:**
```bash
flutter build ios --release
```

**macOS:**
```bash
flutter build macos --release
```

---

## Key Files Reference

### Must-Read Files for New Developers

| File | Why Important | What to Learn |
|------|---------------|---------------|
| `lib/models/plex_metadata.dart` | Core data structure | How Plex represents media |
| `lib/client/plex_client.dart` | API communication | Available endpoints, patterns |
| `lib/screens/video_player_screen.dart` | Player implementation | MediaKit usage, playback flow |
| `lib/widgets/media_card.dart` | Item display | Type-based navigation logic |
| `lib/screens/libraries_screen.dart` | Library browsing | Filtering, pagination |
| `lib/services/media_kit_audio_handler.dart` | OS integration | Background playback, controls |

### Configuration Files

| File | Purpose |
|------|---------|
| `pubspec.yaml` | Dependencies, app metadata |
| `lib/main.dart` | App initialization, theme |
| `android/app/build.gradle` | Android configuration |
| `ios/Runner/Info.plist` | iOS configuration |
| `macos/Runner/Info.plist` | macOS configuration |

---

## Common Tasks

### How to Add a New Setting

1. **Add to SettingsService** (`lib/services/settings_service.dart`):
   ```dart
   Future<void> setMyNewSetting(bool value) async {
     await _prefs.setBool('myNewSetting', value);
   }

   bool getMyNewSetting() {
     return _prefs.getBool('myNewSetting') ?? false; // default
   }
   ```

2. **Create Settings UI** (in settings screen):
   ```dart
   SwitchListTile(
     title: Text('My New Setting'),
     value: settingsService.getMyNewSetting(),
     onChanged: (value) {
       setState(() {
         settingsService.setMyNewSetting(value);
       });
     },
   )
   ```

3. **Use in Code**:
   ```dart
   final myValue = settingsService.getMyNewSetting();
   if (myValue) {
     // Do something
   }
   ```

### How to Add a New API Endpoint

1. **Add Method to PlexClient** (`lib/client/plex_client.dart`):
   ```dart
   Future<List<PlexMetadata>> getMyNewEndpoint() async {
     final uri = Uri.parse('$baseUrl/my/endpoint?X-Plex-Token=$token');
     final response = await http.get(uri);

     if (response.statusCode != 200) {
       throw Exception('Failed to load data');
     }

     final xmlDoc = xml.XmlDocument.parse(response.body);
     final json = _xmlToJson(xmlDoc);

     // Parse response
     final items = (json['MediaContainer']['Metadata'] as List? ?? [])
         .map((item) => PlexMetadata.fromJson(item))
         .toList();

     return items;
   }
   ```

2. **Use in Provider or Widget**:
   ```dart
   final items = await ref.read(plexClientProvider).getMyNewEndpoint();
   ```

### How to Add a New Screen

1. **Create Screen File** (`lib/screens/my_new_screen.dart`):
   ```dart
   import 'package:flutter/material.dart';
   import 'package:flutter_riverpod/flutter_riverpod.dart';

   class MyNewScreen extends ConsumerWidget {
     const MyNewScreen({super.key});

     @override
     Widget build(BuildContext context, WidgetRef ref) {
       return Scaffold(
         appBar: AppBar(
           title: const Text('My New Screen'),
         ),
         body: Center(
           child: Text('Content here'),
         ),
       );
     }
   }
   ```

2. **Navigate to Screen**:
   ```dart
   Navigator.push(
     context,
     MaterialPageRoute(
       builder: (context) => MyNewScreen(),
     ),
   );
   ```

---

## Troubleshooting

### Common Issues

**Issue:** "Provider not found"
- **Cause:** Forgot to wrap app with `ProviderScope`
- **Fix:** Ensure `main.dart` wraps `MaterialApp` with `ProviderScope`

**Issue:** "Player not initialized"
- **Cause:** Trying to use player before initialization
- **Fix:** Wait for player to initialize, check for null

**Issue:** "XML parsing error"
- **Cause:** Unexpected Plex API response format
- **Fix:** Check Plex server version, add null safety checks

**Issue:** "MediaKit not found"
- **Cause:** Native dependencies not installed
- **Fix:** Run `flutter pub get`, restart IDE, rebuild app

### Debug Tips

**Enable Verbose Logging:**
```dart
// In video_player_screen.dart
Player(
  configuration: PlayerConfiguration(
    logLevel: MPVLogLevel.debug,  // Change from .error
  ),
)
```

**Print API Responses:**
```dart
// In plex_client.dart
print('API Response: ${response.body}');
```

**Check Provider State:**
```dart
// In any widget
print('Library State: ${ref.read(libraryProvider)}');
```

---

## Resources

### Documentation
- [Flutter Docs](https://docs.flutter.dev/)
- [Riverpod Docs](https://riverpod.dev/)
- [MediaKit Docs](https://pub.dev/packages/media_kit)
- [Plex API Docs](https://python-plexapi.readthedocs.io/) (Python but helpful)

### Tools
- [Plex API Explorer](https://github.com/Arcanemagus/plex-api/wiki) - Unofficial API documentation
- [Flutter DevTools](https://docs.flutter.dev/tools/devtools) - Debugging and profiling

---

## Contributing

When contributing to Plezy:

1. **Follow Existing Patterns** - Look at similar features for reference
2. **Update Documentation** - Update this file when adding major features
3. **Test Thoroughly** - Test on multiple platforms and screen sizes
4. **Keep Dependencies Updated** - Regularly update packages
5. **Maintain Code Quality** - Use Flutter analyzer, format code

---

**Last Updated:** 2025-11-07
**Document Version:** 1.0
**App Version:** Current at time of writing
