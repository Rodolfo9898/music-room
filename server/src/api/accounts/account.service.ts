import { sign, verify } from 'jsonwebtoken';
import { compareSync, hashSync } from 'bcrypt';
import crypto from 'node:crypto';
import { AccountModel } from '../../database/database.models';
import { AccountDb } from '../../database/account.db';
import { generateToken, buildTokenLink } from '../../utils/token.util';
import { MailService } from '../../utils/mail.service';
import { ServiceResult, AuthPayload, SignupPayload, ResetPasswordOutcome, ProfilePayload } from './account.model';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const CONFIRM_EMAIL_PATH = '/accounts/confirm-email';
const RESET_PASSWORD_PATH = '/accounts/reset-password';

interface GoogleTokenInfo {
	sub: string;
	email: string;
	name?: string;
}

export class AccountService {

	static hashPassword(password: string): string {
		return hashSync(password, 10)
	}

	static getLoginToken(id: number, sessionId: string): string {
		return sign({id, sid: sessionId}, global.config.jwtSecret, {
			expiresIn: '30d'
		});
	}

	static decodeAccessToken(token: string): { id: number; sessionId: string } | null {
		try {
			const payload = verify(token, global.config.jwtSecret) as { id?: unknown; sid?: unknown };
			if (Number.isInteger(Number(payload.id)) && typeof payload.sid === 'string' && payload.sid) {
				return { id: Number(payload.id), sessionId: payload.sid };
			}
		} catch (_) {
			// Invalid and expired tokens intentionally share the same result.
		}
		return null;
	}

	static tryLogin(email: string, password: string, dbAccount: AccountModel): boolean {
		return email === dbAccount.email && compareSync(password, dbAccount.password_hash);
	}

	static decodeToken(token: string): number {
		return AccountService.decodeAccessToken(token)?.id ?? null;
	}

	// ---- links & emails ----

	private static async sendConfirmationEmail(email: string, token: string): Promise<void> {
		const link = buildTokenLink(CONFIRM_EMAIL_PATH, token);
		await MailService.sendMail({
			subject: 'Confirm your Music Room account',
			text: `Welcome to Music Room! Confirm your email by opening this link:\n\n${link}`,
			html: `<p>Welcome to Music Room!</p><p>Confirm your email by clicking the link below:</p><p><a href="${link}">Confirm my email</a></p>`,
		}, email);
	}

	private static async sendPasswordResetEmail(email: string, token: string): Promise<void> {
		const link = buildTokenLink(RESET_PASSWORD_PATH, token);
		await MailService.sendMail({
			subject: 'Reset your Music Room password',
			text: `We received a request to reset your password. Open this link to choose a new one:\n\n${link}\n\nIf you didn't request this, you can ignore this email.`,
			html: `<p>We received a request to reset your password.</p><p>Open the link below to choose a new one:</p><p><a href="${link}">Reset my password</a></p><p>If you didn't request this, you can ignore this email.</p>`,
		}, email);
	}

	private static normalizeGoogleEmail(email: string): string {
		let normalized = email.toLowerCase().trim();
		if (normalized.endsWith('@googlemail.com')) {
			normalized = normalized.replace('@googlemail.com', '@gmail.com');
		}
		return normalized;
	}

	private static async verifyGoogleToken(idToken: string): Promise<ServiceResult<GoogleTokenInfo>> {
		if (!idToken || !idToken.trim()) {
			return { ok: false, status: 400, message: 'idToken is required' };
		}

		const tokenInfoResponse = await fetch(
			`https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken.trim())}`
		);
		if (!tokenInfoResponse.ok) {
			return { ok: false, status: 400, message: 'invalid Google token' };
		}

		const tokenInfo = await tokenInfoResponse.json() as {
			sub?: string;
			email?: string;
			email_verified?: boolean | string;
			name?: string;
			aud?: string;
		};

		const isEmailVerified = tokenInfo.email_verified === true || tokenInfo.email_verified === 'true';
		if (!tokenInfo.sub || !tokenInfo.email || !isEmailVerified) {
			return { ok: false, status: 400, message: 'invalid Google token payload' };
		}

		const expectedAudience = process.env.GOOGLE_CLIENT_ID;
		if (expectedAudience && tokenInfo.aud !== expectedAudience) {
			return { ok: false, status: 400, message: 'invalid token audience' };
		}

		return {
			ok: true,
			status: 200,
			data: {
				sub: tokenInfo.sub,
				email: AccountService.normalizeGoogleEmail(tokenInfo.email),
				name: tokenInfo.name,
			},
		};
	}

	// ---- registration ----

	static async register(email: string, password: string, displayName: string): Promise<ServiceResult<SignupPayload>> {
		if (!email || !password) {
			return { ok: false, status: 400, message: 'email and password are required' };
		}
		email = email.toLowerCase().trim();
		displayName = String(displayName || '').toLowerCase().trim();
		password = password.trim();

		if (!EMAIL_REGEX.test(email)) {
			return { ok: false, status: 400, message: 'invalid email format' };
		}

		const strengthError = AccountService.validatePasswordStrength(password);
		if (strengthError) {
			return { ok: false, status: 400, message: strengthError };
		}

		const accountId = await AccountDb.insert(email, displayName, AccountService.hashPassword(password));
		if (!accountId) {
			return { ok: false, status: 500, message: 'failed to create account' };
		}

		// Issue an email confirmation token and email the confirmation link.
		// Login stays blocked until the email is confirmed (token cleared).
		const confirmationToken = generateToken();
		await AccountDb.setEmailConfirmationToken(Number(accountId), confirmationToken);
		await AccountService.sendConfirmationEmail(email, confirmationToken);

		return { ok: true, status: 201, data: {
			accountId: Number(accountId),
			email,
			displayName,
			} };
	}

	// ---- login ----

	static async authenticate(email: string, password: string): Promise<ServiceResult<AuthPayload>> {
		if (!email || !password) {
			return { ok: false, status: 400, message: 'email and password are required' };
		}
		email = email.toLowerCase().trim();
		password = password.trim();

		const dbAccount = await AccountDb.getAccountByEmail(email, true);
		if (!dbAccount || !AccountService.tryLogin(email, password, dbAccount)) {
			return { ok: false, status: 400, message: 'invalid email or password' };
		}
		if (dbAccount.email_confirmation_token) {
			return { ok: false, status: 403, message: 'please confirm your email before logging in' };
		}
		return {
			ok: true,
			status: 200,
			data: await AccountService.createAuthPayload(dbAccount),
		};
	}

	static async loginWithGoogle(idToken: string): Promise<ServiceResult<AuthPayload>> {
		try {
			const verification = await AccountService.verifyGoogleToken(idToken);
			if (!verification.ok) {
				return { ok: false, status: verification.status, message: verification.message };
			}
			const tokenInfo = verification.data;
			if (!tokenInfo) {
				return { ok: false, status: 400, message: 'invalid Google token payload' };
			}
			const normalizedEmail = tokenInfo.email;

			// 1) Existing Google-linked account
			let dbAccount: AccountModel = await AccountDb.getAccountByGoogleId(tokenInfo.sub);
			if (dbAccount) {
				return { ok: true, status: 200, data: await AccountService.createAuthPayload(dbAccount) };
			}

			// 2) Existing email account -> link Google ID
			dbAccount = await AccountDb.getAccountByEmail(normalizedEmail, true);
			if (dbAccount) {
				await AccountDb.setGoogleId(dbAccount.id, tokenInfo.sub);
				// Google has verified the address, so clear any pending confirmation.
				if (dbAccount.email_confirmation_token) {
					await AccountDb.confirmEmail(dbAccount.id);
				}
				return { ok: true, status: 200, data: await AccountService.createAuthPayload(dbAccount) };
			}

			// 3) Create new account (auto-confirmed: no confirmation token is set)
			const displayName = (tokenInfo.name || normalizedEmail.split('@')[0]).trim();
			const randomPasswordHash = AccountService.hashPassword(crypto.randomUUID());
			const accountId = await AccountDb.insert(normalizedEmail, displayName, randomPasswordHash);
			if (!accountId) {
				return { ok: false, status: 500, message: 'failed to create account' };
			}
			await AccountDb.setGoogleId(accountId, tokenInfo.sub);
			return {
				ok: true,
				status: 201,
				data: await AccountService.createAuthPayload(await AccountDb.getAccountById(accountId)),
			};
		} catch (e) {
			return { ok: false, status: 500, message: 'failed to authenticate with Google' };
		}
	}

	static async linkGoogleAccount(accountId: number, idToken: string): Promise<ServiceResult<ProfilePayload>> {
		try {
			const verification = await AccountService.verifyGoogleToken(idToken);
			if (!verification.ok) {
				return { ok: false, status: verification.status, message: verification.message };
			}
			const tokenInfo = verification.data;
			if (!tokenInfo) {
				return { ok: false, status: 400, message: 'invalid Google token payload' };
			}

			const currentAccount = await AccountDb.getAccountById(accountId);
			if (!currentAccount) {
				return { ok: false, status: 404, message: 'account not found' };
			}

			const linkedAccount = await AccountDb.getAccountByGoogleId(tokenInfo.sub);
			if (linkedAccount && Number(linkedAccount.id) !== Number(accountId)) {
				return { ok: false, status: 409, message: 'this Google account is already linked to another Music Room account' };
			}

			await AccountDb.setGoogleId(accountId, tokenInfo.sub);
			if (currentAccount.email_confirmation_token) {
				await AccountDb.confirmEmail(accountId);
			}

			return {
				ok: true,
				status: 200,
				data: await AccountService.getProfilePayload(accountId),
			};
		} catch (_) {
			return { ok: false, status: 500, message: 'failed to link Google account' };
		}
	}

	static async getProfile(accountId: number): Promise<ServiceResult<ProfilePayload>> {
		const account = await AccountDb.getAccountById(accountId);
		if (!account) {
			return { ok: false, status: 404, message: 'account not found' };
		}
		return {
			ok: true,
			status: 200,
			data: await AccountService.getProfilePayload(accountId),
		};
	}

	static async refreshSession(refreshToken: string): Promise<ServiceResult<AuthPayload>> {
		const normalized = String(refreshToken || '').trim();
		if (!normalized) return { ok: false, status: 401, message: 'refreshToken is required' };
		const session = await AccountDb.getSessionByRefreshHash(AccountService.hashOpaqueToken(normalized));
		if (!session) {
			return { ok: false, status: 401, message: 'invalid session' };
		}
		const account = await AccountDb.getAccountById(Number(session.user_id));
		if (!account) return { ok: false, status: 401, message: 'invalid session' };
		const nextRefreshToken = generateToken();
		await AccountDb.rotateSession(session.id, AccountService.hashOpaqueToken(nextRefreshToken));
		return { ok: true, status: 200, data: AccountService.authPayloadForSession(account, session.id, nextRefreshToken) };
	}

	static async logout(accountId: number, sessionId: string): Promise<void> {
		await AccountDb.revokeSession(sessionId, accountId);
	}

	static async updateProfile(
		accountId: number,
		displayName: string,
		publicInfo: string,
		friendsInfo: string,
		privateInfo: string,
		hasPublicPreference: boolean,
	): Promise<ServiceResult<ProfilePayload>> {
		displayName = String(displayName || '').trim();
		if (!displayName) {
			return { ok: false, status: 400, message: 'displayName is required' };
		}
		await AccountDb.updateProfile(
			accountId,
			displayName,
			String(publicInfo || '').trim(),
			String(friendsInfo || '').trim(),
			String(privateInfo || '').trim(),
			Boolean(hasPublicPreference),
		);
		return {
			ok: true,
			status: 200,
			data: await AccountService.getProfilePayload(accountId),
		};
	}

	static async updateMusicPreferences(accountId: number, genreIds: unknown): Promise<ServiceResult<ProfilePayload>> {
		if (!Array.isArray(genreIds)) {
			return { ok: false, status: 400, message: 'genreIds must be an array' };
		}
		const normalized = [...new Set(
			genreIds
				.map(value => Number(value))
				.filter(value => Number.isInteger(value) && value > 0),
		)];
		await AccountDb.setGenrePreferences(accountId, normalized);
		return {
			ok: true,
			status: 200,
			data: await AccountService.getProfilePayload(accountId),
		};
	}

	private static async getProfilePayload(accountId: number): Promise<ProfilePayload> {
		const account = await AccountDb.getAccountById(accountId);
		const preferenceIds = await AccountDb.getGenrePreferenceIds(accountId);
		return {
			accountId: Number(account.id),
			email: account.email,
			displayName: account.display_name,
			googleLinked: Boolean(account.google_id),
			hasPublicPreference: Boolean(account.has_public_preference),
			publicInfo: account.public_info ?? '',
			friendsInfo: account.friends_info ?? '',
			privateInfo: account.private_info ?? '',
			musicPreferenceGenreIds: preferenceIds,
		};
	}

	private static async createAuthPayload(dbAccount: AccountModel): Promise<AuthPayload> {
		const sessionId = crypto.randomUUID();
		const refreshToken = generateToken();
		await AccountDb.createSession(sessionId, Number(dbAccount.id), AccountService.hashOpaqueToken(refreshToken));
		return AccountService.authPayloadForSession(dbAccount, sessionId, refreshToken);
	}

	private static authPayloadForSession(dbAccount: AccountModel, sessionId: string, refreshToken: string): AuthPayload {
		return {
			token: AccountService.getLoginToken(dbAccount.id, sessionId),
			refreshToken,
			accountId: Number(dbAccount.id),
			email: dbAccount.email,
			displayName: dbAccount.display_name,
		};
	}

	private static hashOpaqueToken(token: string): string {
		return crypto.createHash('sha256').update(token).digest('hex');
	}

	// ---- email confirmation ----

	static async confirmEmail(token: string): Promise<boolean> {
		token = String(token || '').trim();
		if (!token) {
			return false;
		}
		const account = await AccountDb.getAccountByEmailConfirmationToken(token);
		if (!account) {
			return false;
		}
		await AccountDb.confirmEmail(account.id);
		return true;
	}

	// ---- password reset ----

	// Always succeeds (status 200) once an email is provided, to avoid leaking
	// whether an account exists for that address.
	static async requestPasswordReset(email: string): Promise<ServiceResult> {
		email = String(email || '').toLowerCase().trim();
		if (!email) {
			return { ok: false, status: 400, message: 'email is required' };
		}
		const account = await AccountDb.getAccountByEmail(email);
		if (account) {
			const resetToken = generateToken();
			await AccountDb.setPasswordResetToken(account.id, resetToken);
			await AccountService.sendPasswordResetEmail(account.email, resetToken);
		}
		return { ok: true, status: 200 };
	}

	static async isValidResetToken(token: string): Promise<boolean> {
		token = String(token || '').trim();
		if (!token) {
			return false;
		}
		return !!(await AccountDb.getAccountByPasswordResetToken(token));
	}

	static validatePasswordStrength(password: string): string | null {
		if (password.length < 8) {
			return 'Use at least 8 characters.';
		}
		if (!/[A-Z]/.test(password)) {
			return 'Add at least one uppercase letter.';
		}
		if (!/[a-z]/.test(password)) {
			return 'Add at least one lowercase letter.';
		}
		if (!/[0-9]/.test(password)) {
			return 'Add at least one number.';
		}
		if (!/[^A-Za-z0-9]/.test(password)) {
			return 'Add at least one special character.';
		}
		return null;
	}

	static async resetPassword(token: string, password: string, confirmPassword: string): Promise<ResetPasswordOutcome> {
		token = String(token || '').trim();
		if (!token) {
			return { type: 'invalid_token' };
		}
		const account = await AccountDb.getAccountByPasswordResetToken(token);
		if (!account) {
			return { type: 'invalid_token' };
		}
		const trimmedPassword = password.trim();
		if (!trimmedPassword) {
			return { type: 'invalid_input', message: 'Password cannot be empty.' };
		}
		const strengthError = AccountService.validatePasswordStrength(trimmedPassword);
		if (strengthError) {
			return { type: 'invalid_input', message: strengthError };
		}
		if (password !== confirmPassword) {
			return { type: 'invalid_input', message: 'Passwords do not match.' };
		}
		await AccountDb.updatePasswordAndClearReset(account.id, AccountService.hashPassword(trimmedPassword));
		return { type: 'success' };
	}

	// ---- profile ----

	static async updateDisplayName(accountId: number, displayName?: string): Promise<ServiceResult<{ displayName: string }>> {
		if (!displayName || !displayName.trim()) {
			return { ok: false, status: 400, message: 'displayName is required' };
		}
		const trimmed = displayName.trim();
		await AccountDb.updateDisplayName(accountId, trimmed);
		return { ok: true, status: 200, data: { displayName: trimmed } };
	}

	static async deleteAccount(accountId: number): Promise<void> {
		await AccountDb.deleteAccount(accountId);
	}

}
