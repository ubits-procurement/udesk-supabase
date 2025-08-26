export interface EmailOptions {
  to: string;
  subject: string;
  html: string;
  from?: string;
}

export abstract class EmailProvider {
  abstract sendEmail(options: EmailOptions): Promise<void>;
}
