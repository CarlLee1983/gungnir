FROM oven/bun:1 AS build
WORKDIR /app
COPY package.json ./
RUN bun install
COPY src ./src
RUN bun build ./src/index.ts --outdir ./dist --target=bun

FROM oven/bun:1-slim
WORKDIR /app
COPY --from=build /app/dist ./dist
CMD ["bun", "run", "dist/index.js"]
