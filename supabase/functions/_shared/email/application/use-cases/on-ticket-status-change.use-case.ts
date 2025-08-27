import { UserRepository } from "../../../user/domain/repositories/user-repository.ts";
import { EmailProvider } from "../../domain/email-provider.ts";

interface HtmlTemplateProps {
  user: {
    userName: string;
  };
  ticket: {
    id: number;
    title: string;
    oldStatus: string;
    newStatus: string;
  };
}

interface TicketStatusChangeProps {
  createdById: string;
  oldStatus: string;
  newStatus: string;
  id: number;
  title: string;
}

export class OnTicketStatusChangeUseCase {
  constructor(
    private readonly userRepository: UserRepository,
    private readonly emailProvider: EmailProvider
  ) {}

  async execute({
    createdById,
    oldStatus,
    newStatus,
    id,
    title,
  }: TicketStatusChangeProps) {
    const user = await this.userRepository.getUserById(createdById);

    await this.emailProvider.sendEmail({
      to: user.email,
      subject: "Cambio de estado",
      html: this.getTicketStatusChangeHtml({
        user: {
          userName: user.full_name,
        },
        ticket: {
          id,
          title,
          oldStatus: this.mapTicketStatus(oldStatus),
          newStatus: this.mapTicketStatus(newStatus),
        },
      }),
      from: "u-desk@ubits.co",
    });
  }

  private getTicketStatusChangeHtml({ user, ticket }: HtmlTemplateProps) {
    return `
    <div style="margin: 0; padding: 0; background: linear-gradient(90deg,rgba(7,11,113,1) 0%,rgba(4,44,198,1) 51%,rgba(4,209,248,1) 100%); font-family: Lato, sans-serif; color: #ffffff; border-radius: 12px;">
        <div style="max-width: 600px; margin: 0 auto; padding-top: 48px; text-align: center; color: #ffffff; box-sizing: border-box;">
            
            <!-- Logo -->
            <img src="https://play-lh.googleusercontent.com/yCV_OTAHeDHt451AY5f5yoIESpvFo2OLvjZlP9sDpZuXyc4FemDSfP5th_-jni8ukg" alt="Logo" width="72"
                style="display: block; margin: 0 auto 20px auto; max-width: 100%; height: auto; border: 0; outline: none; text-decoration: none; border-radius: 12px" />

            <!-- Supheader -->
            <div style="text-align:center; font-size:14px; font-weight:400; letter-spacing:2px; margin-top:27px;">U-Desk</div>

            <!-- Header -->
            <div style="text-align:center; font-size:24px; font-weight:bold; line-height:1.3; margin-top:5px;">Hey ${user.userName}, el estado de <span><a style="color: #FFFFFF" href="https://u-desk.lovable.app/tickets/${ticket.id}">${ticket.title}</a></span> ha cambiado</div>

            <!-- Paragraph -->
            <div style="text-align:center; font-size:17px; line-height:1.6; font-weight:400; margin-top:15px;">Revisa U-Desk para ver los detalles del cambio de estado</div>

            <!-- Estado visual -->
            <div style="text-align:center; margin-top:25px; margin-bottom:10px;">
                <span style="display:inline-block; background:#ffffff; color:#0819A0; padding:8px 16px; border-radius:8px; font-weight:bold; font-size:15px; margin-right:8px;">${ticket.oldStatus}</span>
                <span style="display:inline-block; font-size:16px; font-weight:600; vertical-align:middle;">→</span>
                <span style="display:inline-block; background:#0819A0; color:#ffffff; padding:8px 16px; border-radius:8px; font-weight:bold; font-size:15px; margin-left:8px;">${ticket.newStatus}</span>
            </div>

            <!-- App Image -->
            <img src="https://aobhmkfncgyeehdrffce.supabase.co/storage/v1/object/public/emails//55.png" alt="App Preview" width="198"
                style="display: block; margin: 30px auto 0 auto; max-width: 100%; height: auto; border: 0; outline: none; text-decoration: none;" />
        </div>
    </div>
  `;
  }

  private mapTicketStatus(status: string): string {
    const splitted = status.split('_');

    // Convert to title case
    return splitted.map((word) => word.charAt(0).toUpperCase() + word.slice(1)).join(' ');
  }
}
