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
COPY services/api services/api
ENV DATABASE_URL=postgresql://build:build@localhost:5432/build
RUN npm run db:generate --workspace=@seychas/api && npm run build --workspace=@seychas/api

FROM node:24-bookworm-slim AS production-dependencies
WORKDIR /workspace
COPY package.json package-lock.json ./
COPY services/api/package.json services/api/package.json
COPY services/worker/package.json services/worker/package.json
COPY apps/admin/package.json apps/admin/package.json
COPY packages/api-contracts/package.json packages/api-contracts/package.json
COPY packages/shared-types/package.json packages/shared-types/package.json
COPY packages/design-tokens/package.json packages/design-tokens/package.json
RUN npm ci --omit=dev --workspace=@seychas/api --include-workspace-root \
  && npm cache clean --force \
  && mkdir -p services/api/node_modules

FROM node:24-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /workspace
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx /root/.npm \
  && groupadd --system --gid 10001 app \
  && useradd --system --uid 10001 --gid app app
COPY --from=production-dependencies /workspace/node_modules ./node_modules
COPY --from=production-dependencies /workspace/services/api/node_modules ./services/api/node_modules
COPY --from=build /workspace/services/api/dist ./services/api/dist
COPY --from=build /workspace/services/api/src/generated ./services/api/src/generated
COPY --from=build /workspace/services/api/prisma ./services/api/prisma
COPY --from=build /workspace/services/api/package.json ./services/api/package.json
WORKDIR /workspace/services/api
USER app
EXPOSE 3000
CMD ["node", "dist/main.js"]
