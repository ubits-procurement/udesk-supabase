import { TicketRepository } from "../../../user/domain/repositories/ticket.repository.ts";
import { UserRepository } from "../../../user/domain/repositories/user-repository.ts";
import { EmailProvider } from "../../domain/email-provider.ts";

interface HtmlTemplateProps {
  ticketId: number;
  userTicketCreatorName: string;
  userCommentCreatorName: string;
  userCommentCreatorAvatar: string;
  commentContent: string;
}

export class OnTicketCommentCreatedUseCase {
  constructor(
    private readonly userRepository: UserRepository,
    private readonly ticketRepository: TicketRepository,
    private readonly emailProvider: EmailProvider
  ) {}

  async execute(
    ticketId: number,
    commentContent: string,
    commentCreatedBy: string
  ) {
    const { created_by: ticketCreatorId } =
      await this.ticketRepository.getTicketById(ticketId);

    const userCommentCreator = await this.userRepository.getUserById(
      commentCreatedBy
    );
    const userTicketCreator = await this.userRepository.getUserById(
      ticketCreatorId
    );

    await this.emailProvider.sendEmail({
      to: userTicketCreator.email,
      subject: "Nuevo comentario",
      html: this.getHtmlTemplate({
        ticketId,
        userTicketCreatorName: userTicketCreator.full_name,
        userCommentCreatorName: userCommentCreator.full_name,
        userCommentCreatorAvatar: userCommentCreator.avatar,
        commentContent,
      }),
    });
  }

  private getHtmlTemplate({
    ticketId,
    userTicketCreatorName,
    userCommentCreatorName,
    userCommentCreatorAvatar,
    commentContent,
  }: HtmlTemplateProps) {
    return `
        <div style="margin: 0; padding: 0; background: linear-gradient(90deg,rgba(7,11,113,1) 0%,rgba(4,44,198,1) 51%,rgba(4,209,248,1) 100%); font-family: Lato, sans-serif; color: #ffffff; border-radius: 12px;">
            <div style="max-width: 600px; margin: 0 auto; padding-top: 48px; text-align: center; color: #ffffff; box-sizing: border-box;">
                
                <!-- Logo -->
                <img src="https://play-lh.googleusercontent.com/yCV_OTAHeDHt451AY5f5yoIESpvFo2OLvjZlP9sDpZuXyc4FemDSfP5th_-jni8ukg" alt="Logo" width="72"
                    style="display: block; margin: 0 auto 20px auto; max-width: 100%; height: auto; border: 0; outline: none; text-decoration: none; border-radius: 12px" />

                <!-- Supheader -->
                <div style="text-align:center; font-size:14px; font-weight:400; letter-spacing:2px; margin-top:27px;">U-Desk</div>

                <!-- Header -->
                <div style="text-align:center; font-size:24px; font-weight:bold; line-height:1.3; margin-top:5px;">
                Hey ${userTicketCreatorName}, un comentario ha sido agregado a tu Ticket
                </div>

                <!-- Comment Container -->
                <div style="background-color: rgba(255, 255, 255, 0.1); border-radius: 10px; padding: 20px; margin-top: 25px; text-align: left; display: flex; align-items: flex-start;">
                <img src="${userCommentCreatorAvatar}" alt="User Avatar" width="48" height="48" style="border-radius: 50%; margin-right: 15px; object-fit: cover;" />
                <div style="flex: 1;">
                    <div style="font-size: 16px; font-weight: bold; color: #ffffff; margin-bottom: 8px;">${userCommentCreatorName}</div>
                    <div style="font-size: 15px; line-height: 1.5; color: #ffffff;">${commentContent}</div>
                </div>
                </div>

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
