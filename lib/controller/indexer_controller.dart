import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:get/get.dart';
import 'package:on_audio_edit/on_audio_edit.dart' as audioedit;
import 'package:on_audio_query/on_audio_query.dart';

import 'package:namida/class/folder.dart';
import 'package:namida/class/group.dart';
import 'package:namida/class/track.dart';
import 'package:namida/controller/delete_controller.dart';
import 'package:namida/controller/folders_controller.dart';
import 'package:namida/controller/json_to_history_parser.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/functions.dart';

class Indexer extends GetxController {
  static final Indexer inst = Indexer();

  final RxBool isIndexing = false.obs;

  final RxInt allTracksPaths = 0.obs;
  final RxList<FileSystemEntity> tracksFileSystemEntity = <FileSystemEntity>[].obs;
  final RxInt filteredForSizeDurationTracks = 0.obs;
  final RxInt duplicatedTracksLength = 0.obs;
  final Set<String> filteredPathsToBeDeleted = {};

  final RxInt artworksInStorage = Directory(k_DIR_ARTWORKS).listSync().length.obs;
  final RxInt waveformsInStorage = Directory(k_DIR_WAVEFORMS).listSync().length.obs;
  final RxInt colorPalettesInStorage = Directory(k_DIR_PALETTES).listSync().length.obs;
  final RxInt videosInStorage = Directory(k_DIR_VIDEOS_CACHE).listSync().length.obs;

  final RxInt artworksSizeInStorage = 0.obs;
  final RxInt waveformsSizeInStorage = 0.obs;
  final RxInt videosSizeInStorage = 0.obs;

  final TextEditingController globalSearchController = TextEditingController();
  final TextEditingController tracksSearchController = TextEditingController();
  final TextEditingController albumsSearchController = TextEditingController();
  final TextEditingController artistsSearchController = TextEditingController();
  final TextEditingController genresSearchController = TextEditingController();

  final RxList<Track> tracksInfoList = <Track>[].obs;
  final RxList<Group> albumsList = <Group>[].obs;
  final RxList<Group> groupedArtistsList = <Group>[].obs;
  final RxList<Group> groupedGenresList = <Group>[].obs;
  final RxList<Folder> groupedFoldersList = <Folder>[].obs;

  final RxList<Track> trackSearchList = <Track>[].obs;
  final RxList<Group> albumSearchList = <Group>[].obs;
  final RxList<Group> artistSearchList = <Group>[].obs;
  final RxList<Group> genreSearchList = <Group>[].obs;

  /// Temporary lists.
  final RxList<Track> trackSearchTemp = <Track>[].obs;
  final RxList<Group> albumSearchTemp = <Group>[].obs;
  final RxList<Group> artistSearchTemp = <Group>[].obs;

  final OnAudioQuery _query = OnAudioQuery();
  final onAudioEdit = audioedit.OnAudioEdit();

  Future<void> prepareTracksFile() async {
    /// Only awaits if the track file exists, otherwise it will get into normally and start indexing.
    if (await File(k_FILE_PATH_TRACKS).exists() && await File(k_FILE_PATH_TRACKS).stat().then((value) => value.size > 8)) {
      await readTrackData();
      afterIndexing();
    }

    /// doesnt exists
    else {
      await File(k_FILE_PATH_TRACKS).create();
      refreshLibraryAndCheckForDiff(forceReIndex: true);
    }
  }

  Future<void> refreshLibraryAndCheckForDiff({bool forceReIndex = false}) async {
    isIndexing.value = true;
    final files = await getAudioFiles();

    Set<String> newFoundPaths = files.difference(Set.of(tracksInfoList.map((t) => t.path)));
    Set<String> deletedPaths = Set.of(tracksInfoList.map((t) => t.path)).difference(files);

    await fetchAllSongsAndWriteToFile(audioFiles: newFoundPaths, deletedPaths: deletedPaths, forceReIndex: forceReIndex || tracksInfoList.isEmpty);
    isIndexing.value = false;
  }

  void afterIndexing() {
    albumsList.clear();
    groupedArtistsList.clear();
    groupedGenresList.clear();
    groupedFoldersList.clear();

    // albumsList.assignAll(tracksInfoList.groupBy((t) => t.album).entries.map((e) => Group(e.key, e.value)));
    // final allartists = tracksInfoList.expand((element) => element.artistsList).toList();
    // groupedArtistsList.assignAll(tracksInfoList.groupBy((t) => allartists).entries.map((e) => Group(e.key, e.value)));

    for (Track tr in tracksInfoList) {
      /// Assigning Albums
      final album = albumsList.firstWhereOrNull((element) => element.name == tr.album);
      if (album == null) {
        albumsList.add(Group(tr.album, [tr]));
      } else {
        album.tracks.add(tr);
      }
      album?.tracks.sort((a, b) => a.title.compareTo(b.title));

      /// Assigning Artist
      for (final artist in tr.artistsList) {
        final art = groupedArtistsList.firstWhereOrNull((element) => element.name == artist);
        if (art == null) {
          groupedArtistsList.add(Group(artist, [tr]));
        } else {
          art.tracks.add(tr);
        }
        art?.tracks.sort((a, b) => a.title.compareTo(b.title));
      }

      /// Assigning Genres
      for (final genre in tr.genresList) {
        final gen = groupedGenresList.firstWhereOrNull((element) => element.name == genre);
        if (gen == null) {
          groupedGenresList.add(Group(genre, [tr]));
        } else {
          gen.tracks.add(tr);
        }
        gen?.tracks.sort((a, b) => a.title.compareTo(b.title));
      }

      /// Assigning Folders
      final folder = groupedFoldersList.firstWhereOrNull((element) => element.path == tr.folderPath);
      if (folder == null) {
        groupedFoldersList.add(Folder(tr.folderPath.split('/').length, tr.folderPath.split('/').last, tr.folderPath, [tr]));
      } else {
        folder.tracks.add(tr);
      }
      Folders.inst.sortFolderTracks();
    }

    sortTracks();
    sortAlbums();
    sortArtists();
    sortGenres();
  }

  /// extracts artwork from [bytes] or [path] and save to file.
  /// path is needed bothways for making the file name.
  /// using path for extracting will call [onAudioEdit.readAudio] so it will be slower.
  Future<void> extractOneArtwork(String path, {Uint8List? bytes, bool forceReExtract = false}) async {
    final fileOfFull = File("$k_DIR_ARTWORKS${path.getFilename}.png");

    if (forceReExtract) {
      await fileOfFull.delete();
    }

    /// prevent redundent re-creation of image file
    if (!await fileOfFull.exists()) {
      final art = bytes ?? await onAudioEdit.readAudio(path).then((value) => value.firstArtwork);
      if (art != null) {
        final imgFile = await fileOfFull.create(recursive: true);
        imgFile.writeAsBytesSync(art);
      }
    }

    updateImageSizeInStorage();
  }

  Future<void> updateTracks(List<Track> tracks, {bool updateArtwork = false}) async {
    for (final track in tracks) {
      await fetchAllSongsAndWriteToFile(audioFiles: {}, deletedPaths: {track.path}, forceReIndex: false);
      await fetchAllSongsAndWriteToFile(audioFiles: {track.path}, deletedPaths: {}, forceReIndex: false);
      if (updateArtwork) {
        await DeleteController.inst.deleteArtwork(tracks);
        await extractOneArtwork(track.path, forceReExtract: true);
      }
    }

    afterIndexing();
  }

  Map<String?, Set<Track>> getAlbumsForArtist(String artist) {
    Map<String?, Set<Track>> trackAlbumsMap = {};
    for (Track track in tracksInfoList) {
      if (track.artistsList.contains(artist)) {
        trackAlbumsMap.putIfAbsent(track.album, () => {}).addIf(() {
          /// a check to not add tracks with the same filename to the album
          return !(trackAlbumsMap[track.album] ?? {}).map((e) => e.filename).contains(track.filename);
        }, track);
      }
    }
    return trackAlbumsMap;
  }

  Future<void> fetchAllSongsAndWriteToFile({required Set<String> audioFiles, required Set<String> deletedPaths, bool forceReIndex = true}) async {
    if (forceReIndex) {
      debugPrint(tracksInfoList.length.toString());
      tracksInfoList.clear();
      audioFiles = await getAudioFiles();
    } else {
      audioFiles = audioFiles;
    }
    debugPrint("New Audio Files: ${audioFiles.length}");
    debugPrint("Deleted Audio Files: ${deletedPaths.length}");

    List<AudioModel> tracksOld = await _query.querySongs();
    filteredForSizeDurationTracks.value = 0;
    duplicatedTracksLength.value = 0;
    final minDur = SettingsController.inst.indexMinDurationInSec.value; // Seconds
    final minSize = SettingsController.inst.indexMinFileSizeInB.value; // bytes

    Future<void> extractAllMetadata() async {
      Set<String> listOfCurrentFileNames = <String>{};
      for (final trackPath in audioFiles) {
        printInfo(info: trackPath);
        try {
          /// skip duplicated tracks according to filename
          if (SettingsController.inst.preventDuplicatedTracks.value && listOfCurrentFileNames.contains(trackPath.getFilename)) {
            duplicatedTracksLength.value++;
            continue;
          }

          final trackInfo = await onAudioEdit.readAudio(trackPath);

          /// Since duration & dateAdded can't be accessed using [onAudioEdit] (jaudiotagger), im using [onAudioQuery] to access it
          int? duration;
          // int? dateAdded;
          for (final h in tracksOld) {
            if (h.data == trackPath) {
              duration = h.duration;
              // dateAdded = h.dateAdded;
            }
          }
          final fileStat = await File(trackPath).stat();

          // breaks the loop early depending on size [byte] or duration [seconds]
          if ((duration ?? 999999) < minDur * 1000 || fileStat.size < minSize) {
            filteredForSizeDurationTracks.value++;
            filteredPathsToBeDeleted.add(trackPath);
            deletedPaths.add(trackPath);
            continue;
          }

          /// Split Artists
          final artists = splitBySeparators(
              trackInfo.artist, SettingsController.inst.trackArtistsSeparators.toList(), 'Unkown Artist', SettingsController.inst.trackArtistsSeparatorsBlacklist.toList());

          /// Split Genres
          final genres = splitBySeparators(
              trackInfo.genre, SettingsController.inst.trackGenresSeparators.toList(), 'Unkown Genre', SettingsController.inst.trackGenresSeparatorsBlacklist.toList());

          Track newTrackEntry = Track(
            trackInfo.title ?? '',
            artists,
            trackInfo.album ?? 'Unknown Album',
            trackInfo.albumArtist ?? '',
            genres,
            trackInfo.composer ?? 'Unknown Composer',
            trackInfo.track ?? 0,
            duration ?? 0,
            int.tryParse((trackInfo.year ?? '').cleanUpForComparison) ?? 0,
            fileStat.size,
            //TODO(MSOB7YY): REMOVE CREATION DATE
            fileStat.accessed.millisecondsSinceEpoch,
            fileStat.changed.millisecondsSinceEpoch,
            trackPath,
            trackInfo.getMap['COMMENT'] ?? '',
            trackInfo.bitrate ?? 0,
            trackInfo.sampleRate ?? 0,
            trackInfo.format ?? '',
            trackInfo.channels ?? '',
            trackInfo.discNo ?? 0,
            trackInfo.language ?? '',
            trackInfo.lyrics ?? '',
            trackInfo.mood ?? '',
          );
          tracksInfoList.add(newTrackEntry);

          debugPrint(tracksInfoList.length.toString());

          listOfCurrentFileNames.add(trackPath.getFilename);
          searchTracks('');
          extractOneArtwork(trackPath, bytes: trackInfo.firstArtwork);
        } catch (e) {
          printError(info: e.toString());

          /// TODO(MSOB7YY): Should i add a dummy track that has a real path?
          // final fileStat = await File(track).stat();
          // tracksInfoList.add(Track(p.basenameWithoutExtension(track), ['Unkown Artist'], 'Unkown Album', 'Unkown Album Artist', ['Unkown Genre'], 'Unknown Composer', 0, 0, 0, fileStat.size, fileStat.accessed.millisecondsSinceEpoch, fileStat.changed.millisecondsSinceEpoch, track,
          //     "$k_DIR_USER_DATA/Artworks/${p.basename(track)}.png", p.dirname(track), p.basename(track), p.basenameWithoutExtension(track), p.extension(track).substring(1), '', 0, 0, '', '', 0, '', '', '', ''));

          continue;
        }
      }
      debugPrint('Extracted All Metadata');
    }

    if (deletedPaths.isEmpty) {
      await extractAllMetadata();
    } else {
      for (final p in deletedPaths) {
        tracksInfoList.removeWhere((track) => track.path == p);
      }
    }

    /// removes tracks after increasing duration
    tracksInfoList.removeWhere((tr) => tr.duration < minDur * 1000 || tr.size < minSize);

    /// removes duplicated tracks after a refresh
    if (SettingsController.inst.preventDuplicatedTracks.value) {
      Set<String> listOfCurrentFileNames = <String>{};
      final listOfTracksWithoutDuplicates = <Track>[];
      for (final tr in tracksInfoList) {
        if (!listOfCurrentFileNames.contains(tr.filename)) {
          listOfTracksWithoutDuplicates.add(tr);
          listOfCurrentFileNames.add(tr.filename);
        } else {
          duplicatedTracksLength.value++;
        }
      }
      tracksInfoList.assignAll(listOfTracksWithoutDuplicates);
    }

    afterIndexing();

    printInfo(info: "FINAL: ${tracksInfoList.length}");

    tracksInfoList.map((track) => track.toJson()).toList();
    await File(k_FILE_PATH_TRACKS).writeAsString(json.encode(tracksInfoList));

    /// Creating Default Artwork
    if (!await File(k_FILE_PATH_NAMIDA_LOGO).exists()) {
      ByteData byteData = await rootBundle.load('assets/namida_icon.png');
      File file = await File(k_FILE_PATH_NAMIDA_LOGO).create(recursive: true);
      await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
  }

  Future<void> readTrackData() async {
    final jsonResponse = await JsonToHistoryParser.inst.readJSONFile(k_FILE_PATH_TRACKS);

    if (jsonResponse != null) {
      for (final p in jsonResponse) {
        tracksInfoList.add(Track.fromJson(p));
        debugPrint("Tracks Info List Length From File: ${tracksInfoList.length}");
      }
    }
  }

  List<String> splitBySeparators(String? string, Iterable<String> separators, String fallback, List<String> blacklist) {
    final List<String> finalStrings = <String>[];
    final List<String> pre = string?.trim().multiSplit(separators, blacklist) ?? [fallback];
    for (final element in pre) {
      finalStrings.addIf(element != '', element.trim());
    }
    return finalStrings;
  }

  Future<Set<String>> getAudioFiles() async {
    final allPaths = <String>{};
    tracksFileSystemEntity.clear();
    for (final path in SettingsController.inst.directoriesToScan.toList()) {
      if (await Directory(path).exists()) {
        final directory = Directory(path);
        final filesPre = directory.listSync(recursive: true, followLinks: true);

        /// Respects .nomedia
        /// Typically Skips a directory if a .nomedia file was detected
        if (SettingsController.inst.respectNoMedia.value) {
          final basenames = <String>[];
          for (final b in filesPre) {
            basenames.add(b.path.split('/').last);
            printInfo(info: b.path.split('/').last);
          }
          if (basenames.contains('nomedia')) {
            printInfo(info: '.nomedia skipped');
            continue;
          }
        }

        for (final file in filesPre) {
          try {
            if (file is File) {
              for (final extension in kFileExtensions) {
                if (file.path.endsWith(extension)) {
                  // Checks if the file is not included in one of the excluded folders.
                  if (!SettingsController.inst.directoriesToExclude.toList().any((exc) => file.path.startsWith(exc))) {
                    // tracksFileSystemEntity.add(file);
                    allPaths.add(file.path);
                  }

                  break;
                }
              }
            }
            if (file is Directory) {
              if (!SettingsController.inst.directoriesToExclude.toList().any((exc) => file.path.startsWith(exc))) {
                tracksFileSystemEntity.add(file);
                debugPrint("Added $file");
                debugPrint("Added ${tracksFileSystemEntity.length}");
              }
            }
          } catch (e) {
            printError(info: e.toString());
            continue;
          }
        }
      }
      allTracksPaths.value = allPaths.length;
      debugPrint(allPaths.length.toString());
    }
    return allPaths;
  }

  void searchAll(String text) {
    searchTracks(text, temp: true);
    searchAlbums(text, temp: true);
    searchArtists(text, temp: true);
  }

  void searchTracks(String text, {bool temp = false}) {
    final finalList = temp ? trackSearchTemp : trackSearchList;
    finalList.clear();
    if (text == '') {
      if (temp) {
        trackSearchTemp.clear();
      } else {
        tracksSearchController.clear();
        trackSearchList.assignAll(tracksInfoList);
      }

      return;
    }

    final tsf = SettingsController.inst.trackSearchFilter;
    final sTitle = tsf.contains('title');
    final sAlbum = tsf.contains('album');
    final sAlbumArtist = tsf.contains('albumartist');
    final sArtist = tsf.contains('artist');
    final sGenre = tsf.contains('genre');
    final sComposer = tsf.contains('composer');
    final sYear = tsf.contains('year');

    for (final item in tracksInfoList) {
      final lctext = textCleanedForSearch(text);

      if ((sTitle && textCleanedForSearch(item.title).contains(lctext)) ||
          (sAlbum && textCleanedForSearch(item.album).contains(lctext)) ||
          (sAlbumArtist && textCleanedForSearch(item.albumArtist).contains(lctext)) ||
          (sArtist && item.artistsList.any((element) => textCleanedForSearch(element).contains(lctext))) ||
          (sGenre && item.genresList.any((element) => textCleanedForSearch(element).contains(lctext))) ||
          (sComposer && textCleanedForSearch(item.composer).contains(lctext)) ||
          (sYear && textCleanedForSearch(item.year.toString()).contains(lctext))) {
        finalList.add(item);
      }
    }
    printInfo(info: "Tracks Found: ${trackSearchList.length}");
  }

  void searchAlbums(String text, {bool temp = false}) {
    if (text == '') {
      if (temp) {
        albumSearchTemp.clear();
      } else {
        albumsSearchController.clear();
        albumSearchList.assignAll(albumsList);
      }
      return;
    }
    if (temp) {
      albumSearchTemp.assignAll(albumsList.where((al) => textCleanedForSearch(al.name).contains(textCleanedForSearch(text))));
    } else {
      albumSearchList.assignAll(albumsList.where((al) => textCleanedForSearch(al.name).contains(textCleanedForSearch(text))));
    }
  }

  void searchArtists(String text, {bool temp = false}) {
    if (text == '') {
      if (temp) {
        artistSearchTemp.clear();
      } else {
        artistsSearchController.clear();
        artistSearchList.assignAll(groupedArtistsList);
      }

      return;
    }
    if (temp) {
      artistSearchTemp.assignAll(groupedArtistsList.where((ar) => textCleanedForSearch(ar.name).contains(textCleanedForSearch(text))));
    } else {
      artistSearchList.assignAll(groupedArtistsList.where((ar) => textCleanedForSearch(ar.name).contains(textCleanedForSearch(text))));
    }
  }

  void searchGenres(String text) {
    if (text == '') {
      genresSearchController.clear();
      genreSearchList.assignAll(groupedGenresList);
      return;
    }
    genreSearchList.assignAll(groupedGenresList.where((gen) => textCleanedForSearch(gen.name).contains(textCleanedForSearch(text))));
  }

  /// Sorts Tracks and Saves automatically to settings
  void sortTracks({SortType? sortBy, bool? reverse}) {
    sortBy ??= SettingsController.inst.tracksSort.value;
    reverse ??= SettingsController.inst.tracksSortReversed.value;
    switch (sortBy) {
      case SortType.title:
        tracksInfoList.sort((a, b) => (a.title).compareTo(b.title));
        break;
      case SortType.album:
        tracksInfoList.sort((a, b) => (a.album).compareTo(b.album));
        break;
      case SortType.albumArtist:
        tracksInfoList.sort((a, b) => (a.albumArtist).compareTo(b.albumArtist));
        break;
      case SortType.year:
        tracksInfoList.sort((a, b) => (a.year).compareTo(b.year));
        break;
      case SortType.artistsList:
        tracksInfoList.sort((a, b) => (a.artistsList.toString()).compareTo(b.artistsList.toString()));
        break;
      case SortType.genresList:
        tracksInfoList.sort((a, b) => (a.genresList.toString()).compareTo(b.genresList.toString()));
        break;
      case SortType.dateAdded:
        tracksInfoList.sort((a, b) => (a.dateAdded).compareTo(b.dateAdded));
        break;
      case SortType.dateModified:
        tracksInfoList.sort((a, b) => (a.dateModified).compareTo(b.dateModified));
        break;
      case SortType.bitrate:
        tracksInfoList.sort((a, b) => (a.bitrate).compareTo(b.bitrate));
        break;
      case SortType.composer:
        tracksInfoList.sort((a, b) => (a.composer).compareTo(b.composer));
        break;
      case SortType.discNo:
        tracksInfoList.sort((a, b) => (a.discNo).compareTo(b.discNo));
        break;
      case SortType.filename:
        tracksInfoList.sort((a, b) => (a.filename).compareTo(b.filename));
        break;
      case SortType.duration:
        tracksInfoList.sort((a, b) => (a.duration).compareTo(b.duration));
        break;
      case SortType.sampleRate:
        tracksInfoList.sort((a, b) => (a.sampleRate).compareTo(b.sampleRate));
        break;
      case SortType.size:
        tracksInfoList.sort((a, b) => (a.size).compareTo(b.size));
        break;

      default:
        null;
    }

    if (reverse) {
      tracksInfoList.value = tracksInfoList.reversed.toList();
    }
    SettingsController.inst.save(tracksSort: sortBy, tracksSortReversed: reverse);
    searchTracks(tracksSearchController.value.text);
  }

  /// Sorts Albums and Saves automatically to settings
  void sortAlbums({GroupSortType? sortBy, bool? reverse}) {
    sortBy ??= SettingsController.inst.albumSort.value;
    reverse ??= SettingsController.inst.albumSortReversed.value;
    switch (sortBy) {
      case GroupSortType.album:
        albumsList.sort((a, b) => a.name.compareTo(b.name));
        break;
      case GroupSortType.albumArtist:
        albumsList.sort((a, b) => a.tracks.first.albumArtist.compareTo(b.tracks.first.albumArtist));
        break;
      case GroupSortType.year:
        albumsList.sort((a, b) => a.tracks.first.year.compareTo(b.tracks.first.year));
        break;
      case GroupSortType.artistsList:
        albumsList.sort((a, b) => a.tracks.first.artistsList.toString().compareTo(b.tracks.first.artistsList.toString()));
        break;

      case GroupSortType.composer:
        albumsList.sort((a, b) => a.tracks.first.composer.compareTo(b.tracks.first.composer));
        break;
      case GroupSortType.dateModified:
        albumsList.sort((a, b) => a.tracks.first.dateModified.compareTo(b.tracks.first.dateModified));
        break;
      case GroupSortType.duration:
        albumsList.sort((a, b) => a.tracks.toList().totalDuration.compareTo(b.tracks.toList().totalDuration));
        break;
      case GroupSortType.numberOfTracks:
        albumsList.sort((a, b) => a.tracks.length.compareTo(b.tracks.length));
        break;

      default:
        null;
    }

    if (reverse) {
      albumsList.value = albumsList.reversed.toList();
    }

    SettingsController.inst.save(albumSort: sortBy, albumSortReversed: reverse);

    searchAlbums(albumsSearchController.value.text);
  }

  /// Sorts Artists and Saves automatically to settings
  void sortArtists({GroupSortType? sortBy, bool? reverse}) {
    sortBy ??= SettingsController.inst.artistSort.value;
    reverse ??= SettingsController.inst.artistSortReversed.value;
    switch (sortBy) {
      case GroupSortType.album:
        groupedArtistsList.sort((a, b) => a.tracks.elementAt(0).album.compareTo(b.tracks.elementAt(0).album));
        break;
      case GroupSortType.albumArtist:
        groupedArtistsList.sort((a, b) => a.tracks.elementAt(0).albumArtist.compareTo(b.tracks.elementAt(0).albumArtist));
        break;
      case GroupSortType.year:
        groupedArtistsList.sort((a, b) => a.tracks.elementAt(0).year.compareTo(b.tracks.elementAt(0).year));
        break;
      case GroupSortType.artistsList:
        // mapEntries.sort((a, b) => a.tracks.elementAt(0).artistsList.toString().compareTo(b.tracks.elementAt(0).artistsList.toString()));
        groupedArtistsList.sort(((a, b) => a.name.compareTo(b.name)));
        break;
      case GroupSortType.genresList:
        groupedArtistsList.sort((a, b) => a.tracks.elementAt(0).genresList.toString().compareTo(b.tracks.elementAt(0).genresList.toString()));
        break;
      case GroupSortType.composer:
        groupedArtistsList.sort((a, b) => a.tracks.elementAt(0).composer.compareTo(b.tracks.elementAt(0).composer));
        break;
      case GroupSortType.dateModified:
        groupedArtistsList.sort((a, b) => a.tracks.elementAt(0).dateModified.compareTo(b.tracks.elementAt(0).dateModified));
        break;
      case GroupSortType.duration:
        groupedArtistsList.sort((a, b) => a.tracks.toList().totalDuration.compareTo(b.tracks.toList().totalDuration));
        break;
      case GroupSortType.numberOfTracks:
        groupedArtistsList.sort((a, b) => a.tracks.length.compareTo(b.tracks.length));
        break;
      default:
        null;
    }
    if (reverse) {
      groupedArtistsList.value = groupedArtistsList.reversed.toList();
    }

    SettingsController.inst.save(artistSort: sortBy, artistSortReversed: reverse);

    searchArtists(artistsSearchController.value.text);
  }

  /// Sorts Genres and Saves automatically to settings
  void sortGenres({GroupSortType? sortBy, bool? reverse}) {
    sortBy ??= SettingsController.inst.genreSort.value;
    reverse ??= SettingsController.inst.genreSortReversed.value;
    switch (sortBy) {
      case GroupSortType.album:
        groupedGenresList.sort((a, b) => a.tracks.elementAt(0).album.compareTo(b.tracks.elementAt(0).album));
        break;
      case GroupSortType.albumArtist:
        groupedGenresList.sort((a, b) => a.tracks.elementAt(0).albumArtist.compareTo(b.tracks.elementAt(0).albumArtist));
        break;
      case GroupSortType.year:
        groupedGenresList.sort((a, b) => a.tracks.elementAt(0).year.compareTo(b.tracks.elementAt(0).year));
        break;
      case GroupSortType.artistsList:
        groupedGenresList.sort((a, b) => a.tracks.elementAt(0).artistsList.toString().compareTo(b.tracks.elementAt(0).artistsList.toString()));
        break;
      case GroupSortType.genresList:
        groupedGenresList.sort(((a, b) => a.name.compareTo(b.name)));
        break;
      case GroupSortType.composer:
        groupedGenresList.sort((a, b) => a.tracks.elementAt(0).composer.compareTo(b.tracks.elementAt(0).composer));
        break;
      case GroupSortType.dateModified:
        groupedGenresList.sort((a, b) => a.tracks.elementAt(0).dateModified.compareTo(b.tracks.elementAt(0).dateModified));
        break;
      case GroupSortType.duration:
        groupedGenresList.sort((a, b) => a.tracks.toList().totalDuration.compareTo(b.tracks.toList().totalDuration));
        break;
      case GroupSortType.numberOfTracks:
        groupedGenresList.sort((a, b) => a.tracks.length.compareTo(b.tracks.length));
        break;

      default:
        null;
    }
    if (reverse) {
      groupedGenresList.value = groupedGenresList.reversed.toList();
    }

    SettingsController.inst.save(genreSort: sortBy, genreSortReversed: reverse);
    searchGenres(genresSearchController.value.text);
  }

  void updateImageSizeInStorage() {
    // resets values
    artworksInStorage.value = 0;
    artworksSizeInStorage.value = 0;

    Directory(k_DIR_ARTWORKS).listSync(recursive: true, followLinks: false).forEach((FileSystemEntity entity) {
      if (entity is File) {
        artworksInStorage.value++;
        artworksSizeInStorage.value += entity.lengthSync();
      }
    });
  }

  void updateWaveformSizeInStorage() {
    // resets values
    waveformsInStorage.value = 0;
    waveformsSizeInStorage.value = 0;

    Directory(k_DIR_WAVEFORMS).listSync(recursive: true, followLinks: false).forEach((FileSystemEntity entity) {
      if (entity is File) {
        waveformsInStorage.value++;
        waveformsSizeInStorage.value += entity.lengthSync();
      }
    });
  }

  void updateColorPalettesSizeInStorage() {
    // resets values
    colorPalettesInStorage.value = 0;

    Directory(k_DIR_PALETTES).listSync(recursive: true, followLinks: false).forEach((FileSystemEntity entity) {
      if (entity is File) {
        colorPalettesInStorage.value++;
      }
    });
  }

  void updateVideosSizeInStorage() {
    // resets values
    videosInStorage.value = 0;
    videosSizeInStorage.value = 0;

    Directory(k_DIR_VIDEOS_CACHE).listSync(recursive: true, followLinks: false).forEach((FileSystemEntity entity) {
      if (entity is File) {
        videosInStorage.value++;
        videosSizeInStorage.value += entity.lengthSync();
      }
    });
  }

  Future<void> clearImageCache() async {
    await Directory(k_DIR_ARTWORKS).delete(recursive: true);
    await Directory(k_DIR_ARTWORKS).create();
    updateImageSizeInStorage();
  }

  Future<void> clearWaveformData() async {
    await Directory(k_DIR_WAVEFORMS).delete(recursive: true);
    await Directory(k_DIR_WAVEFORMS).create();
    updateWaveformSizeInStorage();
  }

  /// Deletes specific videos or the whole cache.
  Future<void> clearVideoCache([List<FileSystemEntity>? videosToDelete]) async {
    if (videosToDelete != null) {
      for (final v in videosToDelete) {
        await v.delete();
      }
    } else {
      await Directory(k_DIR_VIDEOS_CACHE).delete(recursive: true);
      await Directory(k_DIR_VIDEOS_CACHE).create();
    }

    updateVideosSizeInStorage();
  }

  @override
  void onClose() {
    Get.delete();
    super.onClose();
  }
}
