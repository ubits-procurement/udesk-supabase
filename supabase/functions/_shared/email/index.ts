import { SupabaseTicketRepository } from "../user/infrastructure/repositories/supabase-ticket.repository.ts";
import { SupabaseUserRepository } from "../user/infrastructure/repositories/supabase-user.repository.ts";
import { OnTicketAssignedUseCase } from "./application/use-cases/on-ticket-assigned.use-case.ts";
import { OnTicketCommentCreatedUseCase } from "./application/use-cases/on-ticket-commend-created.use-case.ts";
import { OnTicketStatusChangeUseCase } from "./application/use-cases/on-ticket-status-change.use-case.ts";
import { ResendEmailProvider } from "./infrastructure/resend-email-provider.ts";

export const onTicketAssignedUseCase = new OnTicketAssignedUseCase(
  new SupabaseUserRepository(),
  new ResendEmailProvider()
);

export const onTicketCommentCreatedUseCase = new OnTicketCommentCreatedUseCase(
  new SupabaseUserRepository(),
  new SupabaseTicketRepository(),
  new ResendEmailProvider()
);

export const onTicketStatusChangeUseCase = new OnTicketStatusChangeUseCase(
  new SupabaseUserRepository(),
  new ResendEmailProvider()
);