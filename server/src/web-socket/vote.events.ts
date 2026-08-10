import { EventEmitter, on } from 'node:events';

const emitter = new EventEmitter();
emitter.setMaxListeners(200);

export function publishVoteEventUpdate(eventId: number): void {
	emitter.emit(`event:${eventId}`, eventId);
	emitter.emit('events');
}

export function subscribeToVoteEvent(eventId: number): AsyncIterable<number> {
	return on(emitter, `event:${eventId}`) as AsyncIterable<number>;
}

export function subscribeToVoteEvents(): AsyncIterable<unknown[]> {
	return on(emitter, 'events');
}
