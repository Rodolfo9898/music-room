#!/bin/sh
set -eu

target="${1:-.env}"
if [ -f "$target" ]; then
  exit 0
fi

umask 077
jwt_secret="$(openssl rand -hex 48)"
database_password="$(openssl rand -hex 24)"
root_password="$(openssl rand -hex 24)"

cat > "$target" <<EOF
PORT=8080
JWT_SECRET=$jwt_secret
EMAILPASS=
DB_PASS=$database_password
DB_USER=music_user
DB_PORT=3306
DB_HOST=mariadb
DB_NAME=MusicRoom
PUBLIC_URL=http://localhost:8080
DEV=true
GOOGLE_CLIENT_ID=
MARIADB_ROOT_PASSWORD=$root_password
MARIADB_DATABASE=MusicRoom
MARIADB_USER=music_user
MARIADB_PASSWORD=$database_password
EOF

printf 'Created private local configuration at %s\n' "$target"
