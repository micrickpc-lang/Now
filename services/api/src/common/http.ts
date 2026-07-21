import { createParamDecorator, SetMetadata } from "@nestjs/common";
import type { ExecutionContext } from "@nestjs/common";
import type { Request } from "express";

export interface AuthenticatedRequest extends Request {
  auth: { userId: string; sessionId: string };
}

export const CurrentAuth = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AuthenticatedRequest["auth"] =>
    context.switchToHttp().getRequest<AuthenticatedRequest>().auth,
);

export const Public = () => SetMetadata("public", true);

export function requestIp(request: Request): string {
  return request.ip || request.socket.remoteAddress || "unknown";
}
