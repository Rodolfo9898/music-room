import { EventEmitter } from 'node:events';

const EVENT_CHANNEL = 'playlist';
const emitter = new EventEmitter();
emitter.setMaxListeners(0);

export function publishPlaylistUpdate(playlistId: number) {
	emitter.emit(EVENT_CHANNEL, playlistId);
}

export function subscribeToPlaylist(playlistId: number): AsyncIterableIterator<number> {
	const queue: number[] = [];
	const waiters: Array<(value: IteratorResult<number>) => void> = [];
	let closed = false;

	const onEvent = (updatedPlaylistId: number) => {
		if (closed || updatedPlaylistId !== playlistId) return;
		const waiter = waiters.shift();
		if (waiter) waiter({ value: updatedPlaylistId, done: false });
		else queue.push(updatedPlaylistId);
	};

	emitter.on(EVENT_CHANNEL, onEvent);

	const cleanup = () => {
		emitter.off(EVENT_CHANNEL, onEvent);
		while (waiters.length) {
			const waiter = waiters.shift();
			waiter?.({ value: undefined as never, done: true });
		}
	};

	return {
		next(): Promise<IteratorResult<number>> {
			if (queue.length) {
				return Promise.resolve({ value: queue.shift()!, done: false });
			}
			if (closed) {
				return Promise.resolve({ value: undefined as never, done: true });
			}
			return new Promise(resolve => waiters.push(resolve));
		},
		return(): Promise<IteratorResult<number>> {
			closed = true;
			cleanup();
			return Promise.resolve({ value: undefined as never, done: true });
		},
		throw(err: unknown): Promise<IteratorResult<number>> {
			closed = true;
			cleanup();
			return Promise.reject(err);
		},
		[Symbol.asyncIterator]() {
			return this;
		},
	};
}
