import 'package:go_router/go_router.dart';
import 'package:pmr_music_room/views/home.dart';
import 'package:pmr_music_room/views/login.dart';
import 'package:pmr_music_room/views/my_playlists.dart';
import 'package:pmr_music_room/views/now_playing.dart';
import 'package:pmr_music_room/views/profile.dart';
import 'package:pmr_music_room/views/playlist.dart';
import 'package:pmr_music_room/views/queue_view.dart';
import 'package:pmr_music_room/views/search.dart';
import 'package:pmr_music_room/views/splash.dart';
import 'package:pmr_music_room/views/track_vote.dart';
import 'package:pmr_music_room/objects/vote_event.dart';

GoRouter routes = GoRouter(
  routes: [
    GoRoute(
      path: SplashScreen.routeName,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: LoginScreen.routeName,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: HomeScreen.routeName,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: ProfileScreen.routeName,
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: SearchScreen.routeName,
      builder: (context, state) => const SearchScreen(),
    ),
    GoRoute(
      path: MyPlaylistsScreen.routeName,
      builder: (context, state) => const MyPlaylistsScreen(),
    ),
    GoRoute(
      path: PlaylistScreen.routeName,
      builder: (context, state) {
        final args = state.extra as PlaylistScreenArgs;
        return PlaylistScreen(
          title: args.title,
          subtitle: args.subtitle,
          playlistId: args.playlistId,
        );
      },
    ),
    GoRoute(
      path: NowPlayingScreen.routeName,
      builder: (context, state) => const NowPlayingScreen(),
    ),
    GoRoute(
      path: QueueView.routeName,
      builder: (context, state) => const QueueView(),
    ),
    GoRoute(
      path: TrackVoteScreen.routeName,
      builder: (context, state) => const TrackVoteScreen(),
    ),
    GoRoute(
      path: CreateVoteEventScreen.routeName,
      builder: (context, state) => const CreateVoteEventScreen(),
    ),
    GoRoute(
      path: VoteEventScreen.routeName,
      builder: (context, state) =>
          VoteEventScreen(initialEvent: state.extra as VoteEvent),
    ),
    GoRoute(
      path: VoteEventMembersScreen.routeName,
      builder: (context, state) =>
          VoteEventMembersScreen(initialEvent: state.extra as VoteEvent),
    ),
  ],
);
