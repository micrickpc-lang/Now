import { Module } from "@nestjs/common";
import { MapsModule } from "../features/maps/maps.module";
import { OperationsController } from "./operations.controller";

@Module({ imports: [MapsModule], controllers: [OperationsController] })
export class OperationsModule {}
