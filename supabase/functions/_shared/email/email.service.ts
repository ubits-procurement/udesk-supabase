import { EmailProvider, EmailOptions } from './domain/email-provider.ts';
import { ResendEmailProvider } from './infrastructure/resend-email-provider.ts';

export class EmailService {
  constructor(private readonly provider: EmailProvider) {}

  async sendEmail(options: EmailOptions): Promise<void> {
    await this.provider.sendEmail(options);
  }
}

export const emailService = new EmailService(new ResendEmailProvider());