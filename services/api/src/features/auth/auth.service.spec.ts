import type { ConfigService } from "@nestjs/config";
import { AuthService } from "./auth.service";

function firstArgument(mock: { mock: { calls: unknown[][] } }): unknown {
  return mock.mock.calls[0]?.[0];
}

describe("AuthService", () => {
  const values: Record<string, string> = {
    NODE_ENV: "development",
    APP_ENV: "development",
    AUTH_MODE: "local_test",
    ALLOW_LOCAL_TEST_OTP: "true",
    LOCAL_TEST_OTP: "123456",
    OTP_TTL_SECONDS: "300",
    ACCESS_TOKEN_TTL_SECONDS: "900",
    REFRESH_TOKEN_TTL_DAYS: "30",
  };

  let service: AuthService;
  let prisma: {
    otpChallenge: Record<string, jest.Mock>;
    authSession: Record<string, jest.Mock>;
    $transaction: jest.Mock;
  };
  let sms: { sendOtp: jest.Mock };
  let tokens: { issueAccess: jest.Mock; issueRefresh: jest.Mock };

  beforeEach(() => {
    const config = {
      get: jest.fn((key: string) => values[key]),
      getOrThrow: jest.fn((key: string) => {
        const value = values[key];
        if (value === undefined) throw new Error(`Missing ${key}`);
        return value;
      }),
    } as unknown as ConfigService;
    const crypto = {
      hashPhone: (phone: string) => `phone:${phone}`,
      hashIp: (ip: string) => `ip:${ip}`,
      hashToken: (value: string) => `token:${value}`,
      constantTimeEqual: (left: string, right: string) => left === right,
      encryptPii: (value: string) => `encrypted:${value}`,
    };
    sms = { sendOtp: jest.fn().mockResolvedValue(undefined) };
    tokens = {
      issueAccess: jest.fn().mockReturnValue("access-token"),
      issueRefresh: jest
        .fn()
        .mockReturnValue({ raw: "refresh-token", hash: "refresh-hash" }),
    };
    prisma = {
      otpChallenge: {
        count: jest.fn().mockResolvedValue(0),
        create: jest.fn().mockResolvedValue({ id: "challenge-1" }),
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
        findFirst: jest.fn(),
        update: jest.fn().mockResolvedValue({}),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      authSession: {
        create: jest.fn(),
        findFirst: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        findMany: jest.fn().mockResolvedValue([]),
      },
      $transaction: jest.fn(),
    };
    service = new AuthService(
      prisma as never,
      crypto as never,
      sms as never,
      tokens as never,
      config,
      { write: jest.fn() } as never,
    );
  });

  it("creates local-test OTP challenges without dispatching a real SMS", async () => {
    await expect(
      service.requestOtp("+44 7911 123456", "192.0.2.10"),
    ).resolves.toEqual({ accepted: true, retryAfterSeconds: 60 });

    const createRequest = firstArgument(prisma.otpChallenge.create) as {
      data: { phoneHash: string; codeHash: string };
    };
    expect(createRequest.data).toMatchObject({
      phoneHash: "phone:+447911123456",
      codeHash: "token:phone:+447911123456:123456",
    });
    expect(sms.sendOtp).toHaveBeenCalledWith({
      phoneE164: "+447911123456",
      code: "123456",
      requestId: "challenge-1",
    });
  });

  it("uses the same protected flow for resend", async () => {
    await service.resendOtp("+12025550123", "192.0.2.11");

    expect(prisma.otpChallenge.count).toHaveBeenCalledTimes(2);
    expect(sms.sendOtp).toHaveBeenCalledWith(
      expect.objectContaining({ phoneE164: "+12025550123", code: "123456" }),
    );
  });

  it.each([["+79991234567"], ["+12025550123"], ["+447911123456"]])(
    "accepts a syntactically valid international E.164 number: %s",
    async (phone) => {
      await service.requestOtp(phone, "192.0.2.11");

      expect(sms.sendOtp).toHaveBeenCalledWith(
        expect.objectContaining({ phoneE164: phone, code: "123456" }),
      );
    },
  );

  it("verifies an OTP once and creates a rotated-token session", async () => {
    prisma.otpChallenge.findFirst.mockResolvedValue({
      id: "challenge-1",
      codeHash: "token:phone:+12025550123:123456",
      attemptCount: 0,
    });
    const transaction = {
      otpChallenge: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
      user: {
        upsert: jest.fn().mockResolvedValue({
          id: "user-1",
          status: "ACTIVE",
          limitedMode: false,
        }),
      },
      device: { upsert: jest.fn().mockResolvedValue({ id: "device-1" }) },
      authSession: {
        create: jest.fn().mockResolvedValue({ id: "session-1" }),
      },
    };
    prisma.$transaction.mockImplementation(
      async (callback: (tx: typeof transaction) => Promise<unknown>) =>
        callback(transaction),
    );

    await expect(
      service.verifyOtp(
        {
          phone: "+12025550123",
          code: "123456",
          birthDate: "2001-05-10",
          displayName: "Test User",
          installationId: "installation-id",
          platform: "android",
        },
        "192.0.2.12",
      ),
    ).resolves.toEqual({
      accessToken: "access-token",
      refreshToken: "refresh-token",
      expiresIn: 900,
      user: { id: "user-1", limitedMode: false },
    });
    const consumeRequest = firstArgument(
      transaction.otpChallenge.updateMany,
    ) as {
      where: { id: string; consumedAt: null };
    };
    expect(consumeRequest.where).toMatchObject({
      id: "challenge-1",
      consumedAt: null,
    });
    const sessionRequest = firstArgument(transaction.authSession.create) as {
      data: { refreshTokenHash: string };
    };
    expect(sessionRequest.data).toMatchObject({
      refreshTokenHash: "refresh-hash",
    });
  });

  it("rotates a refresh token and supports logout and session management", async () => {
    prisma.authSession.findFirst.mockResolvedValue({
      id: "session-1",
      userId: "user-1",
      user: { status: "ACTIVE", limitedMode: false },
    });
    await expect(service.refresh("old-refresh", "192.0.2.13")).resolves.toEqual(
      {
        accessToken: "access-token",
        refreshToken: "refresh-token",
        expiresIn: 900,
        user: { id: "user-1", limitedMode: false },
      },
    );
    const refreshRequest = firstArgument(prisma.authSession.updateMany) as {
      where: { id: string; revokedAt: null };
    };
    expect(refreshRequest.where).toMatchObject({
      id: "session-1",
      revokedAt: null,
    });

    await expect(service.logout("user-1", "refresh-token")).resolves.toEqual({
      success: true,
    });
    prisma.authSession.findMany.mockResolvedValue([{ id: "session-1" }]);
    await expect(service.sessions("user-1")).resolves.toEqual([
      { id: "session-1" },
    ]);
    await expect(service.session("user-1", "session-1")).resolves.toMatchObject(
      { id: "session-1" },
    );
    await expect(service.revokeSession("user-1", "session-1")).resolves.toEqual(
      { success: true },
    );
  });
});
