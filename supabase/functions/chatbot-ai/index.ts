import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};
serve(async (req)=>{
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: corsHeaders
    });
  }
  try {
    const { query, sessionId, relevantArticles, relevantDocuments, conversationHistory, confidenceLevel = 0, shouldPrioritizeInternal = true, totalInternalResults = 0, ticketCreationMode = false, requestTypes = [], currentTicketState = null } = await req.json();
    console.log(`Processing query: "${query}" with sessionId: "${sessionId}"`);
    console.log(`Internal confidence: ${confidenceLevel}%, prioritize internal: ${shouldPrioritizeInternal}`);
    console.log(`Internal results: ${totalInternalResults}, Articles: ${relevantArticles?.length || 0}, Documents: ${relevantDocuments?.length || 0}`);
    // Make request to n8n webhook endpoint
    console.log('Making request to n8n webhook...');
    const n8nResponse = await fetch('https://procurement-ubits.app.n8n.cloud/webhook/de2ac704-e7d2-46e3-b718-c575b1d3e573/chat', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        action: "sendMessage",
        sessionId: sessionId,
        chatInput: query
      })
    });
    if (!n8nResponse.ok) {
      throw new Error(`n8n webhook error: ${n8nResponse.status} - ${n8nResponse.statusText}`);
    }
    const n8nData = await n8nResponse.json();
    console.log('n8n response received:', n8nData);
    // Extract the response text from n8n response
    let generatedResponse = n8nData.response || n8nData.message || n8nData.text || "Respuesta recibida del asistente.";
    // If n8nData is a string, use it directly
    if (typeof n8nData === 'string') {
      generatedResponse = n8nData;
    }
    console.log('Generated AI response successfully via n8n webhook');
    // Build sources array based on internal knowledge
    const sources = [];
    if (relevantArticles && relevantArticles.length > 0) {
      sources.push(...relevantArticles.map((a)=>`📋 ${a.title} (Fuente Interna)`));
    }
    if (relevantDocuments && relevantDocuments.length > 0) {
      sources.push(...relevantDocuments.map((d)=>`📄 ${d.file_name} (Documento Procesado)`));
    }
    if (sources.length === 0) {
      sources.push("🤖 Asistente AI");
    }
    return new Response(JSON.stringify({
      response: generatedResponse,
      sources: sources,
      confidenceLevel: confidenceLevel,
      internalResultsCount: totalInternalResults,
      documentsProcessedCount: relevantDocuments?.length || 0,
      prioritizedInternal: shouldPrioritizeInternal,
      ticketCreationAction: null // n8n will handle ticket creation differently
    }), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  } catch (error) {
    console.error('Error in chatbot-ai function:', error);
    const fallbackResponse = "Disculpa, hubo un problema conectando con el asistente. Por favor, intenta nuevamente o crea un ticket para recibir asistencia directa de nuestro equipo de soporte en UDesk.";
    return new Response(JSON.stringify({
      response: fallbackResponse,
      sources: [
        "🤖 Sistema de respaldo"
      ],
      error: true,
      confidenceLevel: 0
    }), {
      status: 200,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  }
});
