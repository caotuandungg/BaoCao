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
