import { describe, it, expect, vi, afterEach } from 'vitest';
import { generateTimestamp, urlToDomainSlug } from '../timestamp';

describe('generateTimestamp', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('generates correct UTC timestamp format', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-27T17:12:07Z'));

    expect(generateTimestamp()).toBe('2026-01-27T171207');
  });

  it('zero-pads single-digit months and days', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-03-05T09:01:02Z'));

    expect(generateTimestamp()).toBe('2026-03-05T090102');
  });

  it('handles midnight correctly', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-12-31T00:00:00Z'));

    expect(generateTimestamp()).toBe('2026-12-31T000000');
  });
});

describe('urlToDomainSlug', () => {
  it('converts a simple URL to domain slug', () => {
    expect(urlToDomainSlug('https://www.deobald.ca/page')).toBe('www-deobald-ca');
  });

  it('replaces dots with hyphens', () => {
    expect(urlToDomainSlug('https://savebutton.com')).toBe('savebutton-com');
  });

  it('handles subdomains', () => {
    expect(urlToDomainSlug('https://docs.example.co.uk/path')).toBe('docs-example-co-uk');
  });

  it('returns unknown for invalid URLs', () => {
    expect(urlToDomainSlug('not-a-url')).toBe('unknown');
  });

  it('strips port numbers from hostname', () => {
    expect(urlToDomainSlug('http://localhost:3000/test')).toBe('localhost');
  });
});
