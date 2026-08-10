import { Request, Response } from 'express';
import { AccountService } from './account.service';
import { IPreAccountRequest } from './account.pre.model';
import { successPage, errorPage, resetPasswordForm } from '../../utils/html-templates';

const CONFIRM_PROMPT_MESSAGE = 'check your email to confirm your account';
const RESET_GENERIC_MESSAGE = 'if an account exists for this email, a reset link has been sent';
const HTML_CONTENT_TYPE = 'text/html';
const INVALID_CONFIRM_LINK = 'This confirmation link is invalid or has already been used.';
const INVALID_RESET_LINK = 'This reset link is invalid or has already been used.';

export class AccountController {
	private static success(res: Response, status: number, data: unknown) {
		return res.status(status).json({ success: true, data });
	}

	private static failure(res: Response, status: number, message: string, error?: string) {
		return res.status(status).json({ success: false, message, ...(error ? { error } : {}) });
	}

	static async createAccount(req: Request, res: Response) {
		const { email, password, displayName } = req.body ?? {};
		const result = await AccountService.register(email, password, displayName);
		if (!result.ok) {
			return AccountController.failure(res, result.status, result.message);
		}
		return AccountController.success(res, result.status, { ...result.data, message: CONFIRM_PROMPT_MESSAGE });
	}

	static async login(req: Request, res: Response) {
		const { email, password } = req.body ?? {};
		const result = await AccountService.authenticate(email, password);
		if (!result.ok) {
			return AccountController.failure(
				res,
				result.status,
				result.message,
				result.status === 403 ? 'EMAIL_NOT_VERIFIED' : undefined,
			);
		}
		return AccountController.success(res, result.status, result.data);
	}

	static async loginWithGoogle(req: Request, res: Response) {
		const { idToken } = req.body ?? {};
		const result = await AccountService.loginWithGoogle(idToken);
		if (!result.ok) {
			return AccountController.failure(res, result.status, result.message);
		}
		return AccountController.success(res, result.status, result.data);
	}

	static async refreshSession(req: Request, res: Response) {
		const result = await AccountService.refreshSession(req.body?.refreshToken);
		if (!result.ok) {
			return AccountController.failure(res, result.status, result.message);
		}
		return AccountController.success(res, result.status, result.data);
	}

	static async logout(req: IPreAccountRequest, res: Response) {
		await AccountService.logout(req.accountId, req.sessionId);
		return res.status(200).json({ success: true, data: null });
	}

	static async updateDisplayName(req: IPreAccountRequest, res: Response) {
		const {
			displayName,
			publicInfo = '',
			friendsInfo = '',
			privateInfo = '',
			hasPublicPreference = true,
		} = (req.body ?? {}) as {
			displayName?: string;
			publicInfo?: string;
			friendsInfo?: string;
			privateInfo?: string;
			hasPublicPreference?: boolean;
		};
		const result = await AccountService.updateProfile(
			req.accountId,
			displayName,
			publicInfo,
			friendsInfo,
			privateInfo,
			hasPublicPreference,
		);
		if (!result.ok) {
			return AccountController.failure(res, result.status, result.message);
		}
		return AccountController.success(res, result.status, result.data);
	}

	static async getProfile(req: IPreAccountRequest, res: Response) {
		const result = await AccountService.getProfile(req.accountId);
		if (!result.ok) {
			return AccountController.failure(res, result.status, result.message);
		}
		return AccountController.success(res, result.status, result.data);
	}

	static async updateMusicPreferences(req: IPreAccountRequest, res: Response) {
		const result = await AccountService.updateMusicPreferences(req.accountId, req.body?.genreIds);
		if (!result.ok) {
			return AccountController.failure(res, result.status, result.message);
		}
		return AccountController.success(res, result.status, result.data);
	}

	static async linkGoogleAccount(req: IPreAccountRequest, res: Response) {
		const result = await AccountService.linkGoogleAccount(req.accountId, req.body?.idToken);
		if (!result.ok) {
			return AccountController.failure(res, result.status, result.message);
		}
		return AccountController.success(res, result.status, result.data);
	}

	static async deleteAccount(req: IPreAccountRequest, res: Response) {
		await AccountService.deleteAccount(req.accountId);
		return res.status(200).json({ success: true, data: null });
	}

	// GET /accounts/confirm-email?token=... — serves an HTML page.
	static async confirmEmail(req: Request, res: Response) {
		res.setHeader('Content-Type', HTML_CONTENT_TYPE);
		const confirmed = await AccountService.confirmEmail(String(req.query.token || ''));
		if (!confirmed) {
			return res.status(400).send(errorPage(INVALID_CONFIRM_LINK));
		}
		return res.status(200).send(successPage('Email confirmed', 'Your email address has been confirmed.'));
	}

	// POST /accounts/forgot-password { email } — always 200 to avoid leaking existence.
	static async forgotPassword(req: Request, res: Response) {
		const result = await AccountService.requestPasswordReset(req.body?.email);
		if (!result.ok) {
			return AccountController.failure(res, result.status, result.message);
		}
		return AccountController.success(res, result.status, { message: RESET_GENERIC_MESSAGE });
	}

	// GET /accounts/reset-password?token=... — serves the HTML reset form.
	static async getResetPasswordForm(req: Request, res: Response) {
		res.setHeader('Content-Type', HTML_CONTENT_TYPE);
		const token = String(req.query.token || '').trim();
		if (!(await AccountService.isValidResetToken(token))) {
			return res.status(400).send(errorPage(INVALID_RESET_LINK));
		}
		return res.status(200).send(resetPasswordForm(token));
	}

	// POST /accounts/reset-password (form body) — sets the new password.
	static async resetPassword(req: Request, res: Response) {
		res.setHeader('Content-Type', HTML_CONTENT_TYPE);
		const token = String(req.body?.token || '').trim();
		const outcome = await AccountService.resetPassword(
			token,
			String(req.body?.password || ''),
			String(req.body?.confirmPassword || ''),
		);
		switch (outcome.type) {
			case 'invalid_token':
				return res.status(400).send(errorPage(INVALID_RESET_LINK));
			case 'invalid_input':
				return res.status(400).send(resetPasswordForm(token, outcome.message));
			case 'success':
				return res.status(200).send(successPage('Password updated', 'Your password has been reset.'));
		}
	}
}
