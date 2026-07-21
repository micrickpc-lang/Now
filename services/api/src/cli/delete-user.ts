import "dotenv/config";
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "../generated/prisma/client";

const userId = process.argv[2];
if (!userId) throw new Error("Usage: npm run db:delete-user -- <user-uuid>");
if (process.env.NODE_ENV === "production")
  throw new Error("This command is restricted to development and staging");

const prisma = new PrismaClient({
  adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL! }),
});

async function remove() {
  await prisma.locationShare.deleteMany({ where: { ownerId: userId } });
  await prisma.notificationToken.deleteMany({ where: { userId } });
  await prisma.authSession.deleteMany({ where: { userId } });
  await prisma.roomMessage.updateMany({
    where: { authorId: userId },
    data: { authorId: null, body: "[сообщение удалено]" },
  });
  await prisma.report.updateMany({
    where: { reporterId: userId },
    data: { reporterId: null },
  });
  await prisma.user.delete({ where: { id: userId } });
  process.stdout.write(JSON.stringify({ deleted: userId }) + "\n");
}

void remove()
  .catch((error: unknown) => {
    process.stderr.write(`${String(error)}\n`);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
