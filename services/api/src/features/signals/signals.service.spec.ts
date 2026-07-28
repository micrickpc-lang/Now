import { BadRequestException } from "@nestjs/common";
import type { AuditService } from "../../common/audit.service";
import type { ContentPolicyService } from "../../common/content-policy.service";
import type { PrismaService } from "../../common/prisma.service";
import type { RealtimeGateway } from "../../realtime/realtime.gateway";
import type { SocialService } from "../social/social.service";
import { SignalsService } from "./signals.service";

describe("SignalsService safe locations", () => {
  const now = new Date(Date.now() + 60 * 60_000);
  const safeLocation = {
    id: "safe-location-id",
    ownerId: "author-id",
    signalId: null,
    mode: "APPROXIMATE" as const,
    description: "Within 2 km",
    cityLabel: null,
    districtLabel: null,
    radiusMeters: 2_000,
    expiresAt: now,
    deletedAt: null,
    latitude: 55.75,
    longitude: 37.62,
  };
  const createdSignal = {
    id: "signal-id",
    authorId: "author-id",
    category: "walk",
  };
  const tx = {
    $queryRaw: jest.fn(),
    $executeRaw: jest.fn(),
    signal: { create: jest.fn() },
    exactLocationShare: { findFirst: jest.fn() },
  };
  const prisma = {
    signal: { count: jest.fn(), findMany: jest.fn() },
    user: { findUniqueOrThrow: jest.fn() },
    circle: { count: jest.fn() },
    block: { findMany: jest.fn() },
    signalVisibility: { findMany: jest.fn() },
    $transaction: jest.fn((work: (client: typeof tx) => unknown) => work(tx)),
    $queryRaw: jest.fn(),
  };
  const social = { areFriends: jest.fn() };
  const realtime = { emitUsers: jest.fn() };
  const content = { assertAllowed: jest.fn() };
  const audit = { write: jest.fn() };
  const service = new SignalsService(
    prisma as unknown as PrismaService,
    social as unknown as SocialService,
    realtime as unknown as RealtimeGateway,
    content as unknown as ContentPolicyService,
    audit as unknown as AuditService,
  );

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.signal.count.mockResolvedValue(0);
    prisma.user.findUniqueOrThrow.mockResolvedValue({ limitedMode: false });
    prisma.circle.count.mockResolvedValue(1);
    prisma.block.findMany.mockResolvedValue([]);
    prisma.signal.findMany.mockResolvedValue([]);
    prisma.signalVisibility.findMany.mockResolvedValue([]);
    tx.$queryRaw.mockResolvedValue([{ ...safeLocation }]);
    tx.signal.create.mockResolvedValue({ ...createdSignal });
    tx.$executeRaw.mockResolvedValue(1);
    tx.exactLocationShare.findFirst.mockResolvedValue({
      id: "exact-share-id",
      audience: "CIRCLE",
      circleId: "circle-id",
      recipients: [],
    });
    audit.write.mockResolvedValue(undefined);
  });

  it("hydrates visible signals from safe zones in one bounded query", async () => {
    prisma.signal.findMany.mockResolvedValue([
      { id: "signal-id", category: "walk" },
    ]);
    prisma.$queryRaw.mockResolvedValue([
      { ...safeLocation, signalId: "signal-id" },
    ]);

    await expect(service.feed("friend-id")).resolves.toEqual([
      expect.objectContaining({
        id: "signal-id",
        safeLocation: {
          safeLocationId: "safe-location-id",
          mode: "APPROXIMATE",
          description: "Within 2 km",
          expiresAt: now,
          center: { latitude: 55.75, longitude: 37.62 },
          radiusMeters: 2_000,
        },
      }),
    ]);
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(1);
    const [[safeLocationQuery]] = prisma.$queryRaw.mock
      .calls as unknown as Array<[TemplateStringsArray]>;
    const sql = safeLocationQuery.join(" ");
    expect(sql).toContain('FROM "safe_location_zones"');
    expect(sql).not.toContain("approximate_point");
  });

  it("locks a valid draft, atomically attaches it, and returns only safe precision", async () => {
    const result = await service.create("author-id", {
      category: "walk",
      startsAt: new Date(Date.now() + 15 * 60_000).toISOString(),
      durationMinutes: 30,
      format: "OFFLINE",
      locationMode: "APPROXIMATE",
      safeLocationId: "safe-location-id",
      maxParticipants: 4,
      circleIds: ["circle-id"],
      userIds: [],
    });

    expect(result.safeLocation).toMatchObject({
      safeLocationId: "safe-location-id",
      mode: "APPROXIMATE",
      description: "Within 2 km",
      center: { latitude: 55.75, longitude: 37.62 },
      radiusMeters: 2_000,
    });
    expect(result.safeLocation?.expiresAt).toBeInstanceOf(Date);
    const [[lockQuery]] = tx.$queryRaw.mock.calls as unknown as Array<
      [TemplateStringsArray]
    >;
    const lockSql = lockQuery.join(" ");
    expect(lockSql).toContain("FOR UPDATE");
    const [[attachQuery]] = tx.$executeRaw.mock.calls as unknown as Array<
      [TemplateStringsArray]
    >;
    const attachSql = attachQuery.join(" ");
    expect(attachSql).toContain('"owner_id"');
    expect(attachSql).toContain('"mode"');
    expect(attachSql).toContain('"signal_id" IS NULL');
    expect(attachSql).toContain('"expires_at" > now()');
  });

  it("does not attach a draft owned by another user", async () => {
    tx.$queryRaw.mockResolvedValue([
      { ...safeLocation, ownerId: "another-user" },
    ]);

    await expect(
      service.create("author-id", {
        category: "walk",
        startsAt: new Date(Date.now() + 15 * 60_000).toISOString(),
        durationMinutes: 30,
        format: "OFFLINE",
        locationMode: "APPROXIMATE",
        safeLocationId: "safe-location-id",
        maxParticipants: 4,
        circleIds: ["circle-id"],
        userIds: [],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.signal.create).not.toHaveBeenCalled();
  });

  it("links an exact share only when its audience matches the signal", async () => {
    await service.create("author-id", {
      category: "walk",
      startsAt: new Date(Date.now() + 15 * 60_000).toISOString(),
      durationMinutes: 30,
      format: "OFFLINE",
      locationMode: "EXACT_LIVE",
      exactLocationShareId: "exact-share-id",
      maxParticipants: 4,
      circleIds: ["circle-id"],
      userIds: [],
    });

    const [[createArgs]] = tx.signal.create.mock.calls as unknown as Array<
      [{ data: { locationMode: string; exactLocationShareId: string } }]
    >;
    expect(createArgs.data).toMatchObject({
      locationMode: "EXACT_LIVE",
      exactLocationShareId: "exact-share-id",
    });
  });

  it("rejects an exact share whose audience differs from the signal", async () => {
    tx.exactLocationShare.findFirst.mockResolvedValue({
      id: "exact-share-id",
      audience: "SELECTED_FRIENDS",
      circleId: null,
      recipients: [{ viewerId: "friend-id" }],
    });

    await expect(
      service.create("author-id", {
        category: "walk",
        startsAt: new Date(Date.now() + 15 * 60_000).toISOString(),
        durationMinutes: 30,
        format: "OFFLINE",
        locationMode: "EXACT_PIN",
        exactLocationShareId: "exact-share-id",
        maxParticipants: 4,
        circleIds: ["circle-id"],
        userIds: [],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.signal.create).not.toHaveBeenCalled();
  });
});
