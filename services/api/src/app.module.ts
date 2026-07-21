import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { APP_GUARD } from "@nestjs/core";
import { ThrottlerGuard, ThrottlerModule } from "@nestjs/throttler";
import { AccessTokenGuard } from "./common/auth.guard";
import { CommonModule } from "./common/common.module";
import { validateEnvironment } from "./config/environment";
import { AuthModule } from "./features/auth/auth.module";
import { MapsModule } from "./features/maps/maps.module";
import { MemoriesModule } from "./features/memories/memories.module";
import { MediaModule } from "./features/media/media.module";
import { ModerationModule } from "./features/moderation/moderation.module";
import { PlatformModule } from "./features/platform/platform.module";
import { RoomsModule } from "./features/rooms/rooms.module";
import { SignalsModule } from "./features/signals/signals.module";
import { SocialModule } from "./features/social/social.module";
import { UsersModule } from "./features/users/users.module";
import { OperationsModule } from "./operations/operations.module";
import { RealtimeModule } from "./realtime/realtime.module";

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnvironment }),
    ThrottlerModule.forRoot([{ name: "default", ttl: 60_000, limit: 120 }]),
    CommonModule,
    AuthModule,
    UsersModule,
    SocialModule,
    SignalsModule,
    RoomsModule,
    MapsModule,
    MemoriesModule,
    MediaModule,
    ModerationModule,
    PlatformModule,
    RealtimeModule,
    OperationsModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: AccessTokenGuard },
  ],
})
export class AppModule {}
