// jwt-compression.service.ts

import { Injectable } from '@angular/core';
import * as pako from 'pako';
import * as base64url from 'base64url';

@Injectable({
  providedIn: 'root'
})
export class JwtCompressionService {
  
  /**
   * Compresses and encodes the JWT token.
   * @param token The original JWT token.
   * @returns The compressed and Base64 URL-encoded token.
   */
  compressToken(token: string): string {
    // Convert the JWT string to a Uint8Array
    const tokenBytes = new TextEncoder().encode(token);
    
    // Compress the token using pako (gzip)
    const compressed = pako.deflate(tokenBytes);
    
    // Convert the compressed data to a string (binary)
    const compressedString = String.fromCharCode.apply(null, compressed as any);
    
    // Encode the compressed string using Base64 URL-safe encoding
    const encoded = base64url.encode(compressedString);
    
    return encoded;
  }
  
  /**
   * Decompresses and decodes the JWT token.
   * @param encodedToken The compressed and encoded token.
   * @returns The original JWT token.
   */
  decompressToken(encodedToken: string): string {
    // Decode the Base64 URL-safe encoded string
    const compressedString = base64url.toBuffer(encodedToken).toString();
    
    // Convert the compressed string to a Uint8Array
    const compressedBytes = new Uint8Array(compressedString.split('').map(char => char.charCodeAt(0)));
    
    // Decompress the token using pako (gzip)
    const decompressed = pako.inflate(compressedBytes);
    
    // Convert the decompressed bytes back to a string
    const token = new TextDecoder().decode(decompressed);
    
    return token;
  }
}
