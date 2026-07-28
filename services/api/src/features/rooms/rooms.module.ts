import { forwardRef, Module } from "@nestjs/common";
import { ContentPolicyService } from "../../common/content-policy.service";
import { RealtimeModule } from "../../realtime/realtime.module";
import { RoomsController } from "./rooms.controller";
import { RoomsService } from "./rooms.service";

@Module({
  imports: [forwardRef(() => RealtimeModule)],
  controllers: [RoomsController],
  providers: [RoomsService, ContentPolicyService],
  exports: [RoomsService],
})
export class RoomsModule {}
