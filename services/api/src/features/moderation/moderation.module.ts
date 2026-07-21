import { Module } from "@nestjs/common";
import { AdminController } from "./admin.controller";
import { AdminAuthService } from "./admin-auth.service";
import { AdminGuard } from "./admin.guard";
import { ModerationController } from "./moderation.controller";
import { ModerationService } from "./moderation.service";

@Module({
  controllers: [ModerationController, AdminController],
  providers: [ModerationService, AdminAuthService, AdminGuard],
})
export class ModerationModule {}
