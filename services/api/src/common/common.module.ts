import { Global, Module } from "@nestjs/common";
import { CryptoService } from "./crypto.service";
import { PrismaService } from "./prisma.service";
import { AuditService } from "./audit.service";
import {
  MESSAGE_ENCRYPTION_PROVIDER,
  ServerManagedEncryptionProvider,
} from "./message-encryption.provider";

@Global()
@Module({
  providers: [
    PrismaService,
    CryptoService,
    AuditService,
    ServerManagedEncryptionProvider,
    {
      provide: MESSAGE_ENCRYPTION_PROVIDER,
      useExisting: ServerManagedEncryptionProvider,
    },
  ],
  exports: [
    PrismaService,
    CryptoService,
    AuditService,
    MESSAGE_ENCRYPTION_PROVIDER,
  ],
})
export class CommonModule {}
