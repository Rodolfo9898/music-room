INSERT IGNORE INTO artists (id, name, bio) VALUES
    (1,  'Howard Shore',           'Canadian composer known for The Lord of the Rings scores'),
    (2,  'Avicii',                 'Swedish DJ and electronic music producer'),
    (3,  'Bébé Lilly',             'French virtual character performing children songs'),
    (4,  'Macklemore & Ryan Lewis','American hip-hop duo from Seattle'),
    (5,  'PSY',                    'South Korean singer and rapper'),
    (6,  'Karl Jenkins',           'Welsh composer and musician'),
    (7,  'Disney',                 'Walt Disney musical productions'),
    (8,  'Jacques Brel',           'Belgian singer-songwriter and actor'),
    (9,  'Imagine Dragons',        'American pop-rock band from Las Vegas'),
    (10, 'Selena Gomez',           'American singer and actress'),
    (11, 'Steve Jablonsky',        'American composer known for Transformers scores'),
    (12, 'Little Richard',         'American musician, pioneer of rock and roll'),
    (13, 'Hans Zimmer',            'German composer known for film scores'),
    (14, 'Jean-Jacques Goldman',   'French singer-songwriter and composer');

INSERT IGNORE INTO genres (id, name, description) VALUES
    (1,  'Soundtrack',        'Film and television soundtracks'),
    (2,  'Electronic',        'Electronic dance music'),
    (3,  'Children',          'Music for children'),
    (4,  'Hip-Hop',           'Hip-hop and rap'),
    (5,  'K-Pop',             'Korean pop music'),
    (6,  'Classical',         'Classical and orchestral music'),
    (7,  'Chanson Française', 'French chanson and variétés'),
    (8,  'Rock',              'Rock and alternative'),
    (9,  'Rock and Roll',     'Classic rock and roll'),
    (10, 'Pop',               'Pop music');

INSERT IGNORE INTO musics (id, title, artist_id, genre_id, file_path, duration) VALUES
    (1,  'The Fellowship',        1,  1,  '-The Fellowship- by Howard Shore.mp3',                 351),
    (2,  'Hey Brother',           2,  2,  'Avicii - Hey Brother (Lyric).mp3',                     258),
    (3,  'Les Bêtises',           3,  3,  'Bébé Lilly - Les Bêtises.mp3',                         181),
    (4,  'Can''t Hold Us',        4,  4,  'Can''t Hold Us Lyrics- Macklemore and Ryan Lewis.mp3', 274),
    (5,  'Gangnam Style',         5,  5,  'Gangnam Style.mp3',                                    220),
    (6,  'Palladio',              6,  6,  'Karl Jenkins- Palladio.mp3',                           226),
    (7,  'Comme un Homme',        7,  1,  'Mulan - Comme un Homme.mp3',                           263),
    (8,  'Ne Me Quitte Pas',      8,  7,  'Ne Me Quitte Pas.mp3',                                 224),
    (9,  'Radioactive',           9,  8,  'Radioactive.mp3',                                      186),
    (10, 'Round and Round',       10, 10, 'Round and Round.mp3',                                  198),
    (11, 'Arrival To Earth',      11, 1,  'Transformers- The Score - Arrival To Earth.mp3',       327),
    (12, 'Tutti Frutti',          12, 9,  'Tutti Frutti.mp3',                                     116),
    (13, 'Pirates des Caraïbes',  13, 1,  'pirates des caraïbes.mp3',                             356),
    (14, 'Il Suffira d''Un Signe',14, 7,  'uIl Suffira d''Un Signe.mp3',                          264);
