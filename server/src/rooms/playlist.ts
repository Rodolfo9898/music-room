import { PlaylistItem } from './room.models';

export class Playlist {
	private readonly _items: PlaylistItem[] = [];

	get items(): readonly PlaylistItem[] {
		return this._items;
	}

	get size(): number {
		return this._items.length;
	}

	get isEmpty(): boolean {
		return this._items.length === 0;
	}

	add(musicId: number, addedByUserId: number): PlaylistItem {
		const item: PlaylistItem = {
			musicId,
			addedByUserId,
			addedAt: Date.now(),
		};
		this._items.push(item);
		return item;
	}

	firstMusicId(): number | null {
		return this._items[0]?.musicId ?? null;
	}

	replace(musicIds: number[], addedByUserId: number): void {
		this._items.length = 0;
		const now = Date.now();
		for (const musicId of musicIds) {
			this._items.push({ musicId, addedByUserId, addedAt: now });
		}
	}

	// Sets the full item list verbatim (no regenerated addedAt/addedByUserId),
	// used when reordering the queue without disturbing already-known items
	// (e.g. syncing the upcoming tail from a vote ranking).
	replaceAll(items: PlaylistItem[]): void {
		this._items.length = 0;
		this._items.push(...items);
	}

	snapshot(): PlaylistItem[] {
		return this._items.slice();
	}
}
