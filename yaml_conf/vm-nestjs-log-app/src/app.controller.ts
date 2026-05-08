import {
  Controller,
  Get,
  InternalServerErrorException,
  Logger,
  Post,
} from '@nestjs/common';

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

@Controller()
export class AppController {
  private readonly logger = new Logger(AppController.name);

  @Get('/health')
  health() {
    this.logger.log('health check requested');
    return { status: 'ok' };
  }

  @Get('/orders')
  listOrders() {
    const count = Math.floor(Math.random() * 10) + 1;
    this.logger.log(`loaded orders count=${count}`);
    return { count };
  }

  @Post('/orders')
  createOrder() {
    const orderId = `ord-${Math.floor(Math.random() * 90000) + 10000}`;
    this.logger.log(`created order order_id=${orderId}`);
    return { order_id: orderId, status: 'created' };
  }

  @Get('/slow-query')
  async slowQuery() {
    const durationMs = Math.floor(Math.random() * 1800) + 500;
    await sleep(durationMs);
    this.logger.warn(`slow query detected table=orders duration_ms=${durationMs}`);
    return { duration_ms: durationMs };
  }

  @Get('/payment/error')
  paymentError() {
    const requestId = `req-${Math.floor(Math.random() * 90000) + 10000}`;
    this.logger.error(
      `payment gateway timeout request_id=${requestId} provider=mockpay`,
    );
    throw new InternalServerErrorException('Payment gateway timeout');
  }
}
