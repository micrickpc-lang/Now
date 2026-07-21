import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { ApiTags } from "@nestjs/swagger";
import type { Request } from "express";
import { Public } from "../../common/http";
import { PrismaService } from "../../common/prisma.service";
import { AdminAuthService } from "./admin-auth.service";
import { AdminGuard, type AdminRequest } from "./admin.guard";
import {
  AdminLoginDto,
  ForbiddenWordDto,
  ModerateReportDto,
} from "./moderation.dto";
import { ModerationService } from "./moderation.service";

@ApiTags("admin")
@Controller("admin")
export class AdminController {
  constructor(
    private readonly auth: AdminAuthService,
    private readonly moderation: ModerationService,
    private readonly prisma: PrismaService,
  ) {}

  @Public()
  @Post("login")
  login(@Body() dto: AdminLoginDto) {
    return this.auth.login(dto.email, dto.password);
  }

  @Public()
  @UseGuards(AdminGuard)
  @Get("reports")
  reports(@Query("state") state?: string) {
    return this.moderation.queue(state);
  }

  @Public()
  @UseGuards(AdminGuard)
  @Post("reports/:id/action")
  action(
    @Req() request: Request,
    @Param("id") id: string,
    @Body() dto: ModerateReportDto,
  ) {
    return this.moderation.moderate(
      (request as AdminRequest).admin.sub,
      id,
      dto,
    );
  }

  @Public()
  @UseGuards(AdminGuard)
  @Get("forbidden-words")
  words() {
    return this.prisma.forbiddenWord.findMany({
      orderBy: { createdAt: "desc" },
    });
  }

  @Public()
  @UseGuards(AdminGuard)
  @Post("forbidden-words")
  addWord(@Body() dto: ForbiddenWordDto) {
    return this.prisma.forbiddenWord.upsert({
      where: { pattern: dto.pattern.toLocaleLowerCase("ru-RU") },
      create: {
        pattern: dto.pattern.toLocaleLowerCase("ru-RU"),
        category: dto.category,
      },
      update: { active: true, category: dto.category },
    });
  }

  @Public()
  @UseGuards(AdminGuard)
  @Get("audit")
  audit() {
    return this.prisma.auditLog.findMany({
      orderBy: { createdAt: "desc" },
      take: 200,
    });
  }
}
