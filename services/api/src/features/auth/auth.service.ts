import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomInt, randomUUID } from "node:crypto";
import { parsePhoneNumberFromString } from "libphonenumber-js";
import {
  AuthIdentityProvider,
  EmailLoginCodePurpose,
  type Prisma,
} from "../../generated/prisma/client";
import { differenceInYears } from "../../common/date-utils";
import { AuditService } from "../../common/audit.service";
import { CryptoService } from "../../common/crypto.service";
import { PrismaService } from "../../common/prisma.service";
import { RedisService } from "../../common/redis.service";
import type {
  CompleteProfileDto,
  GoogleAuthDto,
  RequestEmailCodeDto,
  VerifyEmailCodeDto,
  VerifyOtpDto,
} from "./auth.dto";
import { EmailDispatcher } from "./email.provider";
import { GoogleTokenVerifier } from "./google-token-verifier";
import { OtpDispatcher } from "./otp.provider";
import { TokenService } from "./token.service";

const GENERIC_CODE_RESPONSE = {
  accepted: true,
  retryAfterSeconds: 60,
} as const;
const MAX_CODE_ATTEMPTS = 5;

interface DeviceInput {
  installationId: string;
  platform: string;
  deviceLabel?: string;
  appVersion?: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly crypto: CryptoService,
    private readonly redis: RedisService,
    private readonly otp: OtpDispatcher,
    private readonly email: EmailDispatcher,
    private readonly google: GoogleTokenVerifier,
    private readonly tokens: TokenService,
    private readonly config: ConfigService,
    private readonly audit: AuditService,
  ) {}

  // Legacy SMS is deliberately available only to isolated compatibility tests.
  async requestOtp(rawPhone: string, ip: string) {
    this.assertLegacySmsTestMode();
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
    if (phoneRecent > 0 || ipRecent >= 5) return GENERIC_CODE_RESPONSE;

    const code = this.legacyTestCode();
    await this.prisma.otpChallenge.create({
      data: {
        phoneHash,
        codeHash: this.crypto.hashToken(`${phoneHash}:${code}`),
        requestIpHash: ipHash,
        expiresAt: this.codeExpiry(),
      },
    });
    await this.otp.send(phone, code);
    return GENERIC_CODE_RESPONSE;
  }

  async verifyOtp(dto: VerifyOtpDto, ip: string, userAgent?: string) {
    this.assertLegacySmsTestMode();
    const phone = this.normalizePhone(dto.phone);
    const phoneHash = this.crypto.hashPhone(phone);
    const challenge = await this.prisma.otpChallenge.findFirst({
      where: { phoneHash, consumedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: "desc" },
    });
    const providedHash = this.crypto.hashToken(`${phoneHash}:${dto.code}`);
    if (
      !challenge ||
      challenge.attemptCount >= MAX_CODE_ATTEMPTS ||
      !this.crypto.constantTimeEqual(challenge.codeHash, providedHash)
    ) {
      if (challenge) {
        await this.prisma.otpChallenge.update({
          where: { id: challenge.id },
          data: { attemptCount: { increment: 1 } },
        });
      }
      throw new UnauthorizedException("Invalid or expired code");
    }

    const birthDate = new Date(dto.birthDate);
    const age = differenceInYears(new Date(), birthDate);
    if (age < 14) throw new ForbiddenException("Minimum age is 14");
    if (age > 120) throw new BadRequestException("Invalid birth date");

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
          profileCompletedAt: new Date(),
          profile: {
            create: {
              displayName: dto.displayName.trim(),
              privacySettings: { exactLocationDefault: false },
            },
          },
        },
        include: { profile: true },
      });
      this.assertActiveUser(user.status);
      const created = await this.createSession(tx, user.id, dto, ip, userAgent);
      return { user, ...created };
    });
    return this.tokenResponse(
      result.user.id,
      result.sessionId,
      result.refreshToken,
      result.user.limitedMode,
      this.profileComplete(result.user),
    );
  }

  async requestEmailCode(dto: RequestEmailCodeDto, ip: string) {
    return this.issueEmailCode(dto.email, ip, EmailLoginCodePurpose.LOGIN);
  }

  async resendEmailCode(dto: RequestEmailCodeDto, ip: string) {
    return this.issueEmailCode(dto.email, ip, EmailLoginCodePurpose.LOGIN);
  }

  async verifyEmailCode(
    dto: VerifyEmailCodeDto,
    ip: string,
    userAgent?: string,
  ) {
    const email = this.normalizeEmail(dto.email);
    const emailHash = this.crypto.hashEmail(email);
    const result = await this.prisma.$transaction(async (tx) => {
      await this.consumeEmailCode(
        tx,
        emailHash,
        dto.code,
        EmailLoginCodePurpose.LOGIN,
      );
      const user = await this.findOrCreateEmailUser(tx, email, emailHash);
      this.assertActiveUser(user.status);
      const created = await this.createSession(tx, user.id, dto, ip, userAgent);
      return { user, ...created };
    });
    return this.tokenResponse(
      result.user.id,
      result.sessionId,
      result.refreshToken,
      result.user.limitedMode,
      this.profileComplete(result.user),
    );
  }

  async signInWithGoogle(dto: GoogleAuthDto, ip: string, userAgent?: string) {
    const ipHash = this.crypto.hashIp(ip);
    const allowed = await this.redis.take(`auth:google:ip:${ipHash}`, 10, 60);
    if (!allowed) {
      throw new HttpException(
        "Too many Google sign-in attempts",
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    const googleIdentity = await this.google.verify(dto.idToken);
    const email = this.normalizeEmail(googleIdentity.email);
    const emailHash = this.crypto.hashEmail(email);
    const subjectHash = this.crypto.hashToken(
      `google:${googleIdentity.subject}`,
    );
    const result = await this.prisma.$transaction(async (tx) => {
      const existingIdentity = await tx.authIdentity.findUnique({
        where: {
          provider_subjectHash: {
            provider: AuthIdentityProvider.GOOGLE,
            subjectHash,
          },
        },
        include: { user: { include: { profile: true } } },
      });
      let user = existingIdentity?.user;
      if (!user) {
        user = await this.findOrCreateEmailUser(tx, email, emailHash);
        await tx.authIdentity.create({
          data: {
            userId: user.id,
            provider: AuthIdentityProvider.GOOGLE,
            subjectHash,
          },
        });
      }
      this.assertActiveUser(user.status);
      const created = await this.createSession(tx, user.id, dto, ip, userAgent);
      return { user, ...created };
    });
    return this.tokenResponse(
      result.user.id,
      result.sessionId,
      result.refreshToken,
      result.user.limitedMode,
      this.profileComplete(result.user),
    );
  }

  async requestEmailIdentityLink(
    userId: string,
    dto: RequestEmailCodeDto,
    ip: string,
  ) {
    return this.issueEmailCode(
      dto.email,
      ip,
      EmailLoginCodePurpose.LINK_IDENTITY,
      userId,
    );
  }

  async verifyEmailIdentityLink(userId: string, dto: VerifyEmailCodeDto) {
    const email = this.normalizeEmail(dto.email);
    const emailHash = this.crypto.hashEmail(email);
    return this.prisma.$transaction(async (tx) => {
      await this.consumeEmailCode(
        tx,
        emailHash,
        dto.code,
        EmailLoginCodePurpose.LINK_IDENTITY,
        userId,
      );
      const emailIdentity = await tx.authIdentity.findUnique({
        where: {
          provider_subjectHash: {
            provider: AuthIdentityProvider.EMAIL,
            subjectHash: emailHash,
          },
        },
      });
      if (emailIdentity && emailIdentity.userId !== userId) {
        throw new ConflictException("Email is linked to another account");
      }
      const emailOwner = await tx.user.findUnique({ where: { emailHash } });
      if (emailOwner && emailOwner.id !== userId) {
        throw new ConflictException("Email is linked to another account");
      }
      await tx.user.update({
        where: { id: userId },
        data: {
          emailHash,
          emailCiphertext: this.crypto.encryptPii(email),
          emailVerifiedAt: new Date(),
        },
      });
      return tx.authIdentity.upsert({
        where: {
          provider_subjectHash: {
            provider: AuthIdentityProvider.EMAIL,
            subjectHash: emailHash,
          },
        },
        update: {},
        create: {
          userId,
          provider: AuthIdentityProvider.EMAIL,
          subjectHash: emailHash,
        },
        select: { provider: true, createdAt: true },
      });
    });
  }

  async linkGoogleIdentity(userId: string, idToken: string) {
    const googleIdentity = await this.google.verify(idToken);
    const subjectHash = this.crypto.hashToken(
      `google:${googleIdentity.subject}`,
    );
    const existing = await this.prisma.authIdentity.findUnique({
      where: {
        provider_subjectHash: {
          provider: AuthIdentityProvider.GOOGLE,
          subjectHash,
        },
      },
    });
    if (existing && existing.userId !== userId) {
      throw new ConflictException("Google account is linked to another user");
    }
    return this.prisma.authIdentity.upsert({
      where: {
        provider_subjectHash: {
          provider: AuthIdentityProvider.GOOGLE,
          subjectHash,
        },
      },
      update: {},
      create: {
        userId,
        provider: AuthIdentityProvider.GOOGLE,
        subjectHash,
      },
      select: { provider: true, createdAt: true },
    });
  }

  async completeProfile(userId: string, dto: CompleteProfileDto) {
    const username = dto.username.trim().toLowerCase();
    return this.prisma.$transaction(async (tx) => {
      const profile = await tx.userProfile.upsert({
        where: { userId },
        update: { displayName: dto.displayName.trim() },
        create: {
          userId,
          displayName: dto.displayName.trim(),
          privacySettings: { exactLocationDefault: false },
        },
        select: { displayName: true, emoji: true, bio: true },
      });
      await tx.user.update({
        where: { id: userId },
        data: { username, profileCompletedAt: new Date() },
      });
      return { ...profile, username, profileComplete: true };
    });
  }

  async identities(userId: string) {
    return this.prisma.authIdentity.findMany({
      where: { userId },
      select: { provider: true, createdAt: true, updatedAt: true },
      orderBy: { createdAt: "asc" },
    });
  }

  async unlinkIdentity(userId: string, provider: string) {
    if (
      !Object.values(AuthIdentityProvider).includes(
        provider as AuthIdentityProvider,
      )
    ) {
      throw new BadRequestException("Unknown identity provider");
    }
    const identities = await this.prisma.authIdentity.findMany({
      where: { userId },
      select: { id: true, provider: true },
    });
    const identity = identities.find((item) => item.provider === provider);
    if (!identity) throw new BadRequestException("Identity not found");
    if (identities.length < 2) {
      throw new BadRequestException(
        "At least one sign-in identity is required",
      );
    }
    await this.prisma.authIdentity.delete({ where: { id: identity.id } });
    return { success: true };
  }

  async refresh(raw: string, ip: string) {
    const hash = this.crypto.hashToken(raw);
    const tracked = await this.prisma.refreshToken.findUnique({
      where: { tokenHash: hash },
      select: { id: true, sessionId: true },
    });
    if (tracked) return this.rotateTrackedRefresh(tracked.id, hash, ip);

    // Existing sessions from before this migration rotate once into the tracked
    // model. They remain usable, while every subsequent token gains reuse detection.
    const legacy = await this.prisma.authSession.findFirst({
      where: {
        refreshTokenHash: hash,
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
      include: { user: { include: { profile: true } } },
    });
    if (!legacy || legacy.user.status !== "ACTIVE") {
      throw new UnauthorizedException("Invalid refresh token");
    }
    const replacement = this.tokens.issueRefresh();
    const now = new Date();
    const updated = await this.prisma.authSession.updateMany({
      where: { id: legacy.id, refreshTokenHash: hash, revokedAt: null },
      data: {
        refreshTokenHash: replacement.hash,
        rotationCounter: { increment: 1 },
        lastUsedAt: now,
        ipHash: this.crypto.hashIp(ip),
      },
    });
    if (updated.count !== 1) {
      await this.revokeFamily(legacy.tokenFamilyId, "refresh_token_reuse");
      await this.audit.write({
        actorUserId: legacy.userId,
        action: "auth.refresh_reuse_detected",
        resourceType: "token_family",
        resourceId: legacy.tokenFamilyId,
        result: "denied",
        ipHash: this.crypto.hashIp(ip),
      });
      throw new UnauthorizedException("Refresh token reuse detected");
    }
    await this.prisma.refreshToken.create({
      data: {
        sessionId: legacy.id,
        tokenHash: replacement.hash,
        expiresAt: legacy.expiresAt,
      },
    });
    return this.tokenResponse(
      legacy.userId,
      legacy.id,
      replacement.raw,
      legacy.user.limitedMode,
      this.profileComplete(legacy.user),
    );
  }

  async logout(userId: string, rawRefresh: string) {
    const tokenHash = this.crypto.hashToken(rawRefresh);
    const tracked = await this.prisma.refreshToken.findUnique({
      where: { tokenHash },
      select: { session: { select: { id: true, userId: true } } },
    });
    if (tracked?.session.userId === userId) {
      await this.revokeSession(userId, tracked.session.id, "logout");
      return { success: true };
    }
    await this.prisma.authSession.updateMany({
      where: { userId, refreshTokenHash: tokenHash, revokedAt: null },
      data: { revokedAt: new Date(), revokeReason: "logout" },
    });
    return { success: true };
  }

  async logoutAll(userId: string) {
    const sessions = await this.prisma.authSession.findMany({
      where: { userId, revokedAt: null },
      select: { tokenFamilyId: true },
    });
    await Promise.all(
      sessions.map((session) =>
        this.revokeFamily(session.tokenFamilyId, "logout_all"),
      ),
    );
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
          select: {
            platform: true,
            label: true,
            installationId: true,
            appVersion: true,
          },
        },
      },
      orderBy: { lastUsedAt: "desc" },
    });
  }

  async revokeSession(
    userId: string,
    sessionId: string,
    reason = "user_revoked",
  ) {
    const session = await this.prisma.authSession.findFirst({
      where: { id: sessionId, userId, revokedAt: null },
      select: { tokenFamilyId: true },
    });
    if (!session) throw new BadRequestException("Session not found");
    await this.revokeFamily(session.tokenFamilyId, reason);
    return { success: true };
  }

  private async issueEmailCode(
    rawEmail: string,
    ip: string,
    purpose: EmailLoginCodePurpose,
    requestedByUserId?: string,
  ) {
    const email = this.normalizeEmail(rawEmail);
    const emailHash = this.crypto.hashEmail(email);
    const ipHash = this.crypto.hashIp(ip);
    const [emailAllowed, ipAllowed] = await Promise.all([
      this.redis.take(`auth:email-code:email:${emailHash}`, 1, 60),
      this.redis.take(`auth:email-code:ip:${ipHash}`, 5, 60),
    ]);
    if (!emailAllowed || !ipAllowed) return GENERIC_CODE_RESPONSE;
    const minuteAgo = new Date(Date.now() - 60_000);
    const [emailRecent, ipRecent] = await Promise.all([
      this.prisma.emailLoginCode.count({
        where: { emailHash, createdAt: { gte: minuteAgo } },
      }),
      this.prisma.emailLoginCode.count({
        where: { requestIpHash: ipHash, createdAt: { gte: minuteAgo } },
      }),
    ]);
    if (emailRecent > 0 || ipRecent >= 5) return GENERIC_CODE_RESPONSE;

    const code = String(randomInt(100000, 1_000_000));
    await this.prisma.$transaction(async (tx) => {
      await tx.emailLoginCode.updateMany({
        where: {
          emailHash,
          purpose,
          requestedByUserId: requestedByUserId ?? null,
          consumedAt: null,
        },
        data: { consumedAt: new Date() },
      });
      await tx.emailLoginCode.create({
        data: {
          emailHash,
          codeHash: this.crypto.hashToken(`${emailHash}:${code}`),
          purpose,
          requestedByUserId,
          requestIpHash: ipHash,
          expiresAt: this.codeExpiry(),
        },
      });
    });
    await this.email.sendLoginCode(email, code);
    return GENERIC_CODE_RESPONSE;
  }

  private async consumeEmailCode(
    tx: Prisma.TransactionClient,
    emailHash: string,
    code: string,
    purpose: EmailLoginCodePurpose,
    requestedByUserId?: string,
  ) {
    const challenge = await tx.emailLoginCode.findFirst({
      where: {
        emailHash,
        purpose,
        requestedByUserId: requestedByUserId ?? null,
        consumedAt: null,
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: "desc" },
    });
    const providedHash = this.crypto.hashToken(`${emailHash}:${code}`);
    if (
      !challenge ||
      challenge.attemptCount >= MAX_CODE_ATTEMPTS ||
      !this.crypto.constantTimeEqual(challenge.codeHash, providedHash)
    ) {
      if (challenge) {
        await tx.emailLoginCode.update({
          where: { id: challenge.id },
          data: { attemptCount: { increment: 1 } },
        });
      }
      throw new UnauthorizedException("Invalid or expired code");
    }
    await tx.emailLoginCode.update({
      where: { id: challenge.id },
      data: { consumedAt: new Date() },
    });
  }

  private async findOrCreateEmailUser(
    tx: Prisma.TransactionClient,
    email: string,
    emailHash: string,
  ) {
    const emailIdentity = await tx.authIdentity.findUnique({
      where: {
        provider_subjectHash: {
          provider: AuthIdentityProvider.EMAIL,
          subjectHash: emailHash,
        },
      },
      include: { user: { include: { profile: true } } },
    });
    if (emailIdentity) return emailIdentity.user;

    const existing = await tx.user.findUnique({
      where: { emailHash },
      include: { profile: true },
    });
    if (existing) {
      await tx.authIdentity.create({
        data: {
          userId: existing.id,
          provider: AuthIdentityProvider.EMAIL,
          subjectHash: emailHash,
        },
      });
      return existing;
    }
    return tx.user.create({
      data: {
        emailHash,
        emailCiphertext: this.crypto.encryptPii(email),
        emailVerifiedAt: new Date(),
        identities: {
          create: {
            provider: AuthIdentityProvider.EMAIL,
            subjectHash: emailHash,
          },
        },
      },
      include: { profile: true },
    });
  }

  private async createSession(
    tx: Prisma.TransactionClient,
    userId: string,
    deviceInput: DeviceInput,
    ip: string,
    userAgent?: string,
  ) {
    const now = new Date();
    const expiresAt = new Date(
      now.getTime() +
        Number(this.config.get("REFRESH_TOKEN_TTL_DAYS") ?? 30) * 86_400_000,
    );
    const device = await tx.device.upsert({
      where: {
        userId_installationId: {
          userId,
          installationId: deviceInput.installationId,
        },
      },
      update: {
        lastSeenAt: now,
        label: deviceInput.deviceLabel,
        appVersion: deviceInput.appVersion,
      },
      create: {
        userId,
        installationId: deviceInput.installationId,
        platform: deviceInput.platform,
        label: deviceInput.deviceLabel,
        appVersion: deviceInput.appVersion,
      },
    });
    const refresh = this.tokens.issueRefresh();
    const session = await tx.authSession.create({
      data: {
        userId,
        deviceId: device.id,
        tokenFamilyId: randomUUID(),
        refreshTokenHash: refresh.hash,
        ipHash: this.crypto.hashIp(ip),
        userAgent: userAgent?.slice(0, 255),
        appVersion: deviceInput.appVersion,
        expiresAt,
        refreshTokens: {
          create: { tokenHash: refresh.hash, expiresAt },
        },
      },
    });
    return { sessionId: session.id, refreshToken: refresh.raw };
  }

  private async rotateTrackedRefresh(
    tokenId: string,
    tokenHash: string,
    ip: string,
  ) {
    const result = await this.prisma.$transaction(async (tx) => {
      const token = await tx.refreshToken.findUnique({
        where: { id: tokenId },
        include: {
          session: { include: { user: { include: { profile: true } } } },
        },
      });
      if (!token) return { kind: "invalid" as const };
      const session = token.session;
      const invalid =
        token.tokenHash !== tokenHash ||
        token.usedAt !== null ||
        token.revokedAt !== null ||
        token.expiresAt <= new Date() ||
        session.revokedAt !== null ||
        session.expiresAt <= new Date() ||
        session.user.status !== "ACTIVE";
      if (invalid) {
        await this.revokeFamilyTx(
          tx,
          session.tokenFamilyId,
          "refresh_token_reuse",
        );
        return {
          kind: "reuse" as const,
          userId: session.userId,
          familyId: session.tokenFamilyId,
        };
      }
      const now = new Date();
      const consumed = await tx.refreshToken.updateMany({
        where: { id: token.id, usedAt: null, revokedAt: null },
        data: { usedAt: now, revokedAt: now },
      });
      if (consumed.count !== 1) {
        await this.revokeFamilyTx(
          tx,
          session.tokenFamilyId,
          "refresh_token_reuse",
        );
        return {
          kind: "reuse" as const,
          userId: session.userId,
          familyId: session.tokenFamilyId,
        };
      }
      const replacement = this.tokens.issueRefresh();
      const replacementToken = await tx.refreshToken.create({
        data: {
          sessionId: session.id,
          tokenHash: replacement.hash,
          expiresAt: session.expiresAt,
        },
      });
      await tx.refreshToken.update({
        where: { id: token.id },
        data: { replacedById: replacementToken.id },
      });
      await tx.authSession.update({
        where: { id: session.id },
        data: {
          refreshTokenHash: replacement.hash,
          rotationCounter: { increment: 1 },
          lastUsedAt: now,
          ipHash: this.crypto.hashIp(ip),
        },
      });
      return {
        kind: "success" as const,
        userId: session.userId,
        sessionId: session.id,
        refreshToken: replacement.raw,
        limitedMode: session.user.limitedMode,
        profileComplete: this.profileComplete(session.user),
      };
    });
    if (result.kind === "reuse") {
      await this.audit.write({
        actorUserId: result.userId,
        action: "auth.refresh_reuse_detected",
        resourceType: "token_family",
        resourceId: result.familyId,
        result: "denied",
        ipHash: this.crypto.hashIp(ip),
      });
      throw new UnauthorizedException("Refresh token reuse detected");
    }
    if (result.kind === "invalid") {
      throw new UnauthorizedException("Invalid refresh token");
    }
    return this.tokenResponse(
      result.userId,
      result.sessionId,
      result.refreshToken,
      result.limitedMode,
      result.profileComplete,
    );
  }

  private async revokeFamily(familyId: string, reason: string) {
    await this.prisma.$transaction((tx) =>
      this.revokeFamilyTx(tx, familyId, reason),
    );
  }

  private async revokeFamilyTx(
    tx: Prisma.TransactionClient,
    familyId: string,
    reason: string,
  ) {
    const now = new Date();
    await tx.authSession.updateMany({
      where: { tokenFamilyId: familyId, revokedAt: null },
      data: { revokedAt: now, revokeReason: reason },
    });
    await tx.refreshToken.updateMany({
      where: { session: { tokenFamilyId: familyId }, revokedAt: null },
      data: { revokedAt: now },
    });
  }

  private tokenResponse(
    userId: string,
    sessionId: string,
    refreshToken: string,
    limitedMode: boolean,
    profileComplete: boolean,
  ) {
    return {
      accessToken: this.tokens.issueAccess(userId, sessionId),
      refreshToken,
      expiresIn: Number(this.config.get("ACCESS_TOKEN_TTL_SECONDS") ?? 900),
      user: { id: userId, limitedMode, profileComplete },
    };
  }

  private profileComplete(user: {
    profileCompletedAt: Date | null;
    profile?: unknown;
  }) {
    return user.profileCompletedAt !== null || Boolean(user.profile);
  }

  private assertActiveUser(status: string) {
    if (status !== "ACTIVE")
      throw new ForbiddenException("Account is unavailable");
  }

  private codeExpiry() {
    return new Date(
      Date.now() +
        Number(this.config.get("EMAIL_CODE_TTL_SECONDS") ?? 600) * 1000,
    );
  }

  private normalizeEmail(input: string): string {
    const email = input.trim().toLowerCase();
    if (
      !email ||
      email.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
    ) {
      throw new BadRequestException("Invalid email address");
    }
    return email;
  }

  private normalizePhone(input: string): string {
    const parsed = parsePhoneNumberFromString(input, "RU");
    if (!parsed?.isValid())
      throw new BadRequestException("Invalid phone number");
    return parsed.number;
  }

  private assertLegacySmsTestMode() {
    if (this.config.get("ALLOW_LEGACY_SMS_TEST_MODE") !== "true") {
      throw new ForbiddenException("Legacy SMS authentication is test-only");
    }
  }

  private legacyTestCode() {
    const configured = this.config.get<string>("DEV_OTP_CODE");
    if (!configured || this.config.get("NODE_ENV") === "production") {
      throw new ForbiddenException("Legacy SMS authentication is test-only");
    }
    return configured;
  }
}
