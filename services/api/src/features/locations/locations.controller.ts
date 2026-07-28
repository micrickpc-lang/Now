import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Put,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { CurrentAuth } from "../../common/http";
import {
  CreateGlobalLocationShareDto,
  UpdateMyLocationDto,
} from "./locations.dto";
import { LocationsService } from "./locations.service";

@ApiBearerAuth()
@ApiTags("locations")
@Controller()
export class LocationsController {
  constructor(private readonly locations: LocationsService) {}

  @Put("locations/me")
  updateMyLocation(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: UpdateMyLocationDto,
  ) {
    return this.locations.updateMyLocation(auth.userId, dto);
  }

  @Post("location-shares")
  createShare(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: CreateGlobalLocationShareDto,
  ) {
    return this.locations.createShare(auth.userId, dto);
  }

  @Get("location-shares")
  ownShares(@CurrentAuth() auth: { userId: string }) {
    return this.locations.listOwnShares(auth.userId);
  }

  @Delete("location-shares/:id")
  revokeShare(
    @CurrentAuth() auth: { userId: string },
    @Param("id") id: string,
  ) {
    return this.locations.revokeShare(auth.userId, id);
  }

  @Get("map/friends")
  mapFriends(@CurrentAuth() auth: { userId: string }) {
    return this.locations.mapFriends(auth.userId);
  }
}
