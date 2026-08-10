import { accountRouter } from './accounts/account.router';
import { musicRouter } from './musics/music.router';
import { playlistRouter } from './playlists/playlist.router';
import { Router } from 'express';

export const router =
	Router({mergeParams: true})
	.use('/accounts', accountRouter)
	.use('/musics', musicRouter)
	.use('/playlists', playlistRouter)
;
