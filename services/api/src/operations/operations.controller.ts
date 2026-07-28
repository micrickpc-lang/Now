import { Controller, Get, Header } from "@nestjs/common";
import { Public } from "../common/http";
import { PrismaService } from "../common/prisma.service";
import { RedisService } from "../common/redis.service";
import { collectDefaultMetrics, register } from "prom-client";

collectDefaultMetrics({ prefix: "seychas_api_" });

@Controller()
export class OperationsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  @Public()
  @Get("health")
  health() {
    return { status: "ok", time: new Date().toISOString() };
  }

  @Public()
  @Get("ready")
  async ready() {
    await this.prisma.$queryRaw`SELECT 1`;
    await this.redis.ping();
    return { status: "ready" };
  }

  @Public()
  @Get("metrics")
  @Header("Content-Type", register.contentType)
  metrics() {
    return register.metrics();
  }
}
