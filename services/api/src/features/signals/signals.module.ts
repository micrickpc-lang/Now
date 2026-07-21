import { Module } from "@nestjs/common";
import { ContentPolicyService } from "../../common/content-policy.service";
import { RealtimeModule } from "../../realtime/realtime.module";
import { SocialModule } from "../social/social.module";
import { SignalsController } from "./signals.controller";
import { SignalsService } from "./signals.service";

@Module({
  imports: [SocialModule, RealtimeModule],
  controllers: [SignalsController],
  providers: [SignalsService, ContentPolicyService],
  exports: [SignalsService],
})
export class SignalsModule {}
