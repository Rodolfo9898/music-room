FROM node:22-bookworm-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json nodemon.json ./
COPY src ./src
COPY public ./public
COPY test ./test

RUN npm run build_app

EXPOSE 8080

CMD ["sh", "-c", "npm run db:migrate && node dist/app.js"]
