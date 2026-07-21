import { Body, Controller, Get, Post } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { CurrentAuth } from "../../common/http";
import { CreateMemoryDto } from "./memories.dto";
import { MemoriesService } from "./memories.service";

@ApiTags("memories")
@ApiBearerAuth()
@Controller("memories")
export class MemoriesController {
  constructor(private readonly memories: MemoriesService) {}
  @Get() list(@CurrentAuth() auth: { userId: string }) {
    return this.memories.list(auth.userId);
  }
  @Post() create(
    @CurrentAuth() auth: { userId: string },
    @Body() dto: CreateMemoryDto,
  ) {
    return this.memories.create(auth.userId, dto);
  }
}
