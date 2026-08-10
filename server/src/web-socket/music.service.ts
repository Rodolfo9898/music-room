import * as fs from 'node:fs';
import * as path from 'node:path';

const STREAM_CHUNK_SIZE_BYTES = 65_536;
const MUSICS_DIRECTORY = path.resolve(__dirname, '../../musics');

export interface MusicChunkPayload {
	filename: string;
	chunkIndex: number;
	totalChunks: number;
	data: string;
	finished: boolean;
}

export class MusicService {
	static listMusicFiles(): string[] {
		return fs.readdirSync(MUSICS_DIRECTORY)
			.filter(file => file.endsWith('.mp3'))
			.sort();
	}

	static async *streamFile(filename: string): AsyncGenerator<MusicChunkPayload> {
		const sanitizedFilename = path.basename(filename);
		const filePath = path.join(MUSICS_DIRECTORY, sanitizedFilename);

		if (!fs.existsSync(filePath)) {
			throw new Error(`Music file not found: ${sanitizedFilename}`);
		}

		const fileSize = fs.statSync(filePath).size;
		const totalChunks = Math.ceil(fileSize / STREAM_CHUNK_SIZE_BYTES);
		const fileHandle = await fs.promises.open(filePath, 'r');

		try {
			let chunkIndex = 0;
			const buffer = Buffer.alloc(STREAM_CHUNK_SIZE_BYTES);

			while (true) {
				const { bytesRead } = await fileHandle.read(buffer, 0, STREAM_CHUNK_SIZE_BYTES);
				if (bytesRead === 0) break;

				const chunk = buffer.subarray(0, bytesRead);
				yield {
					filename: sanitizedFilename,
					chunkIndex,
					totalChunks,
					data: chunk.toString('base64'),
					finished: chunkIndex === totalChunks - 1,
				};
				chunkIndex++;
			}
		} finally {
			await fileHandle.close();
		}
	}
}
