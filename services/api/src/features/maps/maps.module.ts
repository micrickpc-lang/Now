import { Module } from "@nestjs/common";
import { MapsController } from "./maps.controller";
import { DisabledRoutingProvider } from "./maps.dto";
import { MapsService } from "./maps.service";

@Module({
  controllers: [MapsController],
  providers: [MapsService, DisabledRoutingProvider],
})
export class MapsModule {}
