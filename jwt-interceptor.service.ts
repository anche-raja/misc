// jwt-interceptor.service.ts

import { Injectable } from '@angular/core';
import {
  HttpEvent, HttpInterceptor, HttpHandler, HttpRequest
} from '@angular/common/http';
import { Observable } from 'rxjs';
import { JwtCompressionService } from './jwt-compression.service';
import { AuthService } from './auth.service'; // Replace with your actual AuthService

@Injectable()
export class JwtInterceptor implements HttpInterceptor {

  constructor(
    private jwtCompressionService: JwtCompressionService,
    private authService: AuthService
  ) {}

  intercept(req: HttpRequest<any>, next: HttpHandler): Observable<HttpEvent<any>> {
    // Retrieve the original JWT token from your AuthService or wherever it's stored
    const originalToken = this.authService.getJwtToken();

    if (originalToken) {
      // Compress and encode the JWT token
      const compressedToken = this.jwtCompressionService.compressToken(originalToken);
      
      // Clone the request and add the compressed token to the headers
      const cloned = req.clone({
        headers: req.headers.set('Authorization', `Bearer ${compressedToken}`)
      });

      return next.handle(cloned);
    }

    // If there's no token, proceed without modifying the request
    return next.handle(req);
  }
}
