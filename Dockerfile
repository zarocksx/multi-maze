FROM node:20-alpine

WORKDIR /app

COPY server/package*.json ./server/
RUN cd server && npm ci --omit=dev

COPY server ./server
COPY web ./web

ENV PORT=8080
EXPOSE 8080

CMD ["node", "server/server.js"]
