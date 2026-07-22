import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import type { Request } from "express";
import { TokenService } from "../features/auth/token.service";
import type { AuthenticatedRequest } from "./http";
import { PrismaService } from "./prisma.service";

@Injectable()
export class AccessTokenGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly tokens: TokenService,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (
      this.reflector.getAllAndOverride<boolean>("public", [
        context.getHandler(),
        context.getClass(),
      ])
    ) {
      return true;
    }
    const request = context.switchToHttp().getRequest<Request>();
    const header = request.headers.authorization;
    if (!header?.startsWith("Bearer "))
      throw new UnauthorizedException("Authentication required");
    const payload = this.tokens.verifyAccess(header.slice(7));
    const session = await this.prisma.authSession.findFirst({
      where: {
        id: payload.sid,
        userId: payload.sub,
        revokedAt: null,
        expiresAt: { gt: new Date() },
        user: { status: "ACTIVE" },
      },
      select: { id: true },
    });
    if (!session)
      throw new UnauthorizedException("Session is no longer active");
    (request as AuthenticatedRequest).auth = {
      userId: payload.sub,
      sessionId: payload.sid,
    };
    return true;
  }
}
