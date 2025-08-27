// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { onTicketAssignedUseCase, onTicketStatusChangeUseCase } from "../_shared/email/index.ts";

console.info('Ticket Updated Function started');

Deno.serve(async (req) => {
  try {
    const { record: updatedRecord, old_record: oldRecord } = await req.json();
    
    // Check if the ticket was reassigned
    if (updatedRecord?.assigned_to !== oldRecord?.assigned_to) {
      await onTicketAssignedUseCase.execute(updatedRecord.assigned_to, updatedRecord.id);

      const successMessage = 'Email [Ticket Assigned] notification sent';

      console.info(successMessage);

      return new Response(JSON.stringify({ message: successMessage }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if(updatedRecord?.status !== oldRecord?.status) {
      await onTicketStatusChangeUseCase.execute({
        createdById: updatedRecord.created_by,
        oldStatus: oldRecord.status,
        newStatus: updatedRecord.status,
        id: updatedRecord.id,
        title: updatedRecord.title,
      });

      const successMessage = 'Email [Ticket Status Changed] notification sent';

      console.info(successMessage);

      return new Response(JSON.stringify({ message: successMessage }), {
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