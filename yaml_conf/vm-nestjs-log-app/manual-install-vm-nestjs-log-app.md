# Huong dan cai thu cong NestJS app tu sinh log tren VM

Gia su ban vua SSH vao VM va chua co app NestJS nao.

## 1. Cai Node.js 20

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -d -m 0755 /etc/apt/keyrings

curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg

echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
  | sudo tee /etc/apt/sources.list.d/nodesource.list

sudo apt-get update
sudo apt-get install -y nodejs

node -v
npm -v
```

## 2. Cai NestJS CLI va tao app moi

```bash
sudo npm i -g @nestjs/cli
cd /opt
sudo nest new dung-nestjs-log-app
```

Khi NestJS hoi package manager, chon:

```text
npm
```

## 3. Cap quyen de sua source

```bash
sudo chown -R $USER:$USER /opt/dung-nestjs-log-app
cd /opt/dung-nestjs-log-app
```

## 4. Sua `src/main.ts`

```bash
cat > src/main.ts <<'EOF'
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    logger: ['log', 'error', 'warn', 'debug'],
  });

  const port = Number(process.env.PORT || 3000);
  await app.listen(port, '0.0.0.0');
  Logger.log(`NestJS log app listening on port=${port}`, 'Bootstrap');
}

bootstrap();
EOF
```

## 5. Tao controller sinh log theo API

```bash
cat > src/app.controller.ts <<'EOF'
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
EOF
```

## 6. Tao interceptor ghi log moi request HTTP

```bash
cat > src/raw-http-logging.interceptor.ts <<'EOF'
import {
  CallHandler,
  ExecutionContext,
  Injectable,
  Logger,
  NestInterceptor,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { catchError, tap } from 'rxjs/operators';

@Injectable()
export class RawHttpLoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger('HTTP');

  intercept(context: ExecutionContext, next: CallHandler) {
    const http = context.switchToHttp();
    const request = http.getRequest<Request>();
    const response = http.getResponse<Response>();
    const startedAt = Date.now();

    return next.handle().pipe(
      tap(() => {
        const durationMs = Date.now() - startedAt;
        this.logger.log(
          `${request.method} ${request.originalUrl || request.url} ${response.statusCode} ${durationMs}ms`,
        );
      }),
      catchError((error) => {
        const durationMs = Date.now() - startedAt;
        const statusCode = error?.status || error?.statusCode || 500;
        this.logger.error(
          `${request.method} ${request.originalUrl || request.url} ${statusCode} ${durationMs}ms error="${error.message}"`,
        );
        throw error;
      }),
    );
  }
}
EOF
```

## 7. Tao service tu sinh log nen moi 5 giay

```bash
cat > src/synthetic-events.service.ts <<'EOF'
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
EOF
```

## 8. Sua `src/app.module.ts`

```bash
cat > src/app.module.ts <<'EOF'
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
EOF
```

## 9. Chay thu app bang npm

```bash
npm run start
```

Mo terminal khac tren VM va test:

```bash
curl http://localhost:3000/health
curl http://localhost:3000/orders
curl -X POST http://localhost:3000/orders
curl http://localhost:3000/slow-query
curl http://localhost:3000/payment/error
```

Dung app bang:

```text
Ctrl + C
```

## 10. Build app de chay production

```bash
npm run build
npm prune --omit=dev
```

## 11. Tao thu muc log

```bash
sudo mkdir -p /var/log/dung-lab
```

## 12. Tao systemd service

```bash
sudo tee /etc/systemd/system/dung-nestjs-log-app.service >/dev/null <<'EOF'
[Unit]
Description=Dung NestJS raw log app
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/dung-nestjs-log-app
Environment=NODE_ENV=production
Environment=NO_COLOR=1
Environment=PORT=3000
ExecStart=/usr/bin/node /opt/dung-nestjs-log-app/dist/main.js
Restart=always
RestartSec=3
StandardOutput=append:/var/log/dung-lab/nestjs.log
StandardError=append:/var/log/dung-lab/nestjs.err.log

[Install]
WantedBy=multi-user.target
EOF
```

## 13. Bat va chay service

```bash
sudo systemctl daemon-reload
sudo systemctl enable dung-nestjs-log-app.service
sudo systemctl restart dung-nestjs-log-app.service
sudo systemctl status dung-nestjs-log-app.service
```

## 14. Test service va xem log

```bash
curl http://localhost:3000/health
curl http://localhost:3000/orders
curl -X POST http://localhost:3000/orders
curl http://localhost:3000/slow-query
curl http://localhost:3000/payment/error
```

```bash
sudo tail -f /var/log/dung-lab/nestjs.log
sudo tail -f /var/log/dung-lab/nestjs.err.log
```

Neu muon truy cap tu may khac, dung IP cua VM:

```text
http://<IP-VM>:3000/health
```

## 15. Apply lai sau khi sua logic code

Moi lan sua code trong thu muc `/opt/dung-nestjs-log-app/src`, chay lai:

```bash
cd /opt/dung-nestjs-log-app
npm run build
sudo systemctl restart dung-nestjs-log-app.service
sudo systemctl status dung-nestjs-log-app.service
```

Test lai app:

```bash
curl http://localhost:3000/health
sudo tail -f /var/log/dung-lab/nestjs.log
```

Neu co sua `package.json` de them dependency moi, chay them `npm install` truoc khi build:

```bash
cd /opt/dung-nestjs-log-app
npm install
npm run build
sudo systemctl restart dung-nestjs-log-app.service
```
