FROM node:24-bookworm-slim AS build
WORKDIR /workspace
ENV NODE_OPTIONS=--max-old-space-size=512
COPY package.json package-lock.json ./
COPY services/api/package.json services/api/package.json
COPY services/worker/package.json services/worker/package.json
COPY apps/admin/package.json apps/admin/package.json
COPY packages/api-contracts/package.json packages/api-contracts/package.json
COPY packages/shared-types/package.json packages/shared-types/package.json
COPY packages/design-tokens/package.json packages/design-tokens/package.json
RUN npm ci --workspace=@seychas/worker --include-workspace-root
COPY services/worker services/worker
RUN npm run build --workspace=@seychas/worker

# Keep the runtime image production-only and serialize the second install after
# compilation for the same low-memory reason as the API Dockerfile.
FROM build AS production-dependencies
RUN npm ci --omit=dev --workspace=@seychas/worker --include-workspace-root \
  && npm cache clean --force \
  && mkdir -p services/worker/node_modules

FROM node:24-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /workspace
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app app
COPY --from=production-dependencies /workspace/node_modules ./node_modules
COPY --from=production-dependencies /workspace/services/worker/node_modules ./services/worker/node_modules
COPY --from=build /workspace/services/worker/dist ./services/worker/dist
COPY --from=build /workspace/services/worker/package.json ./services/worker/package.json
WORKDIR /workspace/services/worker
USER app
CMD ["node", "dist/main.js"]
