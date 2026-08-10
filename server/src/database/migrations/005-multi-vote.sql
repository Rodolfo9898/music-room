-- Allow a user to hold votes on multiple tracks within the same voting event.
-- Widen the primary key so (event_id, user_id) is no longer unique on its own;
-- a user may now have one row per (event_id, user_id, music_id) they voted for.
ALTER TABLE vote_event_votes
  DROP PRIMARY KEY,
  ADD PRIMARY KEY (event_id, user_id, music_id);
