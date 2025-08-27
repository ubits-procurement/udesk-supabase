import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { onTicketCommentCreatedUseCase } from "../_shared/email";

Deno.serve(async (req) => {
  try {
    const { record } = await req.json();

    await onTicketCommentCreatedUseCase.execute(
      record.id,
      record.content,
      record.created_by
    );

    return new Response(
      JSON.stringify({ message: "Email notification sent" }),
      {
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error in ticket-comment-created:", error as Error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: (error as Error).message,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
