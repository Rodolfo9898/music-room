export interface GeocodedLocation {
	latitude: number;
	longitude: number;
}

// Resolves a free-text place name into coordinates using OpenStreetMap's
// Nominatim search API. Nominatim's usage policy requires a descriptive
// User-Agent and caps usage at roughly one request per second, which is
// well within this app's needs. Returns null when nothing matches.
export class GeocodingService {
	static async resolveLocation(query: string): Promise<GeocodedLocation | null> {
		const trimmed = query.trim();
		if (!trimmed) return null;

		const url = `https://nominatim.openstreetmap.org/search?${new URLSearchParams({
			q: trimmed,
			format: 'json',
			limit: '1',
		})}`;

		const response = await fetch(url, {
			headers: { 'User-Agent': 'music-room-app (contact: app-support@vanderlynden.eu)' },
		});
		if (!response.ok) return null;

		const results = (await response.json()) as Array<{ lat: string; lon: string }>;
		const first = results[0];
		if (!first) return null;

		const latitude = Number(first.lat);
		const longitude = Number(first.lon);
		if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;

		return { latitude, longitude };
	}
}
