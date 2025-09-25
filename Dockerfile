FROM node:20-alpine
WORKDIR /app
COPY warmup.js ./
RUN npm init -y && npm i pg ioredis
CMD ["node", "warmup.js"]
