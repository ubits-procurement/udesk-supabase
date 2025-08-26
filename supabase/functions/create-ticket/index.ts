import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
Deno.serve(async (req)=>{
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      status: 200
    });
  }
  try {
    const supabaseClient = createClient(Deno.env.get('SUPABASE_URL'), Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'));
    const ticketData = await req.json();
    const { data, error } = await supabaseClient.from('tickets').insert([
      {
        ...ticketData,
        created_at: new Date().toISOString(),
        created_by: Deno.env.get('TICKET_CREATED_BY_DEFAULT_ID')
      }
    ]);
    if (error) throw error;
    return new Response(JSON.stringify(data), {
      headers: {
        'Content-Type': 'application/json'
      },
      status: 201
    });
  } catch (error) {
    return new Response(JSON.stringify({
      error: error.message
    }), {
      headers: {
        'Content-Type': 'application/json'
      },
      status: 400
    });
  }
});
