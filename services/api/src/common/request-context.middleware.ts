import { Injectable } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import type { NextFunction, Request, Response } from "express";

export interface RequestWithContext extends Request {
  requestId: string;
  auth?: { userId: string; sessionId: string };
}

const safeRequestId = /^[A-Za-z0-9][A-Za-z0-9._-]{7,127}$/u;

@Injectable()
export class RequestContextMiddleware {
  use(request: RequestWithContext, response: Response, next: NextFunction) {
    const incoming = request.header("x-request-id");
    request.requestId =
      incoming && safeRequestId.test(incoming) ? incoming : randomUUID();
    response.setHeader("X-Request-Id", request.requestId);
    next();
  }
}
