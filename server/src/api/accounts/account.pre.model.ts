import { Request } from 'express';
import { AccountModel } from '../../database/database.models';

export interface IPreAccountRequest extends Request {
	account: AccountModel;
	accountId: number;
	sessionId: string;
}
