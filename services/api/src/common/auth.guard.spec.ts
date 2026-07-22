import { UnauthorizedException } from "@nestjs/common";
import type { ExecutionContext } from "@nestjs/common";
import type { Reflector } from "@nestjs/core";
import type { Request } from "express";
import type { TokenService } from "../features/auth/token.service";
import { AccessTokenGuard } from "./auth.guard";
import type { PrismaService } from "./prisma.service";

describe("AccessTokenGuard", () => {
  const reflectorMock = { getAllAndOverride: jest.fn() };
  const tokensMock = { verifyAccess: jest.fn() };
  const prismaMock = { authSession: { findFirst: jest.fn() } };
  const guard = new AccessTokenGuard(
    reflectorMock as unknown as Reflector,
    tokensMock as unknown as TokenService,
    prismaMock as unknown as PrismaService,
  );

  function context(authorization?: string) {
    const request = {
      headers: { ...(authorization && { authorization }) },
    } as unknown as Request;
    const executionContext = {
      getHandler: jest.fn(),
      getClass: jest.fn(),
      switchToHttp: () => ({ getRequest: () => request }),
    } as unknown as ExecutionContext;
    return { executionContext, request };
  }

  beforeEach(() => {
    jest.clearAllMocks();
    reflectorMock.getAllAndOverride.mockReturnValue(false);
    tokensMock.verifyAccess.mockReturnValue({
      sub: "user-id",
      sid: "session-id",
      typ: "access",
      exp: Math.floor(Date.now() / 1000) + 60,
    });
  });

  it("allows public routes without parsing a token", async () => {
    reflectorMock.getAllAndOverride.mockReturnValue(true);
    const { executionContext } = context();
    await expect(guard.canActivate(executionContext)).resolves.toBe(true);
    expect(tokensMock.verifyAccess).not.toHaveBeenCalled();
    expect(prismaMock.authSession.findFirst).not.toHaveBeenCalled();
  });

  it("attaches auth only when the session and user remain active", async () => {
    prismaMock.authSession.findFirst.mockResolvedValue({ id: "session-id" });
    const { executionContext, request } = context("Bearer signed-token");
    await expect(guard.canActivate(executionContext)).resolves.toBe(true);
    expect(request).toHaveProperty("auth", {
      userId: "user-id",
      sessionId: "session-id",
    });
    const sessionCalls = prismaMock.authSession.findFirst.mock
      .calls as unknown as Array<[unknown]>;
    expect(sessionCalls[0]?.[0]).toMatchObject({
      where: {
        id: "session-id",
        userId: "user-id",
        revokedAt: null,
        user: { status: "ACTIVE" },
      },
      select: { id: true },
    });
  });

  it("rejects a signed token after its server session is revoked", async () => {
    prismaMock.authSession.findFirst.mockResolvedValue(null);
    const { executionContext } = context("Bearer signed-token");
    await expect(guard.canActivate(executionContext)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });
});
