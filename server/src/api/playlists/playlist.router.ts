import { Router, Response } from 'express';
import { AccountPreController } from '../accounts/account.pre.controller';
import { IPreAccountRequest } from '../accounts/account.pre.model';
import { PlaylistDb } from '../../database/playlist.db';

function toJson(obj: unknown): unknown {
	return JSON.parse(JSON.stringify(obj, (_key, value) =>
		typeof value === 'bigint' ? Number(value) : value,
	));
}

export const playlistRouter = Router({ mergeParams: true })
	/**
	 * @openapi
	 * /playlists:
	 *   get:
	 *     tags: [Playlists]
	 *     summary: List playlists accessible to the logged-in user
	 *     security:
	 *       - accessTokenHeader: []
	 *       - cookieAuth: []
	 *     responses:
	 *       200:
	 *         description: Accessible playlists with their track ids
	 *         content:
	 *           application/json:
	 *             schema:
	 *               type: object
	 *               properties:
	 *                 success: { type: boolean, example: true }
	 *                 data:
	 *                   type: array
	 *                   items: { $ref: '#/components/schemas/Playlist' }
	 *       400: { $ref: '#/components/responses/AuthError' }
	 */
	.get(
		'/',
		AccountPreController.parseTokenCookie,
		async (req: IPreAccountRequest, res: Response) => {
			const playlists = await PlaylistDb.getAccessible(req.accountId);
			const withMusicIds = await Promise.all(
				playlists.map(async (p) => ({
					...p,
					track_count: Number(p.track_count),
					music_ids: await PlaylistDb.getMusicIds(p.id),
				})),
			);
			res.json({ success: true, data: toJson(withMusicIds) });
		},
	)
	/**
	 * @openapi
	 * /playlists:
	 *   post:
	 *     tags: [Playlists]
	 *     summary: Create a playlist
	 *     security:
	 *       - accessTokenHeader: []
	 *       - cookieAuth: []
	 *     requestBody:
	 *       required: true
	 *       content:
	 *         application/json:
	 *           schema:
	 *             type: object
	 *             required: [name]
	 *             properties:
	 *               name: { type: string }
	 *               isPublic: { type: boolean, default: true }
	 *     responses:
	 *       200:
	 *         description: Created playlist
	 *         content:
	 *           application/json:
	 *             schema:
	 *               type: object
	 *               properties:
	 *                 success: { type: boolean, example: true }
	 *                 data: { $ref: '#/components/schemas/Playlist' }
	 *       400:
	 *         description: Name is missing
	 *         content:
	 *           application/json:
	 *             schema: { $ref: '#/components/schemas/ErrorResponse' }
	 *       500:
	 *         description: Creation failed
	 *         content:
	 *           application/json:
	 *             schema: { $ref: '#/components/schemas/ErrorResponse' }
	 */
	.post(
		'/',
		AccountPreController.parseTokenCookie,
		async (req: IPreAccountRequest, res: Response) => {
			const { name, isPublic } = req.body ?? {};
			if (!name || typeof name !== 'string') {
				res.status(400).json({ success: false, message: 'Name is required' });
				return;
			}
			const playlist = await PlaylistDb.create(
				name.trim(),
				req.accountId,
				isPublic !== false,
			);
			if (!playlist) {
				res.status(500).json({ success: false, message: 'Failed to create playlist' });
				return;
			}
			res.json({ success: true, data: toJson({ ...playlist, track_count: 0, music_ids: [] }) });
		},
	)
	/**
	 * @openapi
	 * /playlists/{id}/tracks:
	 *   post:
	 *     tags: [Playlists]
	 *     summary: Add a music to a playlist
	 *     security:
	 *       - accessTokenHeader: []
	 *       - cookieAuth: []
	 *     parameters:
	 *       - name: id
	 *         in: path
	 *         required: true
	 *         schema: { type: integer }
	 *     requestBody:
	 *       required: true
	 *       content:
	 *         application/json:
	 *           schema:
	 *             type: object
	 *             required: [musicId]
	 *             properties:
	 *               musicId: { type: integer }
	 *     responses:
	 *       200:
	 *         description: Track added
	 *         content:
	 *           application/json:
	 *             schema:
	 *               type: object
	 *               properties:
	 *                 success: { type: boolean, example: true }
	 *       400:
	 *         description: Invalid playlist or music id
	 *         content:
	 *           application/json:
	 *             schema: { $ref: '#/components/schemas/ErrorResponse' }
	 *       403:
	 *         description: Not allowed to edit this playlist
	 *         content:
	 *           application/json:
	 *             schema: { $ref: '#/components/schemas/ErrorResponse' }
	 */
	.post(
		'/:id/tracks',
		AccountPreController.parseTokenCookie,
		async (req: IPreAccountRequest, res: Response) => {
			const playlistId = Number(req.params.id);
			const { musicId } = req.body ?? {};
			if (!Number.isInteger(playlistId) || !Number.isInteger(musicId)) {
				res.status(400).json({ success: false, message: 'Invalid playlist or music id' });
				return;
			}
			const canEdit = await PlaylistDb.canEdit(playlistId, req.accountId);
			if (!canEdit) {
				res.status(403).json({ success: false, message: 'Not authorized' });
				return;
			}
			await PlaylistDb.addTrack(playlistId, musicId);
			res.json({ success: true, data: null });
		},
	);
