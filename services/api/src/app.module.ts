import {
  MiddlewareConsumer,
  Module,
  NestModule,
  RequestMethod,
} from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from "@nestjs/core";
import { ThrottlerGuard, ThrottlerModule } from "@nestjs/throttler";
import { AccessTokenGuard } from "./common/auth.guard";
import { CommonModule } from "./common/common.module";
import { RequestContextMiddleware } from "./common/request-context.middleware";
import { SafeExceptionFilter } from "./common/safe-exception.filter";
import { SafeHttpLoggingInterceptor } from "./common/safe-http.interceptor";
import { validateEnvironment } from "./config/environment";
import { AuthModule } from "./features/auth/auth.module";
import { ConversationsModule } from "./features/conversations/conversations.module";
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
    ConversationsModule,
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
    { provide: APP_FILTER, useClass: SafeExceptionFilter },
    { provide: APP_INTERCEPTOR, useClass: SafeHttpLoggingInterceptor },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer
      .apply(RequestContextMiddleware)
      .forRoutes({ path: "*", method: RequestMethod.ALL });
  }
}
