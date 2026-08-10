import { createTransport } from 'nodemailer';
import { Logger } from './logger';


export interface IEmail {
	subject: string;
	text: string;
	html?: string;
}

export class MailService {
	static async sendMail(email: IEmail, recipient: string | string[]) {
		if (String(process.env.IS_LOCAL) === 'TRUE') {
			console.log('Sent mail: ' + email.subject);
			console.log('To: ' + recipient);
			return;
		}
		const sender = 'no-reply@vanderlynden.eu';
		const transporter = createTransport({
			host: 'ssl0.ovh.net',
			secure: true,
			auth: {
				user: sender,
				pass: global.config.emailPassword
			}
		});
		transporter.sendMail({
			from: sender,
			to: recipient,
			replyTo: 'app-support@vanderlynden.eu',
			subject: email.subject,
			text: email.text,
			...(email.html ? { html: email.html } : {})
		}).catch((e) => {
			Logger.report(e);
			Logger.report(`Error sending email with subject: ${email.subject}`);
		});
	}
}
