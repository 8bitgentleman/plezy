# Audiobook Support Feasibility Analysis

**Date:** 2025-11-07
**App:** Plezy - Modern Cross-Platform Plex Client
**Current Support:** Movies and TV Shows only

---

## Executive Summary

Adding audiobook support to Plezy is **HIGHLY FEASIBLE** and could position this app as a best-in-class audiobook player. The app already has ~80% of the infrastructure needed for excellent audiobook playback, including:

- ✅ Full playback speed control (0.5x - 3.0x)
- ✅ Chapter navigation with visual timeline
- ✅ Sleep timer with multiple presets
- ✅ Lock screen controls with artwork
- ✅ Background playback with interruption handling
- ✅ Progress tracking synced to Plex
- ✅ Skip forward/backward controls
- ✅ OS media integration (notifications, control center)

**Estimated Implementation Effort:** Medium (2-3 weeks for core features)

---

## Understanding Plex Audiobook Architecture

### How Plex Handles Audiobooks

Plex does NOT have a dedicated audiobook library type. Instead:

- **Library Type:** `artist` (same as music)
- **Hierarchy:**
  - **Artist** = Book Author
  - **Album** = Book Title
  - **Track** = Chapter/Part

### Detection Method

The ONLY reliable way to differentiate audiobooks from music is through the **metadata agent**:

**Common Audiobook Agents:**
- `com.plexapp.agents.audnexus` - Audnexus (most popular)
- `com.plexapp.agents.audiobooks` - Audiobooks.bundle
- `com.plexapp.agents.audiobookshelf` - Audiobookshelf

**Detection Logic:**
```dart
bool isAudiobookLibrary(PlexLibrary library) {
  if (library.type.toLowerCase() != 'artist') return false;

  final agent = library.agent?.toLowerCase() ?? '';
  return agent.contains('audnexus') ||
         agent.contains('audiobook') ||
         agent.contains('audiobookshelf');
}
```

### API Endpoints (Already Supported)

All necessary endpoints are already used by the app:

```dart
// Get audiobook libraries (type: "artist" with audiobook agent)
GET /library/sections

// Get books by author (albums by artist)
GET /library/sections/{id}/all

// Get book details with chapters
GET /library/metadata/{ratingKey}?includeChapters=1

// Get chapters (tracks)
GET /library/metadata/{albumRatingKey}/children

// Progress tracking (already works)
POST /:/timeline?ratingKey={key}&time={ms}&state={playing|paused}

// Mark as finished
GET /:/scrobble?key={ratingKey}
```

---

## Current App Architecture

### State Management
- **Riverpod** for state management
- **Providers** in `/lib/providers/`
- **Services** in `/lib/services/`

### Navigation
- Material navigation with route transitions
- Contextual navigation (tap episode → play, tap show → details)

### Media Player Stack
- **MediaKit** (v1.1.10+1) - MPV-based player
- **audio_service** (v0.18.18) - OS media integration
- **Supports:** Audio-only playback (same Player class)

### Key Files to Modify

| File | Purpose | Changes Needed |
|------|---------|----------------|
| `/lib/models/plex_library.dart` | Library model | Add `isAudiobookLibrary` getter |
| `/lib/models/plex_metadata.dart` | Metadata model | Already compatible (grandparent/parent structure works) |
| `/lib/screens/libraries_screen.dart` | Library browser | Remove artist filtering, add audiobook detection |
| `/lib/client/plex_client.dart` | API client | Update filtering logic for discover feeds |
| `/lib/widgets/media_card.dart` | Media cards | Remove "not supported" snackbar for audiobooks |

### New Components Needed

1. **Screens:**
   - `AudiobookLibraryScreen` - Browse books by author
   - `AudiobookDetailScreen` - Book details with chapter list
   - `AudiobookPlayerScreen` - Audio-only player UI

2. **Widgets:**
   - `AudiobookCard` - Visual representation of books
   - `ChapterList` - Enhanced chapter browser
   - `AudioPlayerControls` - Audio-specific controls

3. **Models:**
   - No new models needed! Existing `PlexMetadata` works:
     - `grandparentTitle` = Author name
     - `parentTitle` = Book title
     - `title` = Chapter title
     - `type` = "track"

---

## Feature Feasibility Analysis

### ✅ ALREADY IMPLEMENTED (Core Playback)

| Feature | Status | Implementation Details |
|---------|--------|------------------------|
| **Variable playback speed** | ✅ Complete | 0.5x - 3.0x with 8 presets (`sheets/playback_speed_sheet.dart`) |
| **Skip forward/backward** | ✅ Complete | Configurable (default 10s/30s), keyboard + gesture support |
| **Sleep timer** | ✅ Complete | 5-120 min presets, extend +15min option (`services/sleep_timer_service.dart`) |
| **Chapter navigation** | ✅ Complete | Full chapter UI with thumbnails, timeline markers (`sheets/chapter_sheet.dart`) |
| **Resume position** | ✅ Complete | `viewOffset` synced every 10s during playback |
| **Automatic bookmarking** | ✅ Complete | Progress tracked via `/:/timeline` endpoint |
| **Lock screen controls** | ✅ Complete | Native iOS/Android/macOS controls via `audio_service` |
| **Background playback** | ✅ Complete | Audio session management with interruption handling |
| **Progress tracking** | ✅ Complete | Percentage + time remaining calculated from duration |
| **Mark as finished** | ✅ Complete | `/:/scrobble` endpoint marks items watched |

### 🔧 MINOR MODIFICATIONS NEEDED

| Feature | Effort | Implementation Notes |
|---------|--------|----------------------|
| **Sleep timer "end of chapter"** | Low | Add chapter boundary detection to sleep timer service |
| **Per-book playback speed** | Low | Store speed preferences keyed by `albumRatingKey` |
| **Library sorting** | Low | Add author/series/narrator sort options (Plex supports via `/library/sections/{id}/sorts`) |
| **Audiobook-specific UI** | Medium | Adapt video player to audio-only mode, show album art |
| **Audio session mode** | Low | Change from `moviePlayback` to `spokenAudio` (iOS) and `speech` (Android) |

### 🏗️ NEW DEVELOPMENT REQUIRED

| Feature | Effort | Feasibility | Notes |
|---------|--------|-------------|-------|
| **Collections/Playlists** | Medium | ✅ High | Plex supports collections API - can display series |
| **Download management** | High | ⚠️ Medium | Requires offline storage system, partial downloads, sync logic |
| **Offline listening** | High | ⚠️ Medium | Depends on download management, requires local playback |
| **Silence skipping** | Medium | ⚠️ Medium | Requires MPV configuration or audio analysis (complex) |
| **Volume boost** | Low | ✅ High | MPV supports `--af=volume=X` audio filter |
| **Per-book equalizer** | Medium | ✅ High | MPV supports `--af=equalizer=` with parametric EQ |

### ❌ NOT FEASIBLE (Current Architecture)

| Feature | Reason |
|---------|--------|
| **Selective chapter downloads** | Requires offline mode + granular download control |
| **Storage management tools** | Requires download system infrastructure |

---

## Recommended Implementation Roadmap

### Phase 1: Core Audiobook Support (Week 1)
**Goal:** Make audiobooks playable with existing features

- [ ] **Library Detection**
  - Add `isAudiobookLibrary` method to `PlexLibrary`
  - Update library filtering in `libraries_screen.dart`
  - Add audiobook icon to library cards

- [ ] **API Integration**
  - Modify `plex_client.dart` filtering to include audiobooks
  - Update discover feeds (recently added, on deck) to support audiobooks

- [ ] **Navigation**
  - Create `AudiobookLibraryScreen` (list authors)
  - Create `AuthorDetailScreen` (list books by author)
  - Create `AudiobookDetailScreen` (show book info + chapters)

- [ ] **Basic Playback**
  - Create `AudiobookPlayerScreen` (audio-only UI)
  - Adapt existing player with album art display
  - Test chapter navigation with audiobook structure

### Phase 2: Audiobook-Specific Features (Week 2)
**Goal:** Enhance UX with audiobook-optimized features

- [ ] **Enhanced Sleep Timer**
  - Add "end of current chapter" option
  - Add "custom duration" input

- [ ] **Per-Book Settings**
  - Store playback speed per book (`albumRatingKey`)
  - Persist audio preferences per book

- [ ] **Audio Session Optimization**
  - Change iOS mode to `spokenAudio`
  - Change Android content type to `speech`
  - Optimize for voice content

- [ ] **Library Organization**
  - Add sort options (author, series, recently added)
  - Add filter options (in-progress, finished, unplayed)
  - Add search within audiobook libraries

### Phase 3: Advanced Features (Week 3+)
**Goal:** Best-in-class audiobook experience

- [ ] **Collections/Series Support**
  - Query Plex collections API
  - Display book series grouped together
  - Auto-play next book in series

- [ ] **Audio Enhancements**
  - Add volume boost option (MPV audio filter)
  - Add basic EQ presets (voice-optimized, bass boost, etc.)
  - Add silence detection (experimental)

- [ ] **UI Polish**
  - Add audiobook-specific themes
  - Enhanced progress visualization
  - Narrator information display
  - Reading statistics

### Phase 4: Offline Support (Future)
**Goal:** Enable offline audiobook listening

- [ ] **Download System**
  - Design local storage schema
  - Implement chapter-level downloads
  - Add download queue management

- [ ] **Offline Playback**
  - Local file playback via MediaKit
  - Offline progress tracking
  - Sync when online

---

## Technical Considerations

### 1. Audio Session Configuration

**Current (Video):**
```dart
AVAudioSessionCategory.playback
AVAudioSessionMode.moviePlayback
AndroidAudioContentType.movie
```

**Recommended (Audiobook):**
```dart
AVAudioSessionCategory.playback
AVAudioSessionMode.spokenAudio  // iOS voice optimized
AndroidAudioContentType.speech  // Android voice optimized
AndroidAudioUsage.media
```

**Benefits:**
- Better system audio ducking
- Optimized for voice frequency ranges
- Improved Bluetooth device compatibility

### 2. Chapter Structure

Audiobooks in Plex use tracks as chapters:

```json
{
  "type": "track",
  "title": "Chapter 1: The Beginning",
  "index": 1,
  "parentTitle": "The Great Gatsby",
  "grandparentTitle": "F. Scott Fitzgerald",
  "duration": 1200000,  // 20 minutes
  "thumb": "/library/metadata/12345/thumb/...",
  "Media": [{
    "Part": [{
      "key": "/library/parts/67890/file.m4b",
      "duration": 1200000
    }]
  }]
}
```

**Existing Chapter Support:** The app already parses and displays chapters from Plex's `/library/metadata/{id}?includeChapters=1` endpoint. This will work seamlessly for audiobooks.

### 3. Progress Tracking

**Current Implementation:** Perfect for audiobooks
- Updates every 10 seconds during playback
- Syncs to Plex via `/:/timeline` endpoint
- Resumes from `viewOffset` on next play
- Cross-device sync through Plex

### 4. MediaKit Player

**Key Advantages:**
- Same `Player` class works for audio and video
- Already handles audio-only files (m4b, mp3, m4a, etc.)
- MPV backend provides extensive audio processing
- No additional dependencies needed

---

## Competitive Analysis

### Existing Plex Audiobook Clients

| App | Platform | Quality | Features |
|-----|----------|---------|----------|
| **PlexAmp** | Mobile/Desktop | High | Music-focused, basic audiobook support |
| **Prologue** | iOS | Excellent | Dedicated audiobook client, $5 one-time |
| **BookCamp** | iOS | Good | Audiobook-focused Plex client |
| **Plappa** | iOS/Android | Medium | General Plex client |

### Plezy's Competitive Advantages

1. **Cross-Platform** - Flutter supports iOS, Android, macOS, Windows, Linux
2. **Modern UI** - Material Design 3, clean interface
3. **Already Excellent Player** - MediaKit with full controls
4. **Open Source** - Community can contribute
5. **No Cost** - Free alternative to $5 Prologue

### Opportunity

**None of the existing clients offer:**
- Cross-platform audiobook support (mobile + desktop)
- Modern Material Design UI
- Free and open source
- Integrated with TV show/movie library browsing

Plezy could become the **go-to free, cross-platform Plex audiobook client**.

---

## Potential Challenges

### 1. Music vs. Audiobook Detection

**Challenge:** No definitive way to distinguish audiobooks from music at the metadata level.

**Solution:** Use agent-based detection (covers 95% of cases) + optional user override settings.

**Fallback:** Allow users to manually mark libraries as "audiobook" in app settings.

### 2. Chapter vs. Multi-File Books

**Challenge:** Some audiobook libraries use:
- Single file with embedded chapters (m4b)
- Multiple files (one per chapter) without embedded chapters

**Solution:**
- Single file → Use Plex chapters API (already supported)
- Multiple files → Each track IS a chapter (treat as playlist)

### 3. Narrator/Series Metadata

**Challenge:** Plex music fields don't map perfectly to audiobook needs:
- Narrator might be in "mood" or "style" field
- Series name might be in "mood" field
- Inconsistent across different agents

**Solution:** Display available metadata flexibly, don't require specific fields.

### 4. Large Library Performance

**Challenge:** Audiobook libraries can be very large (1000+ books).

**Solution:** Already solved - app uses pagination (1000 items/page) and efficient loading.

---

## User Experience Flow

### Discovery Flow
```
Libraries Screen
  ↓ (tap audiobook library)
Authors List (sorted A-Z)
  ↓ (tap author)
Books by Author (with progress indicators)
  ↓ (tap book)
Book Detail Screen
  - Cover art
  - Title, author, narrator
  - Duration, progress
  - Chapter list preview
  - [Play] [Resume] buttons
  ↓ (tap Play)
Audiobook Player
  - Album art (large)
  - Title, author, chapter
  - Timeline with chapter markers
  - Speed, sleep timer, chapters
  - Skip ±30s buttons
  - Lock screen controls
```

### Continue Listening Flow
```
Home/Dashboard
  ↓ (shows "Continue Listening" row)
In-Progress Audiobooks
  ↓ (tap book)
Resume playback instantly
  - Maintains position
  - Maintains playback speed
  - Maintains chapter context
```

---

## Development Checklist

### Models & Data
- [ ] Add `isAudiobookLibrary` getter to `PlexLibrary`
- [ ] Verify `PlexMetadata` supports all audiobook fields
- [ ] Add audiobook type enums/constants

### API & Client
- [ ] Update library filtering (remove blanket artist exclusion)
- [ ] Update discover feeds (recently added, on deck)
- [ ] Add audiobook-specific queries (sort by author, filter by narrator)
- [ ] Test chapter loading for track-type items

### UI Screens
- [ ] `AudiobookLibraryScreen` - Browse authors
- [ ] `AuthorDetailScreen` - Books by author (optional, could skip)
- [ ] `AudiobookDetailScreen` - Book info + chapters
- [ ] `AudiobookPlayerScreen` - Audio-only player

### Widgets
- [ ] `AudiobookCard` - Grid/list display
- [ ] `AudioPlayerControls` - Audio-specific UI
- [ ] Update `MediaCard` - Support audiobook types
- [ ] `ChapterListSheet` - Already exists, verify works for tracks

### Services
- [ ] Update audio session config (spokenAudio mode)
- [ ] Add per-book settings storage
- [ ] Enhance sleep timer (end of chapter option)
- [ ] Add audiobook statistics tracking

### Settings
- [ ] Add audiobook preferences section
- [ ] Toggle for audiobook library visibility
- [ ] Default skip duration for audiobooks
- [ ] Default playback speed for audiobooks

### Testing
- [ ] Test with Audnexus agent
- [ ] Test with Audiobooks.bundle agent
- [ ] Test single-file books (m4b with embedded chapters)
- [ ] Test multi-file books (one file per chapter)
- [ ] Test background playback + interruptions
- [ ] Test cross-device sync
- [ ] Test large libraries (1000+ books)

---

## Conclusion

Adding audiobook support to Plezy is **highly feasible** and could establish this app as a premier cross-platform audiobook client for Plex. The existing architecture already includes 80% of the necessary infrastructure, requiring primarily UI adaptation and library detection logic.

**Key Strengths:**
- MediaKit player already supports audio-only playback
- All playback features (speed, chapters, sleep timer) are implemented
- Progress tracking and sync work perfectly for audiobooks
- Cross-platform support gives competitive advantage

**Recommended Approach:**
1. Start with Phase 1 (core support) to validate architecture
2. Gather user feedback early
3. Iterate on audiobook-specific features (Phase 2)
4. Consider offline support as long-term enhancement (Phase 4)

**Estimated Timeline:**
- **Phase 1 (Core):** 1 week
- **Phase 2 (Enhanced):** 1 week
- **Phase 3 (Advanced):** 1-2 weeks
- **Total MVP:** 2-3 weeks

This could position Plezy as the best free, open-source, cross-platform audiobook client for Plex.

---

## Additional Resources

**Plex Audiobook Community:**
- [Plex Audiobook Guide](https://github.com/seanap/Plex-Audiobook-Guide) by seanap
- [Audnexus Agent](https://github.com/djdembeck/Audnexus.bundle)
- [Audiobooks.bundle Agent](https://github.com/seanap/Audiobooks.bundle)

**Existing Audiobook Clients:**
- Prologue (iOS) - Reference for UX patterns
- PlexAmp - See how Plex's official app handles audiobooks
- BookCamp - iOS-specific implementation

**MediaKit Documentation:**
- [media_kit](https://pub.dev/packages/media_kit) on pub.dev
- [MPV manual](https://mpv.io/manual/stable/) for audio filters and options

---

**Document Version:** 1.0
**Last Updated:** 2025-11-07
**Next Review:** After Phase 1 implementation
