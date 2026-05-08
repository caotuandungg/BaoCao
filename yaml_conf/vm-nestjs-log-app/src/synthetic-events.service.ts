import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';

@Injectable()
export class SyntheticEventsService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(SyntheticEventsService.name);
  private timer: NodeJS.Timeout | undefined;

  onModuleInit() {
    this.timer = setInterval(() => this.emitEvent(), 5000);
  }

  onModuleDestroy() {
    if (this.timer) {
      clearInterval(this.timer);
    }
  }

  private emitEvent() {
    const roll = Math.random();
    const requestId = `req-${Math.floor(Math.random() * 90000) + 10000}`;

    if (roll < 0.6) {
      this.logger.log(`background job completed job=sync_orders request_id=${requestId}`);
      return;
    }

    if (roll < 0.85) {
      const durationMs = Math.floor(Math.random() * 2500) + 500;
      this.logger.warn(
        `external api latency provider=inventory request_id=${requestId} duration_ms=${durationMs}`,
      );
      return;
    }

    this.logger.error(
      `background job failed job=charge_payment request_id=${requestId} reason=timeout`,
    );
  }
}
