ALTER TABLE users
  ADD COLUMN IF NOT EXISTS email_confirmation_expires_at DATETIME NULL,
  ADD COLUMN IF NOT EXISTS password_reset_expires_at DATETIME NULL;

CREATE TABLE IF NOT EXISTS user_sessions (
  id CHAR(36) NOT NULL,
  user_id INT NOT NULL,
  refresh_token_hash CHAR(64) NOT NULL,
  expires_at DATETIME NOT NULL,
  revoked_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_used_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY refresh_token_hash_uk (refresh_token_hash),
  KEY user_sessions_user_idx (user_id),
  CONSTRAINT user_sessions_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS friendships (
  requester_id INT NOT NULL,
  addressee_id INT NOT NULL,
  status ENUM('PENDING','ACCEPTED') NOT NULL DEFAULT 'PENDING',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (requester_id, addressee_id),
  KEY friendships_addressee_idx (addressee_id),
  CONSTRAINT friendships_requester_fk FOREIGN KEY (requester_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT friendships_addressee_fk FOREIGN KEY (addressee_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT friendships_not_self CHECK (requester_id <> addressee_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS user_devices (
  id INT NOT NULL AUTO_INCREMENT,
  user_id INT NOT NULL,
  device_key VARCHAR(191) NOT NULL,
  name VARCHAR(191) NOT NULL,
  platform VARCHAR(32) NOT NULL,
  app_version VARCHAR(32) NOT NULL,
  can_control TINYINT(1) NOT NULL DEFAULT 1,
  last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY user_device_uk (user_id, device_key),
  CONSTRAINT user_devices_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mobile_action_logs (
  id BIGINT NOT NULL AUTO_INCREMENT,
  user_id INT NULL,
  transport VARCHAR(24) NOT NULL,
  operation VARCHAR(191) NOT NULL,
  platform VARCHAR(32) NOT NULL,
  device VARCHAR(191) NOT NULL,
  app_version VARCHAR(32) NOT NULL,
  status VARCHAR(32) NULL,
  duration_ms INT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY mobile_action_user_idx (user_id),
  KEY mobile_action_created_idx (created_at),
  CONSTRAINT mobile_action_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vote_events (
  id INT NOT NULL AUTO_INCREMENT,
  name VARCHAR(191) NOT NULL,
  owner_id INT NOT NULL,
  is_public TINYINT(1) NOT NULL DEFAULT 1,
  vote_policy ENUM('EVERYONE','INVITED','LOCATION_TIME') NOT NULL DEFAULT 'EVERYONE',
  latitude DECIMAL(9,6) NULL,
  longitude DECIMAL(9,6) NULL,
  radius_meters INT NULL,
  starts_at DATETIME NULL,
  ends_at DATETIME NULL,
  version INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY vote_events_owner_idx (owner_id),
  CONSTRAINT vote_events_owner_fk FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vote_event_invites (
  event_id INT NOT NULL,
  user_id INT NOT NULL,
  invited_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (event_id, user_id),
  CONSTRAINT vote_invites_event_fk FOREIGN KEY (event_id) REFERENCES vote_events(id) ON DELETE CASCADE,
  CONSTRAINT vote_invites_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vote_event_tracks (
  event_id INT NOT NULL,
  music_id INT NOT NULL,
  suggested_by INT NOT NULL,
  suggested_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (event_id, music_id),
  CONSTRAINT vote_tracks_event_fk FOREIGN KEY (event_id) REFERENCES vote_events(id) ON DELETE CASCADE,
  CONSTRAINT vote_tracks_music_fk FOREIGN KEY (music_id) REFERENCES musics(id) ON DELETE CASCADE,
  CONSTRAINT vote_tracks_user_fk FOREIGN KEY (suggested_by) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vote_event_votes (
  event_id INT NOT NULL,
  user_id INT NOT NULL,
  music_id INT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (event_id, user_id),
  KEY vote_event_music_idx (event_id, music_id),
  CONSTRAINT votes_event_fk FOREIGN KEY (event_id) REFERENCES vote_events(id) ON DELETE CASCADE,
  CONSTRAINT votes_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT votes_track_fk FOREIGN KEY (event_id, music_id) REFERENCES vote_event_tracks(event_id, music_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
