import { randomBytes } from 'node:crypto';

const DEFAULT_TOKEN_LENGTH = 64;

export function generateToken(length: number = DEFAULT_TOKEN_LENGTH): string {
	return randomBytes(length / 2).toString('hex');
}

/**
 * Builds an absolute backend link carrying a token query param, e.g. for email
 * confirmation / password reset links. Base origin comes from PUBLIC_URL.
 */
export function buildTokenLink(path: string, token: string): string {
	const baseUrl = (global.config.publicUrl || '').replace(/\/$/, '');
	return `${baseUrl}${path}?token=${encodeURIComponent(token)}`;
}
