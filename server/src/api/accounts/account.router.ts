import { Router } from 'express';
import { AccountController } from './account.controller';
import { AccountPreController } from './account.pre.controller';
import { accountResourcesRouter } from './account-resources.router';
import { accountRateLimit } from '../../middleware/rate-limit.middleware';

export const accountRouter: Router =
	Router({mergeParams: true})
		.use(accountRateLimit)
		/**
		 * @openapi
		 * /accounts/login/google:
		 *   post:
		 *     tags: [Accounts]
		 *     summary: Log in or sign up with a Google ID token
		 *     security: []
		 *     description: Verifies the Google ID token, links or creates the account, and returns an auth payload.
		 *     requestBody:
		 *       required: true
		 *       content:
		 *         application/json:
		 *           schema: { $ref: '#/components/schemas/GoogleLoginRequest' }
		 *     responses:
		 *       200:
		 *         description: Logged in to an existing account
		 *         content:
		 *           application/json:
		 *             schema: { $ref: '#/components/schemas/AuthPayload' }
		 *       201:
		 *         description: New account created from the Google profile (auto-confirmed)
		 *         content:
		 *           application/json:
		 *             schema: { $ref: '#/components/schemas/AuthPayload' }
		 *       400: { description: 'Missing or invalid Google token (plain-text message)' }
		 *       500: { description: 'Google verification or account creation failed (plain-text message)' }
		 */
		.post('/login/google', AccountController.loginWithGoogle)
		/**
		 * @openapi
		 * /accounts/login:
		 *   post:
		 *     tags: [Accounts]
		 *     summary: Log in with email and password
		 *     security: []
		 *     requestBody:
		 *       required: true
		 *       content:
		 *         application/json:
		 *           schema: { $ref: '#/components/schemas/LoginRequest' }
		 *     responses:
		 *       200:
		 *         description: Login OK
		 *         content:
		 *           application/json:
		 *             schema: { $ref: '#/components/schemas/AuthPayload' }
		 *       400: { description: 'Missing fields or invalid email/password (plain-text message)' }
		 *       403: { description: 'Email not confirmed yet (plain-text message)' }
		 */
		.post('/login', AccountController.login)
		/**
		 * @openapi
		 * /accounts/signup:
		 *   post:
		 *     tags: [Accounts]
		 *     summary: Create an account
		 *     security: []
		 *     description: Sends a confirmation email; login is blocked until the email is confirmed.
		 *     requestBody:
		 *       required: true
		 *       content:
		 *         application/json:
		 *           schema: { $ref: '#/components/schemas/SignupRequest' }
		 *     responses:
		 *       201:
		 *         description: Account created, confirmation email sent
		 *         content:
		 *           application/json:
		 *             schema: { $ref: '#/components/schemas/SignupResponse' }
		 *       400: { description: 'Missing fields or invalid email format (plain-text message)' }
		 *       500: { description: 'Account creation failed, e.g. email already registered (plain-text message)' }
		 */
		.post('/signup', AccountController.createAccount)
		/**
		 * @openapi
		 * /accounts/refresh:
		 *   post:
		 *     tags: [Accounts]
		 *     summary: Renew the current authenticated session
		 *     description: Validates the current JWT and returns a freshly issued auth payload for the same account.
		 *     security:
		 *       - accessTokenHeader: []
		 *       - cookieAuth: []
		 *     responses:
		 *       200:
		 *         description: Session renewed
		 *         content:
		 *           application/json:
		 *             schema: { $ref: '#/components/schemas/AuthPayload' }
		 *       400: { $ref: '#/components/responses/AuthError' }
		 */
		.post('/refresh', AccountController.refreshSession)
		.post('/logout', AccountPreController.parseTokenCookie, AccountController.logout)
		/**
		 * @openapi
		 * /accounts/forgot-password:
		 *   post:
		 *     tags: [Accounts]
		 *     summary: Request a password reset email
		 *     security: []
		 *     description: Always answers 200 when an email is provided, to avoid leaking whether an account exists.
		 *     requestBody:
		 *       required: true
		 *       content:
		 *         application/json:
		 *           schema:
		 *             type: object
		 *             required: [email]
		 *             properties:
		 *               email: { type: string, format: email }
		 *     responses:
		 *       200:
		 *         description: Reset link sent if the account exists
		 *         content:
		 *           application/json:
		 *             schema:
		 *               type: object
		 *               properties:
		 *                 message: { type: string, example: 'if an account exists for this email, a reset link has been sent' }
		 *       400: { description: 'Email is missing (plain-text message)' }
		 */
		.post('/forgot-password', AccountController.forgotPassword)
		/**
		 * @openapi
		 * /accounts/confirm-email:
		 *   get:
		 *     tags: [Accounts]
		 *     summary: Confirm an email address (link from the confirmation email)
		 *     security: []
		 *     parameters:
		 *       - name: token
		 *         in: query
		 *         required: true
		 *         schema: { type: string }
		 *     responses:
		 *       200: { description: 'HTML success page', content: { text/html: { schema: { type: string } } } }
		 *       400: { description: 'HTML error page — link invalid or already used', content: { text/html: { schema: { type: string } } } }
		 */
		.get('/confirm-email', AccountController.confirmEmail)
		/**
		 * @openapi
		 * /accounts/reset-password:
		 *   get:
		 *     tags: [Accounts]
		 *     summary: Show the password reset form (link from the reset email)
		 *     security: []
		 *     parameters:
		 *       - name: token
		 *         in: query
		 *         required: true
		 *         schema: { type: string }
		 *     responses:
		 *       200: { description: 'HTML reset form', content: { text/html: { schema: { type: string } } } }
		 *       400: { description: 'HTML error page — link invalid or already used', content: { text/html: { schema: { type: string } } } }
		 */
		.get('/reset-password', AccountController.getResetPasswordForm)
		/**
		 * @openapi
		 * /accounts/reset-password:
		 *   post:
		 *     tags: [Accounts]
		 *     summary: Set a new password (submitted by the HTML reset form)
		 *     security: []
		 *     requestBody:
		 *       required: true
		 *       content:
		 *         application/x-www-form-urlencoded:
		 *           schema:
		 *             type: object
		 *             required: [token, password, confirmPassword]
		 *             properties:
		 *               token: { type: string }
		 *               password: { type: string, format: password }
		 *               confirmPassword: { type: string, format: password }
		 *     responses:
		 *       200: { description: 'HTML success page', content: { text/html: { schema: { type: string } } } }
		 *       400: { description: 'HTML error page or re-rendered form with a validation message', content: { text/html: { schema: { type: string } } } }
		 */
		.post('/reset-password', AccountController.resetPassword)
		/**
		 * @openapi
		 * /accounts/me:
		 *   get:
		 *     tags: [Accounts]
		 *     summary: Get the complete profile of the authenticated account
		 *     responses: { 200: { description: Profile and genre preferences }, 401: { $ref: '#/components/responses/AuthError' } }
		 */
		.get('/me', AccountPreController.parseTokenCookie, AccountController.getProfile)
		/**
		 * @openapi
		 * /accounts/me/google:
		 *   post:
		 *     tags: [Accounts]
		 *     summary: Link a Google identity to the authenticated account
		 *     responses: { 200: { description: Updated profile }, 400: { description: Invalid or conflicting Google token } }
		 */
		.post('/me/google', AccountPreController.parseTokenCookie, AccountController.linkGoogleAccount)
		/**
		 * @openapi
		 * /accounts/me/preferences:
		 *   patch:
		 *     tags: [Accounts]
		 *     summary: Replace music genre preferences
		 *     responses: { 200: { description: Updated profile }, 400: { description: Invalid genre IDs } }
		 */
		.patch('/me/preferences', AccountPreController.parseTokenCookie, AccountController.updateMusicPreferences)
		/**
		 * @openapi
		 * /accounts/me:
		 *   patch:
		 *     tags: [Accounts]
		 *     summary: Update the display name of the logged-in account
		 *     security:
		 *       - accessTokenHeader: []
		 *       - cookieAuth: []
		 *     requestBody:
		 *       required: true
		 *       content:
		 *         application/json:
		 *           schema:
		 *             type: object
		 *             required: [displayName]
		 *             properties:
		 *               displayName: { type: string }
		 *     responses:
		 *       200:
		 *         description: Display name updated
		 *         content:
		 *           application/json:
		 *             schema:
		 *               type: object
		 *               properties:
		 *                 displayName: { type: string }
		 *       400: { $ref: '#/components/responses/AuthError' }
		 */
		.patch('/me', AccountPreController.parseTokenCookie, AccountController.updateDisplayName)
		/**
		 * @openapi
		 * /accounts/me:
		 *   delete:
		 *     tags: [Accounts]
		 *     summary: Delete the logged-in account
		 *     security:
		 *       - accessTokenHeader: []
		 *       - cookieAuth: []
		 *     responses:
		 *       200:
		 *         description: Account deleted
		 *         content:
		 *           application/json:
		 *             schema:
		 *               type: object
		 *               properties:
		 *                 success: { type: boolean, example: true }
		 *       400: { $ref: '#/components/responses/AuthError' }
		 */
		.delete('/me', AccountPreController.parseTokenCookie, AccountController.deleteAccount)
		.use('/', accountResourcesRouter)
;
