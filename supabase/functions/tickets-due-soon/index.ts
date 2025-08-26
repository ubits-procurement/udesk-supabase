import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};
// Setup client
const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const supabase = createClient(supabaseUrl, supabaseKey);
serve(async (req)=>{
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: corsHeaders
    });
  }
  // Fetch tickets próximos a vencerse (en las próximas 24h), aún abiertos y no notificados
  const { data: tickets, error } = await supabase.from("tickets").select("id, title, description, assigned_to, created_by, status, resolved_at, updated_at").eq("status", "abierto").is("resolved_at", null).gte("updated_at", new Date(Date.now() - 1000 * 60 * 60 * 24 * 3).toISOString());
  if (error) {
    console.error("Error fetching tickets:", error);
    return new Response(JSON.stringify({
      error
    }), {
      status: 500,
      headers: corsHeaders
    });
  }
  // Identificar tickets próximos a vencerse y notificar
  let counter = 0;
  for (const ticket of tickets ?? []){
    // Ejemplo simple: si la última actualización es >48h, podría estar por vencerse
    // Puedes personalizar la lógica según SLA real/preferido
    const msSinceUpdate = Date.now() - new Date(ticket.updated_at).getTime();
    if (msSinceUpdate > 1000 * 60 * 60 * 24 * 2) {
      // Notificar al responsable si existe
      if (ticket.assigned_to) {
        await supabase.from("notifications").insert({
          recipient_id: ticket.assigned_to,
          title: "Ticket próximo a vencerse",
          message: `El ticket "${ticket.title}" está próximo a vencerse.`,
          type: "ticket_due_soon",
          related_entity_type: "ticket",
          related_entity_id: ticket.id
        });
        counter++;
      }
    }
  }
  return new Response(JSON.stringify({
    notified: counter
  }), {
    status: 200,
    headers: corsHeaders
  });
});
