import { Body, Controller, Get, Post } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { CurrentAuth } from "../../common/http";
import { AnalyticsEventDto } from "./platform.dto";
import { PlatformService } from "./platform.service";

@ApiTags("platform")
@ApiBearerAuth()
@Controller()
export class PlatformController {
  constructor(private readonly platform: PlatformService) {}

  @Post("analytics/events")
  event(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: AnalyticsEventDto,
  ) {
    return this.platform.analytics(auth.userId, dto.name, dto.properties);
  }

  @Get("feature-flags")
  flags() {
    return this.platform.flags();
  }
}
