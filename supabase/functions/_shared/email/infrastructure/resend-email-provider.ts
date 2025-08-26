import { EmailOptions, EmailProvider } from "../domain/email-provider.ts";

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || '';
const EMAIL_FROM = 'u-desk@ubits.co';

export class ResendEmailProvider extends EmailProvider {

  constructor() {
    super();
  }

  async sendEmail({ to, subject, html, from }: EmailOptions): Promise<void> {
    try {
      const response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${RESEND_API_KEY}`
        },
        body: JSON.stringify({
          from: from || EMAIL_FROM,
          to,
          subject,
          html
        })
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(`Failed to send email: ${JSON.stringify(error)}`);
      }

      const data = await response.json();
      console.log("Email sent successfully:", data.id);
    } catch (error) {
      console.error("Error sending email:", error);
      throw error;
    }
  }
}
