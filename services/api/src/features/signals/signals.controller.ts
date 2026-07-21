import { Body, Controller, Get, Param, Patch, Post } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { CurrentAuth } from "../../common/http";
import { CreateSignalDto, UpdateSignalDto } from "./signals.dto";
import { SignalsService } from "./signals.service";

@ApiTags("signals")
@ApiBearerAuth()
@Controller("signals")
export class SignalsController {
  constructor(private readonly signals: SignalsService) {}

  @Post()
  create(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: CreateSignalDto,
  ) {
    return this.signals.create(auth.userId, dto);
  }

  @Get("feed")
  feed(@CurrentAuth() auth: { userId: string }) {
    return this.signals.feed(auth.userId);
  }

  @Get(":id")
  get(@CurrentAuth() auth: { userId: string }, @Param("id") id: string) {
    return this.signals.get(auth.userId, id);
  }

  @Patch(":id")
  update(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
    @Body() dto: UpdateSignalDto,
  ) {
    return this.signals.update(auth.userId, id, dto);
  }

  @Post(":id/join")
  join(@CurrentAuth() auth: { userId: string }, @Param("id") id: string) {
    return this.signals.join(auth.userId, id);
  }

  @Post(":id/approve/:userId")
  approve(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
    @Param("userId") userId: string,
  ) {
    return this.signals.decide(auth.userId, id, userId, true);
  }

  @Post(":id/reject/:userId")
  reject(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
    @Param("userId") userId: string,
  ) {
    return this.signals.decide(auth.userId, id, userId, false);
  }

  @Post(":id/cancel")
  cancel(@CurrentAuth() auth: { userId: string }, @Param("id") id: string) {
    return this.signals.cancel(auth.userId, id);
  }

  @Post(":id/complete")
  complete(@CurrentAuth() auth: { userId: string }, @Param("id") id: string) {
    return this.signals.complete(auth.userId, id);
  }
}
