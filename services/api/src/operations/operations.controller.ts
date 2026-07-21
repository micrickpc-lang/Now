import { Controller, Get, Header } from "@nestjs/common";
import { Public } from "../common/http";
import { PrismaService } from "../common/prisma.service";
import { collectDefaultMetrics, register } from "prom-client";

collectDefaultMetrics({ prefix: "seychas_api_" });

@Controller()
export class OperationsController {
  constructor(private readonly prisma: PrismaService) {}

  @Public()
  @Get("health")
  async health() {
    await this.prisma.$queryRaw`SELECT 1`;
    return { status: "ok", time: new Date().toISOString() };
  }

  @Public()
  @Get("ready")
  async ready() {
    await this.prisma.$queryRaw`SELECT 1`;
    return { status: "ready" };
  }

  @Public()
  @Get("metrics")
  @Header("Content-Type", register.contentType)
  metrics() {
    return register.metrics();
  }
}
