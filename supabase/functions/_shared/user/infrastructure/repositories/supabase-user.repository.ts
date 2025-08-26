import { UserRepository } from "../../domain/repositories/user-repository.ts";
import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || '';

export class SupabaseUserRepository implements UserRepository {
  private client: any;

  constructor() {
    this.client = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  }

  async getUserById(id: string): Promise<any | null> {
    const { data, error } = await this.client
      .from("users")
      .select()
      .eq("id", id)
      .single();

    if (error) throw error;
    return data;
  }
}
