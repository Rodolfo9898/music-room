import { NextFunction, Request, Response } from 'express';

interface Bucket { count: number; resetsAt: number }

export function rateLimit(options: { windowMs: number; max: number; name: string }) {
	const buckets = new Map<string, Bucket>();
	return (req: Request, res: Response, next: NextFunction) => {
		const now = Date.now();
		const key = `${options.name}:${req.ip || req.socket.remoteAddress || 'unknown'}`;
		let bucket = buckets.get(key);
		if (!bucket || bucket.resetsAt <= now) {
			bucket = { count: 0, resetsAt: now + options.windowMs };
			buckets.set(key, bucket);
		}
		bucket.count++;
		res.setHeader('RateLimit-Limit', options.max);
		res.setHeader('RateLimit-Remaining', Math.max(0, options.max - bucket.count));
		res.setHeader('RateLimit-Reset', Math.ceil(bucket.resetsAt / 1000));
		if (bucket.count > options.max) {
			res.setHeader('Retry-After', Math.ceil((bucket.resetsAt - now) / 1000));
			return res.status(429).json({ success: false, message: 'Too many requests. Please try again later.' });
		}
		if (buckets.size > 10000) {
			for (const [bucketKey, value] of buckets) if (value.resetsAt <= now) buckets.delete(bucketKey);
		}
		next();
	};
}

export const globalRateLimit = rateLimit({ windowMs: 60_000, max: 300, name: 'global' });
export const accountRateLimit = rateLimit({ windowMs: 60_000, max: 30, name: 'account' });
