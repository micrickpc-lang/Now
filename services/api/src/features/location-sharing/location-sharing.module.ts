import { Module } from "@nestjs/common";
import { RealtimeModule } from "../../realtime/realtime.module";
import { LocationSharingController } from "./location-sharing.controller";
import { LocationSharingService } from "./location-sharing.service";

@Module({
  imports: [RealtimeModule],
  controllers: [LocationSharingController],
  providers: [LocationSharingService],
})
export class LocationSharingModule {}
