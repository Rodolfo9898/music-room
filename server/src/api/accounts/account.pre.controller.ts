import { NextFunction, Response, Request } from 'express';
import { IPreAccountRequest } from './account.pre.model';
import { AccountService } from './account.service';
import { AccountDb } from '../../database/account.db';
import { AccountModel } from '../../database/database.models';

export class AccountPreController {

	static async parseTokenCookie(req: IPreAccountRequest, res: Response, next: NextFunction) {
		let token: string;
		token = req.header('Access-Token');
		if (!token) {
			if (!(req.cookies && req.cookies.token)) {
				return res.status(401).json({ success: false, message: 'token not found' });
			} else {
				token = req.cookies.token;
			}
		}
		if (!token) {
			return res.status(401).json({ success: false, message: 'token not found' });
		}
		const session = AccountService.decodeAccessToken(token);
		const account: AccountModel = await AccountPreController.getAccount(token);
		if (!account) {
			return res.status(401).json({ success: false, message: 'invalid or expired token' });
		}
		req.account = account;
		req.accountId = account.id;
		req.sessionId = session!.sessionId;
		next();
	}

	static async getAccountForWS(req: Request, res: Response) {
		let token: string;
		token = req.header('Access-Token');
		if (!token) {
			if (!(req.cookies && req.cookies.token)) {
				return res.status(401).json({ success: false, message: 'token not found' });
			} else {
				token = req.cookies.token;
			}
		}
		if (!token) {
			return res.status(401).json({ success: false, message: 'token not found' });
		}
		const account: AccountModel = await AccountPreController.getAccount(token);
		if (!account) {
			return res.status(401).json({ success: false, message: 'invalid or expired token' });
		}
		return account;
	}

	static async getAccount(token: string): Promise<AccountModel> {
		const session = AccountService.decodeAccessToken(token);
		if (!session || !(await AccountDb.isSessionActive(session.sessionId, session.id))) {
			return null;
		}
		return await AccountDb.getAccountById(session.id);
	}
}
