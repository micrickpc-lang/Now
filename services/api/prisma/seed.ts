import "dotenv/config";
import argon2 from "argon2";
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "../src/generated/prisma/client";

const prisma = new PrismaClient({
  adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL! }),
});

async function main() {
  for (const flag of [
    {
      key: "exact_room_location",
      enabled: true,
      payload: { default: false },
    },
    {
      key: "persistent_messaging",
      enabled: true,
      payload: { direct: true, groups: true, text: true },
    },
    {
      key: "conversation_typing",
      enabled: true,
      payload: { ttlSeconds: 8 },
    },
    {
      key: "chat_media",
      enabled: false,
      payload: { reason: "phase_3" },
    },
  ]) {
    await prisma.featureFlag.upsert({
      where: { key: flag.key },
      create: flag,
      update: { enabled: flag.enabled, payload: flag.payload },
    });
  }
  await prisma.featureFlag.upsert({
    where: { key: "minimum_supported_version" },
    create: {
      key: "minimum_supported_version",
      enabled: true,
      minVersion: "0.1.0",
      forceUpdate: false,
    },
    update: {},
  });
  for (const pattern of ["наркотики", "закладки"]) {
    await prisma.forbiddenWord.upsert({
      where: { pattern },
      create: { pattern, category: "unsafe_meeting" },
      update: {},
    });
  }
  const email = process.env.ADMIN_BOOTSTRAP_EMAIL;
  const password = process.env.ADMIN_BOOTSTRAP_PASSWORD;
  if (email && password && process.env.NODE_ENV !== "production") {
    await prisma.adminUser.upsert({
      where: { email: email.toLocaleLowerCase("en-US") },
      create: {
        email: email.toLocaleLowerCase("en-US"),
        passwordHash: await argon2.hash(password, {
          type: argon2.argon2id,
          memoryCost: 65_536,
          timeCost: 3,
          parallelism: 1,
        }),
        role: "SUPERADMIN",
      },
      update: {},
    });
  }
}

void main()
  .catch((error: unknown) => {
    process.stderr.write(`${String(error)}\n`);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
