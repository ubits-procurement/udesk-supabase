import { SupabaseUserRepository } from "../user/infrastructure/repositories/supabase-user.repository.ts";
import { OnTicketAssignedUseCase } from "./application/use-cases/on-ticket-assigned.use-case.ts";
import { ResendEmailProvider } from "./infrastructure/resend-email-provider.ts";

export const onTicketAssignedUseCase = new OnTicketAssignedUseCase(
  new SupabaseUserRepository(),
  new ResendEmailProvider()
);
