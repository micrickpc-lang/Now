import { Module } from "@nestjs/common";
import { OperationsController } from "./operations.controller";

@Module({ controllers: [OperationsController] })
export class OperationsModule {}
