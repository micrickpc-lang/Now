import { Body, Controller, Delete, Get, Param, Patch, Post } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { Throttle } from "@nestjs/throttler";
import { CurrentAuth } from "../../common/http";
import {
  CreateExactLocationShareDto,
  UpdateExactLocationShareDto,
} from "./location-sharing.dto";
import { LocationSharingService } from "./location-sharing.service";

@ApiTags("exact-location-sharing")
@ApiBearerAuth()
@Controller("location-shares")
export class LocationSharingController {
  constructor(private readonly shares: LocationSharingService) {}

  @Get("mine")
  mine(@CurrentAuth() auth: { userId: string }) {
    return this.shares.mine(auth.userId);
  }

  @Get("visible")
  visible(@CurrentAuth() auth: { userId: string }) {
    return this.shares.visibleTo(auth.userId);
  }

  @Post()
  create(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: CreateExactLocationShareDto,
  ) {
    return this.shares.create(auth.userId, dto);
  }

  @Patch(":id")
  @Throttle({ default: { limit: 12, ttl: 60_000 } })
  update(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
    @Body() dto: UpdateExactLocationShareDto,
  ) {
    return this.shares.update(auth.userId, id, dto);
  }

  @Delete(":id")
  revoke(@CurrentAuth() auth: { userId: string }, @Param("id") id: string) {
    return this.shares.revoke(auth.userId, id);
  }
}
