export const typeDefs = `

type Music {
    id: Int!
    title: String!
    artist_id: Int!
    genre_id: Int!
    file_path: String!
    duration: Int!
    artist_name: String
}

type UserPlaylistTrack {
    id: Int!
    playlist_id: Int!
    music_id: Int!
    position: Int!
    title: String!
    artist_id: Int!
    genre_id: Int!
    duration: Int!
    file_path: String!
    artist_name: String
}

type UserPlaylist {
    id: Int!
    name: String!
    owner_id: Int!
    is_public: Boolean!
    edit_policy: PlaylistEditPolicy!
    version: Int!
    can_edit: Boolean!
    track_count: Int!
    music_ids: [Int!]!
    collaborator_ids: [Int!]!
    tracks: [UserPlaylistTrack!]
}

type MusicChunk {
    filename: String!
    chunkIndex: Int!
    totalChunks: Int!
    data: String!
    finished: Boolean!
}

enum PlaybackStatus {
    IDLE
    PLAYING
    PAUSED
}

enum PlaylistEditPolicy {
    EVERYONE
    COLLABORATORS
}

enum VotePolicy {
    EVERYONE
    INVITED
    LOCATION_TIME
}

type VoteTrack {
    music_id: Int!
    title: String!
    artist_name: String!
    duration: Int!
    vote_count: Int!
    suggested_by: Int!
}

type VoteMember {
    id: Int!
    email: String!
    display_name: String!
}

type VoteEvent {
    id: Int!
    name: String!
    owner_id: Int!
    is_public: Boolean!
    vote_policy: VotePolicy!
    latitude: Float
    longitude: Float
    radius_meters: Int
    starts_at: String
    ends_at: String
    version: Int!
    can_vote: Boolean!
    can_vote_reason: String
    invited_user_ids: [Int!]!
    members: [VoteMember!]!
    user_vote_music_ids: [Int!]!
    tracks: [VoteTrack!]!
}

type PlaylistItem {
    musicId: Int!
    addedByUserId: Int!
    addedAt: Float!
}

type Room {
    id: Int!
    name: String!
    hostId: Int!
    memberIds: [Int!]!
    playlist: [PlaylistItem!]!
    status: PlaybackStatus!
    currentMusicId: Int
    currentIndex: Int
    playbackTimeMs: Float
    playbackUpdatedAtMs: Float
    linkedVoteEventId: Int
}

type ActionResult {
    success: Boolean!
    message: String
    room: Room
}

type Query {
    me: Int!
    musics: [Music!]!
    searchMusics(query: String!): [Music!]!
    myPlaylists: [UserPlaylist!]!
    searchPlaylists(query: String!): [UserPlaylist!]!
    playlist(id: Int!): UserPlaylist
    voteEvents(latitude: Float, longitude: Float): [VoteEvent!]!
    searchVoteEvents(query: String!): [VoteEvent!]!
    voteEvent(id: Int!, latitude: Float, longitude: Float): VoteEvent
    room(id: Int!): Room
    rooms: [Room!]!
}

type Mutation {
    createRoom(name: String!): Room!
    joinRoom(roomId: Int!): Room!
    leaveRoom(roomId: Int!): Boolean!
    deleteRoom(roomId: Int!): ActionResult!
    transferHost(roomId: Int!, targetUserId: Int!): ActionResult!
    addToQueue(roomId: Int!, musicId: Int!): ActionResult!
    setQueue(roomId: Int!, musicIds: [Int!]!): ActionResult!
    play(roomId: Int!): ActionResult!
    playTrack(roomId: Int!, index: Int!): ActionResult!
    pause(roomId: Int!): ActionResult!
    next(roomId: Int!): ActionResult!
    previous(roomId: Int!): ActionResult!
    seek(roomId: Int!, positionMs: Int!): ActionResult!
    linkVoteEvent(roomId: Int!, eventId: Int!): ActionResult!
    unlinkVoteEvent(roomId: Int!): ActionResult!
    createPlaylist(name: String!, isPublic: Boolean!, editPolicy: PlaylistEditPolicy = EVERYONE): UserPlaylist!
    updatePlaylistVisibility(playlistId: Int!, isPublic: Boolean!, expectedVersion: Int): UserPlaylist!
    updatePlaylistEditPolicy(playlistId: Int!, editPolicy: PlaylistEditPolicy!, expectedVersion: Int): UserPlaylist!
    invitePlaylistCollaborator(playlistId: Int!, email: String!, expectedVersion: Int): UserPlaylist!
    addTrackToPlaylist(playlistId: Int!, musicId: Int!, expectedVersion: Int): UserPlaylist!
    removeTrackFromPlaylist(playlistId: Int!, musicId: Int!, expectedVersion: Int): UserPlaylist!
    moveTrackInPlaylist(playlistId: Int!, musicId: Int!, newPosition: Int!, expectedVersion: Int): UserPlaylist!
    createVoteEvent(name: String!, isPublic: Boolean = true, votePolicy: VotePolicy = EVERYONE, location: String, radiusMeters: Int, startsAt: String, endsAt: String): VoteEvent!
    deleteVoteEvent(eventId: Int!): Boolean!
    inviteVoteEventUser(eventId: Int!, email: String!): VoteEvent!
    removeVoteEventUser(eventId: Int!, userId: Int!): VoteEvent!
    suggestVoteTrack(eventId: Int!, musicId: Int!, latitude: Float, longitude: Float): VoteEvent!
    voteForTrack(eventId: Int!, musicId: Int!, latitude: Float, longitude: Float): VoteEvent!
}

type Subscription {
    roomState(roomId: Int!): Room!
    streamMusic(roomId: Int!): MusicChunk!
    playlistUpdated(playlistId: Int!): UserPlaylist!
    voteEventUpdated(eventId: Int!, latitude: Float, longitude: Float): VoteEvent!
    voteEventsUpdated(latitude: Float, longitude: Float): [VoteEvent!]!
    rooms: [Room!]!
}
`
