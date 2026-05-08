import { Module } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { AppController } from './app.controller';
import { RawHttpLoggingInterceptor } from './raw-http-logging.interceptor';
import { SyntheticEventsService } from './synthetic-events.service';

@Module({
  controllers: [AppController],
  providers: [
    SyntheticEventsService,
    {
      provide: APP_INTERCEPTOR,
      useClass: RawHttpLoggingInterceptor,
    },
  ],
})
export class AppModule {}
