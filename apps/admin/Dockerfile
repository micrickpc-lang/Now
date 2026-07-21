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
COPY apps/admin apps/admin
RUN npm run build --workspace=@seychas/admin

FROM node:24-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app app
COPY --from=build /workspace/apps/admin/.next/standalone ./
COPY --from=build /workspace/apps/admin/.next/static ./apps/admin/.next/static
USER app
EXPOSE 3001
ENV PORT=3001 HOSTNAME=0.0.0.0
CMD ["node", "apps/admin/server.js"]
