import { TicketRepository } from "../../domain/repositories/ticket.repository.ts";
import { supabaseClient } from "../clients/supabase.client.ts";

export class SupabaseTicketRepository implements TicketRepository {
    constructor() {}

    async getTicketById(id: number): Promise<any | null> {
        const { data, error } = await supabaseClient
            .from("tickets")
            .select()
            .eq("id", id)
            .single();

        if (error) throw error;
        return data;
    }
}