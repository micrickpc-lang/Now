FROM node:24-bookworm-slim AS build
WORKDIR /workspace
COPY package.json package-lock.json ./
COPY services/api/package.json services/api/package.json
COPY services/worker/package.json services/worker/package.json
COPY apps/admin/package.json apps/admin/package.json
COPY packages/api-contracts/package.json packages/api-contracts/package.json
COPY packages/shared-types/package.json packages/shared-types/package.json
COPY packages/design-tokens/package.json packages/design-tokens/package.json
RUN npm ci
COPY services/worker services/worker
RUN npm run build --workspace=@seychas/worker

FROM node:24-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /workspace
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app app
COPY --from=build /workspace/node_modules ./node_modules
COPY --from=build /workspace/services/worker/dist ./services/worker/dist
COPY --from=build /workspace/services/worker/package.json ./services/worker/package.json
WORKDIR /workspace/services/worker
USER app
CMD ["node", "dist/main.js"]
