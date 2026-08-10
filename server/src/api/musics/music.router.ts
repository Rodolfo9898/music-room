import { Router, Request, Response } from 'express';
import * as fs from 'node:fs';
import * as path from 'node:path';

import { MusicDb } from '../../database/music.db';

const musicsDirectory = path.resolve(__dirname, '../../../musics');

export const musicRouter = Router({mergeParams: true})
	/**
	 * @openapi
	 * /musics/genres:
	 *   get:
	 *     tags: [Musics]
	 *     summary: List selectable music genres
	 *     security: []
	 *     responses: { 200: { description: Genre records } }
	 */
	.get('/genres', async (_req: Request, res: Response) => {
		const genres = await MusicDb.getGenres();
		res.json({
			success: true,
			data: genres,
		});
	})
	/**
	 * @openapi
	 * /musics/search:
	 *   get:
	 *     tags: [Musics]
	 *     summary: Search musics by title or artist
	 *     security: []
	 *     parameters:
	 *       - name: q
	 *         in: query
	 *         required: false
	 *         description: Search text. Empty or missing returns an empty list.
	 *         schema: { type: string }
	 *     responses:
	 *       200:
	 *         description: Matching musics
	 *         content:
	 *           application/json:
	 *             schema:
	 *               type: object
	 *               properties:
	 *                 success: { type: boolean, example: true }
	 *                 data:
	 *                   type: array
	 *                   items: { $ref: '#/components/schemas/MusicSearchResult' }
	 */
	.get('/search', async (req: Request, res: Response) => {
		const q = (req.query.q as string || '').trim();
		if (!q) {
			res.json({ success: true, data: [] });
			return;
		}

		const results = await MusicDb.search(q);
		res.json({
			success: true,
			data: results.map(music => ({
				...music,
				streamUrl: `/musics/${music.id}/stream`,
			})),
		});
	})
	/**
	 * @openapi
	 * /musics:
	 *   get:
	 *     tags: [Musics]
	 *     summary: List all musics
	 *     security: []
	 *     responses:
	 *       200:
	 *         description: Full catalog, sorted by title
	 *         content:
	 *           application/json:
	 *             schema:
	 *               type: object
	 *               properties:
	 *                 success: { type: boolean, example: true }
	 *                 data:
	 *                   type: array
	 *                   items: { $ref: '#/components/schemas/Music' }
	 */
	.get('/', async (_req: Request, res: Response) => {
		const musics = await MusicDb.getAll();
		res.json({
			success: true,
			data: musics.map(music => ({
				...music,
				streamUrl: `/musics/${music.id}/stream`,
			})),
		});
	})
	/**
	 * @openapi
	 * /musics/{id}/stream:
	 *   get:
	 *     tags: [Musics]
	 *     summary: Stream the audio file of a music
	 *     security: []
	 *     description: Supports HTTP range requests for seeking (send a `Range` header to get a 206).
	 *     parameters:
	 *       - name: id
	 *         in: path
	 *         required: true
	 *         schema: { type: integer }
	 *       - name: Range
	 *         in: header
	 *         required: false
	 *         description: 'Byte range, e.g. `bytes=0-1023`'
	 *         schema: { type: string }
	 *     responses:
	 *       200:
	 *         description: Whole file
	 *         content:
	 *           audio/mpeg:
	 *             schema: { type: string, format: binary }
	 *       206:
	 *         description: Requested byte range
	 *         content:
	 *           audio/mpeg:
	 *             schema: { type: string, format: binary }
	 *       400:
	 *         description: Invalid music id
	 *         content:
	 *           application/json:
	 *             schema: { $ref: '#/components/schemas/ErrorResponse' }
	 *       404:
	 *         description: Music or audio file not found
	 *         content:
	 *           application/json:
	 *             schema: { $ref: '#/components/schemas/ErrorResponse' }
	 *       416: { description: 'Unsatisfiable byte range' }
	 */
	.get('/:id/stream', async (req: Request, res: Response) => {
		const musicId = Number(req.params.id);
		if (!Number.isInteger(musicId)) {
			res.status(400).json({success: false, message: 'Invalid music id'});
			return;
		}

		const music = await MusicDb.getById(musicId);
		if (!music) {
			res.status(404).json({success: false, message: 'Music not found'});
			return;
		}

		const filePath = path.join(musicsDirectory, path.basename(music.file_path));
		if (!fs.existsSync(filePath)) {
			res.status(404).json({success: false, message: 'Music file not found'});
			return;
		}

		const stat = fs.statSync(filePath);
		const range = req.headers.range;

		res.setHeader('Accept-Ranges', 'bytes');
		res.setHeader('Content-Type', 'audio/mpeg');

		if (!range) {
			res.setHeader('Content-Length', stat.size);
			fs.createReadStream(filePath).pipe(res);
			return;
		}

		const [startRaw, endRaw] = range.replace(/bytes=/, '').split('-');
		const start = Number.parseInt(startRaw, 10);
		const end = endRaw ? Number.parseInt(endRaw, 10) : stat.size - 1;

		if (Number.isNaN(start) || Number.isNaN(end) || start > end) {
			res.status(416).end();
			return;
		}

		res.status(206);
		res.setHeader('Content-Range', `bytes ${start}-${end}/${stat.size}`);
		res.setHeader('Content-Length', end - start + 1);
		fs.createReadStream(filePath, {start, end}).pipe(res);
	})
;
