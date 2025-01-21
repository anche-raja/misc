// app.module.ts

import { HTTP_INTERCEPTORS } from '@angular/common/http';
import { JwtInterceptor } from './jwt-interceptor.service';

@NgModule({
  // ... other imports and declarations
  providers: [
    // ... other providers
    { provide: HTTP_INTERCEPTORS, useClass: JwtInterceptor, multi: true },
  ],
  // ... bootstrap and other configurations
})
export class AppModule { }
