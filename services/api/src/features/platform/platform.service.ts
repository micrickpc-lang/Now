import { BadRequestException, Injectable } from "@nestjs/common";
import { CryptoService } from "../../common/crypto.service";
import { PrismaService } from "../../common/prisma.service";

const forbiddenKeys = new Set(
  [
    "phone",
    "name",
    "message",
    "latitude",
    "longitude",
    "coordinates",
    "address",
    "contacts",
    "accessToken",
    "refreshToken",
    "inviteToken",
    "token",
  ].map((key) => key.toLocaleLowerCase("en-US")),
);

@Injectable()
export class PlatformService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly crypto: CryptoService,
  ) {}

  async analytics(
    userId: string,
    name: string,
    properties: Record<string, unknown>,
  ) {
    for (const [key, value] of Object.entries(properties)) {
      if (
        forbiddenKeys.has(key.toLocaleLowerCase("en-US")) ||
        (typeof value === "object" && value !== null)
      ) {
        throw new BadRequestException(
          "Analytics properties contain forbidden data",
        );
      }
      if (typeof value === "string" && value.length > 80)
        throw new BadRequestException("Analytics value too long");
    }
    await this.prisma.analyticsEvent.create({
      data: {
        userId,
        pseudonym: this.crypto.hashToken(`analytics:${userId}`),
        name,
        properties: properties as never,
      },
    });
    return { accepted: true };
  }

  flags() {
    return this.prisma.featureFlag.findMany({
      select: {
        key: true,
        enabled: true,
        payload: true,
        minVersion: true,
        forceUpdate: true,
        updatedAt: true,
      },
    });
  }
}
