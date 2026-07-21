import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomInt } from "node:crypto";
import { parsePhoneNumberFromString } from "libphonenumber-js";
import { differenceInYears } from "../../common/date-utils";
import { AuditService } from "../../common/audit.service";
import { CryptoService } from "../../common/crypto.service";
import { PrismaService } from "../../common/prisma.service";
import type { VerifyOtpDto } from "./auth.dto";
import { OtpDispatcher } from "./otp.provider";
import { TokenService } from "./token.service";

const GENERIC_OTP_RESPONSE = { accepted: true, retryAfterSeconds: 60 } as const;

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly crypto: CryptoService,
    private readonly otp: OtpDispatcher,
    private readonly tokens: TokenService,
    private readonly config: ConfigService,
    private readonly audit: AuditService,
  ) {}

  async requestOtp(rawPhone: string, ip: string) {
    const phone = this.normalizePhone(rawPhone);
    const phoneHash = this.crypto.hashPhone(phone);
    const ipHash = this.crypto.hashIp(ip);
    const minuteAgo = new Date(Date.now() - 60_000);
    const [phoneRecent, ipRecent] = await Promise.all([
      this.prisma.otpChallenge.count({
        where: { phoneHash, createdAt: { gte: minuteAgo } },
      }),
      this.prisma.otpChallenge.count({
        where: { requestIpHash: ipHash, createdAt: { gte: minuteAgo } },
      }),
    ]);
    if (phoneRecent > 0 || ipRecent >= 5) return GENERIC_OTP_RESPONSE;

    const code =
      this.config.get("NODE_ENV") === "development" &&
      this.config.get("DEV_OTP_CODE")
        ? this.config.getOrThrow<string>("DEV_OTP_CODE")
        : String(randomInt(100000, 1_000_000));
    await this.prisma.otpChallenge.create({
      data: {
        phoneHash,
        codeHash: this.crypto.hashToken(`${phoneHash}:${code}`),
        requestIpHash: ipHash,
        expiresAt: new Date(
          Date.now() + Number(this.config.get("OTP_TTL_SECONDS") ?? 300) * 1000,
        ),
      },
    });
    await this.otp.send(phone, code);
    return GENERIC_OTP_RESPONSE;
  }

  async verifyOtp(dto: VerifyOtpDto, ip: string, userAgent?: string) {
    const phone = this.normalizePhone(dto.phone);
    const phoneHash = this.crypto.hashPhone(phone);
    const challenge = await this.prisma.otpChallenge.findFirst({
      where: { phoneHash, consumedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: "desc" },
    });
    const providedHash = this.crypto.hashToken(`${phoneHash}:${dto.code}`);
    if (
      !challenge ||
      challenge.attemptCount >= 5 ||
      !this.crypto.constantTimeEqual(challenge.codeHash, providedHash)
    ) {
      if (challenge)
        await this.prisma.otpChallenge.update({
          where: { id: challenge.id },
          data: { attemptCount: { increment: 1 } },
        });
      throw new UnauthorizedException("Неверный или истёкший код");
    }

    const birthDate = new Date(dto.birthDate);
    const age = differenceInYears(new Date(), birthDate);
    if (age < 14) throw new ForbiddenException("Минимальный возраст — 14 лет");
    if (age > 120) throw new BadRequestException("Некорректная дата рождения");

    const result = await this.prisma.$transaction(async (tx) => {
      await tx.otpChallenge.update({
        where: { id: challenge.id },
        data: { consumedAt: new Date() },
      });
      const user = await tx.user.upsert({
        where: { phoneHash },
        update: {},
        create: {
          phoneHash,
          phoneCiphertext: this.crypto.encryptPii(phone),
          birthDate,
          limitedMode: age < 18,
          profile: {
            create: {
              displayName: dto.displayName.trim(),
              privacySettings: { exactLocationDefault: false },
            },
          },
        },
        include: { profile: true },
      });
      if (user.status !== "ACTIVE")
        throw new ForbiddenException("Аккаунт недоступен");
      const device = await tx.device.upsert({
        where: {
          userId_installationId: {
            userId: user.id,
            installationId: dto.installationId,
          },
        },
        update: { lastSeenAt: new Date(), label: dto.deviceLabel },
        create: {
          userId: user.id,
          installationId: dto.installationId,
          platform: dto.platform,
          label: dto.deviceLabel,
        },
      });
      const refresh = this.tokens.issueRefresh();
      const session = await tx.authSession.create({
        data: {
          userId: user.id,
          deviceId: device.id,
          refreshTokenHash: refresh.hash,
          ipHash: this.crypto.hashIp(ip),
          userAgent: userAgent?.slice(0, 255),
          expiresAt: new Date(
            Date.now() +
              Number(this.config.get("REFRESH_TOKEN_TTL_DAYS") ?? 30) *
                86_400_000,
          ),
        },
      });
      return { user, session, refresh: refresh.raw };
    });
    return this.tokenResponse(
      result.user.id,
      result.session.id,
      result.refresh,
      result.user.limitedMode,
    );
  }

  async refresh(raw: string, ip: string) {
    const hash = this.crypto.hashToken(raw);
    const session = await this.prisma.authSession.findFirst({
      where: {
        refreshTokenHash: hash,
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
      include: { user: true },
    });
    if (!session || session.user.status !== "ACTIVE")
      throw new UnauthorizedException("Invalid refresh token");
    const replacement = this.tokens.issueRefresh();
    const updated = await this.prisma.authSession.updateMany({
      where: { id: session.id, refreshTokenHash: hash, revokedAt: null },
      data: {
        refreshTokenHash: replacement.hash,
        rotationCounter: { increment: 1 },
        lastUsedAt: new Date(),
        ipHash: this.crypto.hashIp(ip),
      },
    });
    if (updated.count !== 1) {
      await this.prisma.authSession.updateMany({
        where: { userId: session.userId },
        data: { revokedAt: new Date() },
      });
      throw new UnauthorizedException("Refresh token reuse detected");
    }
    return this.tokenResponse(
      session.userId,
      session.id,
      replacement.raw,
      session.user.limitedMode,
    );
  }

  async logout(userId: string, rawRefresh: string) {
    await this.prisma.authSession.updateMany({
      where: {
        userId,
        refreshTokenHash: this.crypto.hashToken(rawRefresh),
        revokedAt: null,
      },
      data: { revokedAt: new Date() },
    });
    return { success: true };
  }

  async logoutAll(userId: string) {
    await this.prisma.authSession.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    await this.audit.write({
      actorUserId: userId,
      action: "auth.logout_all",
      resourceType: "user",
      resourceId: userId,
    });
    return { success: true };
  }

  async sessions(userId: string) {
    return this.prisma.authSession.findMany({
      where: { userId, revokedAt: null, expiresAt: { gt: new Date() } },
      select: {
        id: true,
        createdAt: true,
        lastUsedAt: true,
        expiresAt: true,
        device: {
          select: { platform: true, label: true, installationId: true },
        },
      },
      orderBy: { lastUsedAt: "desc" },
    });
  }

  async revokeSession(userId: string, sessionId: string) {
    const result = await this.prisma.authSession.updateMany({
      where: { id: sessionId, userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (!result.count) throw new BadRequestException("Session not found");
    return { success: true };
  }

  private tokenResponse(
    userId: string,
    sessionId: string,
    refreshToken: string,
    limitedMode: boolean,
  ) {
    return {
      accessToken: this.tokens.issueAccess(userId, sessionId),
      refreshToken,
      expiresIn: Number(this.config.get("ACCESS_TOKEN_TTL_SECONDS") ?? 900),
      user: { id: userId, limitedMode },
    };
  }

  private normalizePhone(input: string): string {
    const parsed = parsePhoneNumberFromString(input, "RU");
    if (!parsed?.isValid())
      throw new BadRequestException("Некорректный номер телефона");
    return parsed.number;
  }
}
