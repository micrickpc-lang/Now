import {
  Controller,
  Get,
  Header,
  ServiceUnavailableException,
} from "@nestjs/common";
import { Public } from "../common/http";
import { PrismaService } from "../common/prisma.service";
import { RedisService } from "../common/redis.service";
import { MapsService } from "../features/maps/maps.service";
import { collectDefaultMetrics, register } from "prom-client";

collectDefaultMetrics({ prefix: "seychas_api_" });

@Controller()
export class OperationsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly maps: MapsService,
  ) {}

  @Public()
  @Get("health")
  health() {
    return { status: "ok", time: new Date().toISOString() };
  }

  @Public()
  @Get("ready")
  async ready() {
    try {
      const [, , maps] = await Promise.all([
        this.prisma.$queryRaw`SELECT 1`,
        this.redis.ping(),
        this.maps.upstreamReadiness(),
      ]);
      return {
        status: "ready",
        dependencies: { database: "ready", redis: "ready", ...maps },
      };
    } catch {
      throw new ServiceUnavailableException("Service dependencies unavailable");
    }
  }

  @Public()
  @Get("metrics")
  @Header("Content-Type", register.contentType)
  metrics() {
    return register.metrics();
  }
}
