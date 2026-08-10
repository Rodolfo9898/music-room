import { Response, Router } from 'express';
import { AccountDb } from '../../database/account.db';
import { PlaylistDb } from '../../database/playlist.db';
import { IPreAccountRequest } from './account.pre.model';
import { AccountPreController } from './account.pre.controller';

const auth = AccountPreController.parseTokenCookie;

export const accountResourcesRouter = Router({ mergeParams: true })
	/**
	 * @openapi
	 * /accounts/users/{id}/profile:
	 *   get:
	 *     tags: [Accounts]
	 *     summary: Read another user's privacy-filtered profile
	 *     parameters:
	 *       - { name: id, in: path, required: true, schema: { type: integer } }
	 *     responses:
	 *       200: { description: Public tier plus friends tier when connected; private tier only for self }
	 *       401: { $ref: '#/components/responses/AuthError' }
	 *       404: { description: User not found }
	 */
	.get('/users/:id/profile', auth, async (req: IPreAccountRequest, res: Response) => {
		const targetId = Number(req.params.id);
		if (!Number.isInteger(targetId)) return res.status(400).json({ success: false, message: 'Invalid user id' });
		const account = await AccountDb.getAccountById(targetId);
		if (!account) return res.status(404).json({ success: false, message: 'User not found' });
		const isSelf = Number(req.accountId) === targetId;
		const isFriend = isSelf || await AccountDb.areFriends(req.accountId, targetId);
		return res.json({
			success: true,
			data: {
				accountId: targetId,
				displayName: account.display_name,
				publicInfo: account.public_info ?? '',
				friendsInfo: isFriend ? account.friends_info ?? '' : null,
				privateInfo: isSelf ? account.private_info ?? '' : null,
			},
		});
	})
	/**
	 * @openapi
	 * /accounts/me/friends:
	 *   get:
	 *     tags: [Accounts]
	 *     summary: List accepted and pending friend relationships
	 *     responses: { 200: { description: Friend records } }
	 *   post:
	 *     tags: [Accounts]
	 *     summary: Request a friend by email
	 *     requestBody:
	 *       required: true
	 *       content: { application/json: { schema: { type: object, required: [email], properties: { email: { type: string, format: email } } } } }
	 *     responses: { 201: { description: Updated friend records } }
	 */
	.get('/me/friends', auth, async (req: IPreAccountRequest, res: Response) => {
		return res.json({ success: true, data: await AccountDb.listFriends(req.accountId) });
	})
	.post('/me/friends', auth, async (req: IPreAccountRequest, res: Response) => {
		const email = String(req.body?.email || '').trim().toLowerCase();
		const account = await AccountDb.getAccountByEmail(email);
		if (!account) return res.status(404).json({ success: false, message: 'User not found' });
		if (Number(account.id) === Number(req.accountId)) return res.status(400).json({ success: false, message: 'You cannot add yourself' });
		await AccountDb.requestFriend(req.accountId, Number(account.id));
		return res.status(201).json({ success: true, data: await AccountDb.listFriends(req.accountId) });
	})
	/**
	 * @openapi
	 * /accounts/me/friends/{id}/accept:
	 *   post:
	 *     tags: [Accounts]
	 *     summary: Accept an incoming friend request
	 *     parameters:
	 *       - { name: id, in: path, required: true, schema: { type: integer } }
	 *     responses: { 200: { description: Updated friend records }, 404: { description: Request not found } }
	 */
	.post('/me/friends/:id/accept', auth, async (req: IPreAccountRequest, res: Response) => {
		const requesterId = Number(req.params.id);
		if (!Number.isInteger(requesterId) || !(await AccountDb.acceptFriend(req.accountId, requesterId))) {
			return res.status(404).json({ success: false, message: 'Pending friend request not found' });
		}
		return res.json({ success: true, data: await AccountDb.listFriends(req.accountId) });
	})
	/**
	 * @openapi
	 * /accounts/me/friends/{id}:
	 *   delete:
	 *     tags: [Accounts]
	 *     summary: Remove or cancel a friend relationship
	 *     parameters:
	 *       - { name: id, in: path, required: true, schema: { type: integer } }
	 *     responses: { 200: { description: Updated friend records } }
	 */
	.delete('/me/friends/:id', auth, async (req: IPreAccountRequest, res: Response) => {
		await AccountDb.removeFriend(req.accountId, Number(req.params.id));
		return res.json({ success: true, data: await AccountDb.listFriends(req.accountId) });
	})
	/**
	 * @openapi
	 * /accounts/me/devices:
	 *   get:
	 *     tags: [Accounts]
	 *     summary: List registered account devices and permissions
	 *     responses: { 200: { description: Device records } }
	 *   post:
	 *     tags: [Accounts]
	 *     summary: Register or refresh the current device metadata
	 *     responses: { 201: { description: Device records } }
	 */
	.get('/me/devices', auth, async (req: IPreAccountRequest, res: Response) => {
		return res.json({ success: true, data: await AccountDb.listDevices(req.accountId) });
	})
	.post('/me/devices', auth, async (req: IPreAccountRequest, res: Response) => {
		const deviceKey = String(req.body?.deviceKey || '').trim();
		const name = String(req.body?.name || '').trim();
		const platform = String(req.body?.platform || '').trim();
		const appVersion = String(req.body?.appVersion || '').trim();
		if (!deviceKey || !name || !platform || !appVersion) return res.status(400).json({ success: false, message: 'Complete device metadata is required' });
		await AccountDb.registerDevice(req.accountId, deviceKey, name, platform, appVersion);
		return res.status(201).json({ success: true, data: await AccountDb.listDevices(req.accountId) });
	})
	/**
	 * @openapi
	 * /accounts/me/devices/{id}:
	 *   patch:
	 *     tags: [Accounts]
	 *     summary: Change a device's control permission
	 *     parameters:
	 *       - { name: id, in: path, required: true, schema: { type: integer } }
	 *     responses: { 200: { description: Device records }, 404: { description: Device not found } }
	 *   delete:
	 *     tags: [Accounts]
	 *     summary: Remove a registered device
	 *     parameters:
	 *       - { name: id, in: path, required: true, schema: { type: integer } }
	 *     responses: { 200: { description: Device records } }
	 */
	.patch('/me/devices/:id', auth, async (req: IPreAccountRequest, res: Response) => {
		if (typeof req.body?.canControl !== 'boolean') return res.status(400).json({ success: false, message: 'canControl must be a boolean' });
		if (!(await AccountDb.setDevicePermission(req.accountId, Number(req.params.id), req.body.canControl))) {
			return res.status(404).json({ success: false, message: 'Device not found' });
		}
		return res.json({ success: true, data: await AccountDb.listDevices(req.accountId) });
	})
	.post('/me/devices/:id/delegates/:friendId', auth, async (req: IPreAccountRequest, res: Response) => {
		const granted = await AccountDb.grantDeviceControl(req.accountId, Number(req.params.id), Number(req.params.friendId));
		if (!granted) return res.status(400).json({ success: false, message: 'The device must allow control and the delegate must be an accepted friend' });
		return res.json({ success: true, data: await AccountDb.listDevices(req.accountId) });
	})
	.delete('/me/devices/:id/delegates/:friendId', auth, async (req: IPreAccountRequest, res: Response) => {
		await AccountDb.revokeDeviceControl(req.accountId, Number(req.params.id), Number(req.params.friendId));
		return res.json({ success: true, data: await AccountDb.listDevices(req.accountId) });
	})
	.delete('/me/devices/:id', auth, async (req: IPreAccountRequest, res: Response) => {
		await AccountDb.deleteDevice(req.accountId, Number(req.params.id));
		return res.json({ success: true, data: await AccountDb.listDevices(req.accountId) });
	})
	/**
	 * @openapi
	 * /accounts/me/resources:
	 *   get:
	 *     tags: [Accounts]
	 *     summary: Get friends, accessible playlists, devices, and permissions
	 *     responses: { 200: { description: Account resources } }
	 */
	.get('/me/resources', auth, async (req: IPreAccountRequest, res: Response) => {
		return res.json({ success: true, data: {
			friends: await AccountDb.listFriends(req.accountId),
			playlists: await PlaylistDb.getAccessible(req.accountId),
			devices: await AccountDb.listDevices(req.accountId),
		} });
	});
