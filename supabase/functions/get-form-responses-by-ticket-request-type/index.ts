// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || '';
const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

console.info('Get HR Tickets Form Responses Function started');

// Función que retorna las respuestas de formularios customizados de todos los tickets dado un conjunto de tipos de request_type
Deno.serve(async (req) => {
  try {

    //obtención de request_type desde query params
    const { searchParams } = new URL(req.url);
    
    const requestTypesParam = searchParams.get('request_types');
    
    if (!requestTypesParam) {
      return new Response(JSON.stringify({ error: 'Missing request_types query parameter' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const { data, error } = await supabaseClient
      .from("ticket_form_responses")
      .select("*")
      .in(
        "ticket_id",
        supabaseClient
          .from("tickets")
          .select("id")
          .in("request_type", requestTypesParam)
      );

    if (error) {
      console.error('Error fetching form responses:', error);
      return new Response(
        JSON.stringify({ error: 'Error fetching form responses', details: error.message }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    console.log(`Fetched ${data?.length || 0} form responses for request types: ${requestTypesParam}`);

    if (!data || data.length === 0) {
      return new Response(JSON.stringify({ form_responses: [] }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({ form_responses: data }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
    
  } catch (error) {
    console.error('Error in get-form-responses-by-ticket-request-type function:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: error.message }), 
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});