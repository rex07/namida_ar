import 'package:flutter/material.dart';
import 'package:flutter_scrollbar_modified/flutter_scrollbar_modified.dart';
import 'package:get/get.dart';
import 'package:playlist_manager/module/playlist_id.dart';
import 'package:playlist_manager/playlist_manager.dart';

import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/controller/player_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/dimensions.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/namida_converter_ext.dart';
import 'package:namida/core/themes.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/ui/pages/subpages/most_played_subpage.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';
import 'package:namida/youtube/class/youtube_id.dart';
import 'package:namida/youtube/controller/youtube_history_controller.dart';
import 'package:namida/youtube/controller/youtube_playlist_controller.dart';
import 'package:namida/youtube/functions/yt_playlist_utils.dart';
import 'package:namida/youtube/pages/yt_playlist_download_subpage.dart';
import 'package:namida/youtube/widgets/yt_history_video_card.dart';
import 'package:namida/youtube/widgets/yt_thumbnail.dart';

class YTMostPlayedVideosPage extends StatelessWidget {
  const YTMostPlayedVideosPage({super.key});

  MostPlayedItemsPage getMainWidget(List<String> videos) {
    return MostPlayedItemsPage(
      itemExtents: List.filled(videos.length, Dimensions.youtubeCardItemExtent),
      historyController: YoutubeHistoryController.inst,
      customDateRange: settings.ytMostPlayedCustomDateRange,
      isTimeRangeChipEnabled: (type) => type == settings.ytMostPlayedTimeRange.value,
      onSavingTimeRange: ({dateCustom, isStartOfDay, mptr}) {
        settings.save(
          ytMostPlayedTimeRange: mptr,
          ytMostPlayedCustomDateRange: dateCustom,
          ytMostPlayedCustomisStartOfDay: isStartOfDay,
        );
      },
      header: (timeRangeChips, bottomPadding) {
        return Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: timeRangeChips,
        );
      },
      itemBuilder: (context, i, listensMap) {
        final videoID = videos[i];
        final listens = listensMap[videoID] ?? [];

        return YTHistoryVideoCard(
          key: Key("${videoID}_$i"),
          videos: videos
              .map(
                (e) => YoutubeID(
                  id: e,
                  playlistID: const PlaylistID(id: k_PLAYLIST_NAME_MOST_PLAYED),
                ),
              )
              .toList(),
          index: i,
          day: null,
          overrideListens: listens,
          playlistID: const PlaylistID(id: k_PLAYLIST_NAME_MOST_PLAYED),
          playlistName: '',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        final videos = YoutubeHistoryController.inst.currentMostPlayedTracks.toList();
        return getMainWidget(videos);
      },
    );
  }
}

class YTLikedVideosPage extends StatelessWidget {
  const YTLikedVideosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => YTNormalPlaylistSubpage(
        playlist: YoutubePlaylistController.inst.favouritesPlaylist.value,
        isEditable: false,
        reversedList: true,
      ),
    );
  }
}

class YTNormalPlaylistSubpage extends StatefulWidget {
  final GeneralPlaylist<YoutubeID> playlist;
  final bool isEditable;
  final bool reversedList;

  const YTNormalPlaylistSubpage({
    super.key,
    required this.playlist,
    this.isEditable = true,
    this.reversedList = false,
  });

  @override
  State<YTNormalPlaylistSubpage> createState() => _YTNormalPlaylistSubpageState();
}

class _YTNormalPlaylistSubpageState extends State<YTNormalPlaylistSubpage> {
  Color? bgColor;
  String playlistCurrentName = ''; // to refresh after renaming

  @override
  void initState() {
    playlistCurrentName = widget.playlist.name;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    const horizontalBigThumbPadding = 12.0;
    final bigThumbWidth = context.width - horizontalBigThumbPadding * 2;
    return AnimatedTheme(
      duration: const Duration(milliseconds: 300),
      data: AppThemes.inst.getAppTheme(bgColor, !context.isDarkMode),
      child: BackgroundWrapper(
        child: CupertinoScrollbar(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    YoutubeThumbnail(
                      width: context.width,
                      height: context.width * 9 / 16,
                      compressed: true,
                      isImportantInCache: false,
                      videoId: widget.playlist.tracks.firstOrNull?.id,
                      blur: 0.0,
                      borderRadius: 0.0,
                      extractColor: true,
                      onColorReady: (color) async {
                        if (color != null) {
                          await Future.delayed(const Duration(milliseconds: 200)); // navigation delay
                          bgColor = color.color;
                          setState(() {});
                        }
                      },
                    ),
                    const Positioned.fill(
                      child: ClipRect(
                        child: NamidaBgBlur(
                          blur: 30.0,
                          child: ColoredBox(color: Colors.transparent),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: horizontalBigThumbPadding, vertical: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          YoutubeThumbnail(
                            width: bigThumbWidth,
                            height: (bigThumbWidth * 9 / 16),
                            compressed: false,
                            isImportantInCache: true,
                            videoId: widget.playlist.tracks.firstOrNull?.id,
                            blur: 4.0,
                          ),
                          const SizedBox(height: 24.0),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      playlistCurrentName.translatePlaylistName(),
                                      style: context.textTheme.displayLarge,
                                    ),
                                    const SizedBox(height: 6.0),
                                    Text(
                                      widget.playlist.tracks.length.displayVideoKeyword,
                                      style: context.textTheme.displaySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              NamidaIconButton(
                                iconColor: context.defaultIconColor(bgColor),
                                icon: Broken.shuffle,
                                tooltip: lang.SHUFFLE,
                                onPressed: () => Player.inst.playOrPause(0, widget.playlist.tracks, QueueSource.others, shuffle: true),
                              ),
                              NamidaIconButton(
                                iconColor: context.defaultIconColor(bgColor),
                                icon: Broken.play_cricle,
                                tooltip: lang.PLAY_LAST,
                                onPressed: () => Player.inst.addToQueue(widget.playlist.tracks, insertNext: false),
                              ),
                              NamidaIconButton(
                                iconColor: context.defaultIconColor(bgColor),
                                icon: Broken.import,
                                onPressed: () async {
                                  NamidaNavigator.inst.navigateTo(
                                    YTPlaylistDownloadPage(
                                      ids: widget.playlist.tracks,
                                      playlistName: playlistCurrentName,
                                      infoLookup: const {},
                                    ),
                                  );
                                },
                              ),
                              NamidaPopupWrapper(
                                openOnLongPress: false,
                                childrenDefault: [
                                  NamidaPopupItem(icon: Broken.share, title: lang.SHARE, onTap: widget.playlist.shareVideos),
                                  if (widget.isEditable) ...[
                                    NamidaPopupItem(
                                      icon: Broken.edit_2,
                                      title: lang.RENAME_PLAYLIST,
                                      onTap: () async {
                                        playlistCurrentName = await widget.playlist.showRenamePlaylistSheet(context: context, playlistName: playlistCurrentName);
                                        setState(() {});
                                      },
                                    ),
                                    NamidaPopupItem(
                                      icon: Broken.trash,
                                      title: lang.DELETE_PLAYLIST,
                                      onTap: () => widget.playlist.promptDelete(name: playlistCurrentName, colorScheme: bgColor),
                                    ),
                                  ],
                                ],
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                  child: Icon(
                                    Broken.more_2,
                                    color: context.defaultIconColor(bgColor),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 24.0)),
              SliverFixedExtentList.builder(
                itemExtent: Dimensions.youtubeCardItemExtent,
                itemCount: widget.playlist.tracks.length,
                itemBuilder: (context, index) {
                  return YTHistoryVideoCard(
                    videos: widget.playlist.tracks,
                    index: index,
                    reversedList: widget.reversedList,
                    day: null,
                    playlistID: widget.playlist.playlistID,
                    playlistName: playlistCurrentName,
                  );
                },
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: kBottomPadding)),
            ],
          ),
        ),
      ),
    );
  }
}