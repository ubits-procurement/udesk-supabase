// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { onTicketAssignedUseCase } from "../_shared/email/application/use-cases/on-ticket-assigned.use-case.ts";

console.info('Ticket Updated Function started');

Deno.serve(async (req) => {
  try {
    const { record: updatedRecord, old_record: oldRecord } = await req.json();
    
    // Check if the ticket was reassigned
    if (updatedRecord?.assigned_to !== oldRecord?.assigned_to) {
      onTicketAssignedUseCase.execute(updatedRecord.assigned_to, updatedRecord.id);

      return new Response(JSON.stringify({ message: 'Email notification sent' }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    return new Response(JSON.stringify({ message: 'No action needed' }), {
      headers: { 'Content-Type': 'application/json' }
    });
    
  } catch (error) {
    console.error('Error in ticket-updated-function:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: error.message }), 
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});