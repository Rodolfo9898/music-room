// Generic result for JSON account endpoints: either `ok` with data, or an HTTP error.
export interface ServiceResult<T = void> {
	ok: boolean;
	status: number;
	message?: string;
	data?: T;
}

export interface AuthPayload {
	token: string;
	refreshToken: string;
	accountId: number;
	email: string;
	displayName: string;
}

export interface SignupPayload {
	accountId: number;
	email: string;
	displayName: string;
}

export interface ProfilePayload {
	accountId: number;
	email: string;
	displayName: string;
	googleLinked: boolean;
	hasPublicPreference: boolean;
	publicInfo: string;
	friendsInfo: string;
	privateInfo: string;
	musicPreferenceGenreIds: number[];
}

// Outcome of a password-reset form submission, to drive which HTML page is shown.
export type ResetPasswordOutcome =
	| { type: 'success' }
	| { type: 'invalid_token' }
	| { type: 'invalid_input'; message: string };
