CREATE TABLE IF NOT EXISTS device_control_delegations (
  device_id INT NOT NULL,
  friend_user_id INT NOT NULL,
  granted_by INT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (device_id, friend_user_id),
  CONSTRAINT fk_delegation_device FOREIGN KEY (device_id) REFERENCES user_devices(id) ON DELETE CASCADE,
  CONSTRAINT fk_delegation_friend FOREIGN KEY (friend_user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_delegation_owner FOREIGN KEY (granted_by) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
