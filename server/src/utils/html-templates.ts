const BASE_STYLE = `
	* { box-sizing: border-box; }
	body {
		margin: 0;
		min-height: 100vh;
		display: flex;
		align-items: center;
		justify-content: center;
		font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
		background: #121212;
		color: #e0e0e0;
		padding: 24px;
	}
	.card {
		background: #1e1e1e;
		border-radius: 16px;
		padding: 40px;
		max-width: 420px;
		width: 100%;
		text-align: center;
		box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
	}
	h1 { font-size: 22px; margin: 0 0 12px; }
	p { color: #a0a0a0; line-height: 1.5; margin: 0 0 8px; }
	.icon { font-size: 48px; margin-bottom: 16px; }
	.success { color: #4caf50; }
	.error { color: #f44336; }
	form { margin-top: 24px; text-align: left; }
	label { display: block; font-size: 13px; color: #a0a0a0; margin: 16px 0 6px; }
	input[type="password"] {
		width: 100%;
		padding: 12px 14px;
		border-radius: 10px;
		border: 1px solid #333;
		background: #2a2a2a;
		color: #e0e0e0;
		font-size: 15px;
	}
	input[type="password"]:focus { outline: none; border-color: #1db954; }
	button {
		margin-top: 24px;
		width: 100%;
		padding: 14px;
		border: none;
		border-radius: 10px;
		background: #1db954;
		color: #fff;
		font-size: 16px;
		font-weight: 600;
		cursor: pointer;
	}
	button:hover { background: #1ed760; }
	.form-error { color: #f44336; font-size: 14px; margin-top: 8px; }
	.form-hint { font-size: 13px; color: #808080; margin: 8px 0 0; }
`;

// Prevent XSS injection
function escapeHtml(value: string): string {
	return value
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&#39;');
}

function page(title: string, body: string): string {
	return `<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>${escapeHtml(title)}</title>
	<style>${BASE_STYLE}</style>
</head>
<body>
	<div class="card">${body}</div>
</body>
</html>`;
}

export function successPage(title: string, message: string): string {
	return page(title, `
		<div class="icon success">&#10004;</div>
		<h1>${escapeHtml(title)}</h1>
		<p>${escapeHtml(message)}</p>
		<p>You can return to the app.</p>
	`);
}

export function errorPage(message: string): string {
	return page('Something went wrong', `
		<div class="icon error">&#10006;</div>
		<h1>Something went wrong</h1>
		<p>${escapeHtml(message)}</p>
	`);
}

export function resetPasswordForm(token: string, errorMessage?: string): string {
	const errorBlock = errorMessage
		? `<p class="form-error">${escapeHtml(errorMessage)}</p>`
		: '';
	return page('Reset your password', `
		<h1>Reset your password</h1>
		<p>Enter a new password for your account.</p>
		<form method="POST" action="/accounts/reset-password">
			<input type="hidden" name="token" value="${escapeHtml(token)}">
			<label for="password">New password</label>
			<input type="password" id="password" name="password" required minlength="8" autocomplete="new-password">
			<p class="form-hint">At least 8 characters, with an uppercase letter, a lowercase letter, a number, and a special character.</p>
			<label for="confirmPassword">Confirm password</label>
			<input type="password" id="confirmPassword" name="confirmPassword" required autocomplete="new-password">
			${errorBlock}
			<button type="submit">Reset password</button>
		</form>
	`);
}
