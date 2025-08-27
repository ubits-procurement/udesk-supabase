import { UserRepository } from "../../domain/repositories/user-repository.ts";
import { supabaseClient } from "../clients/supabase.client.ts";

export class SupabaseUserRepository implements UserRepository {
  async getUserById(id: string): Promise<any | null> {
    const { data, error } = await supabaseClient
      .from("users")
      .select()
      .eq("id", id)
      .single();

    if (error) throw error;
    return data;
  }
}
