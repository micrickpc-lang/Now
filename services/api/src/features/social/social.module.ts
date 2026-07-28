import { Module } from "@nestjs/common";
import { RealtimeModule } from "../../realtime/realtime.module";
import { SocialController } from "./social.controller";
import { SocialService } from "./social.service";

@Module({
  imports: [RealtimeModule],
  controllers: [SocialController],
  providers: [SocialService],
  exports: [SocialService],
})
export class SocialModule {}
