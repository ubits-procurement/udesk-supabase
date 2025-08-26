import { UserRepository } from "../../../user/domain/repositories/user-repository.ts";
import { SupabaseUserRepository } from "../../../user/infrastructure/repositories/supabase-user.repository.ts";
import { emailService, EmailService } from "../../email.service.ts";

export class OnTicketAssignedUseCase {
  constructor(
    private readonly userRepository: UserRepository,
    private readonly emailService: EmailService
  ) {}

  async execute(userId: string, ticketId: string) {
    const user = await this.userRepository.getUserById(userId);

    await this.emailService.sendEmail({
      to: user.email,
      subject: "Asignación de Ticket",
      html: this.getTicketAssignmentHtml(
        user.full_name,
        ticketId
      ),
      from: "u-desk@ubits.co",
    });
  }

  private getTicketAssignmentHtml(userName: string, ticketId: string) {
    return `
    <div style="margin: 0; padding: 0; background: linear-gradient(90deg,rgba(7,11,113,1) 0%,rgba(4,44,198,1) 51%,rgba(4,209,248,1) 100%); font-family: Lato, sans-serif; color: #ffffff; border-radius: 12px;">
      <div style="max-width: 600px; margin: 0 auto; padding-top: 48px; text-align: center; color: #ffffff; box-sizing: border-box;">
        <!-- Logo -->
        <img src="https://play-lh.googleusercontent.com/yCV_OTAHeDHt451AY5f5yoIESpvFo2OLvjZlP9sDpZuXyc4FemDSfP5th_-jni8ukg" alt="Logo" width="72"
             style="display: block; margin: 0 auto 20px auto; max-width: 100%; height: auto; border: 0; outline: none; text-decoration: none; border-radius: 12px" />

        <!-- Supheader -->
        <div style="text-align:center; font-size:14px; font-weight:400; letter-spacing:2px; margin-top:27px;">U-Desk</div>

        <!-- Header -->
        <div style="text-align:center; font-size:24px; font-weight:bold; line-height:1.3; margin-top:5px;">Hey ${userName}, parece que te han asignado un Ticket!</div>

        <!-- Paragraph -->
        <div style="text-align:center; font-size:17px; line-height:1.6; font-weight:400; margin-top:15px;">Revisa U-Desk para ver los tickets que te han asignado</div>

        <!-- Button -->
        <div style="text-align:center; margin-top:25px; margin-bottom:5px;">
          <a href="https://u-desk.lovable.app/tickets/${ticketId}" target="_blank" style="background-color: #0819A0;color:#FFFFFF;padding:10px 21px;text-decoration:none;font-size:17px;display:inline-block;border-radius:8px; border: solid 3px #08178e;">Ver Ticket</a>
        </div>

        <!-- App Image -->
        <img src="https://aobhmkfncgyeehdrffce.supabase.co/storage/v1/object/public/emails//55.png" alt="App Preview" width="198"
             style="display: block; margin: 30px auto 0 auto; max-width: 100%; height: auto; border: 0; outline: none; text-decoration: none;" />
      </div>
    </div>
  `;
  }
}

export const onTicketAssignedUseCase = new OnTicketAssignedUseCase(
  new SupabaseUserRepository(),
  emailService
);
