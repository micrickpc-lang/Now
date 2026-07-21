import { Body, Controller, Get, Post } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { CurrentAuth } from "../../common/http";
import { CreateReportDto } from "./moderation.dto";
import { ModerationService } from "./moderation.service";

@ApiTags("reports")
@ApiBearerAuth()
@Controller()
export class ModerationController {
  constructor(private readonly moderation: ModerationService) {}

  @Post("reports")
  create(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: CreateReportDto,
  ) {
    return this.moderation.report(auth.userId, dto);
  }

  @Get("users/me/reports")
  mine(@CurrentAuth() auth: { userId: string }) {
    return this.moderation.listMine(auth.userId);
  }
}
