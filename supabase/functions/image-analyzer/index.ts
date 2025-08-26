import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
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
    const { imageUrl, context, analysisType = 'comprehensive' } = await req.json();
    if (!imageUrl) {
      throw new Error('Image URL is required');
    }
    console.log(`Analyzing image: ${imageUrl} with type: ${analysisType}`);
    // Define prompts based on analysis type
    let systemPrompt = '';
    let userPrompt = '';
    if (analysisType === 'ocr_only') {
      systemPrompt = 'Eres un experto en OCR. Extrae TODO el texto visible en la imagen de manera precisa, manteniendo el formato y estructura original.';
      userPrompt = 'Extrae todo el texto visible en esta imagen. Mantén el formato, saltos de línea y estructura original. Si no hay texto, responde "No se encontró texto en la imagen".';
    } else {
      systemPrompt = `Eres un asistente experto en análisis de imágenes técnicas y documentación. Tu tarea es analizar imágenes de documentos, diagramas, capturas de pantalla, gráficos y otros elementos visuales para extraer información útil.

INSTRUCCIONES DE ANÁLISIS:
1. Describe claramente qué muestra la imagen
2. Extrae TODO el texto visible (títulos, etiquetas, descripciones, etc.)
3. Identifica elementos técnicos: botones, menús, diagramas, flujos, tablas
4. Explica procesos o pasos mostrados visualmente
5. Menciona colores, iconos o símbolos relevantes
6. Si es una captura de pantalla, describe la interfaz y funcionalidades
7. Si es un diagrama, explica las conexiones y flujos

FORMATO DE RESPUESTA:
- Descripción general
- Texto extraído (si existe)
- Elementos identificados
- Información técnica relevante
- Contexto y propósito aparente`;
      userPrompt = `Analiza esta imagen extraída de documentación técnica. ${context ? `Contexto adicional: ${context}` : ''}

Por favor proporciona:
1. Una descripción detallada de lo que muestra la imagen
2. Todo el texto visible en la imagen
3. Elementos técnicos identificados (botones, menús, opciones, etc.)
4. Procesos o pasos mostrados
5. Información relevante para soporte técnico o documentación`;
    }
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: 'gpt-4o',
        messages: [
          {
            role: 'system',
            content: systemPrompt
          },
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: userPrompt
              },
              {
                type: 'image_url',
                image_url: {
                  url: imageUrl,
                  detail: 'high'
                }
              }
            ]
          }
        ],
        max_tokens: 1500,
        temperature: 0.1
      })
    });
    if (!response.ok) {
      throw new Error(`OpenAI API error: ${response.status}`);
    }
    const data = await response.json();
    const analysisResult = data.choices[0].message.content;
    console.log('Image analysis completed successfully');
    if (analysisType === 'ocr_only') {
      return new Response(JSON.stringify({
        success: true,
        extractedText: analysisResult
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    // Parse comprehensive analysis
    const lines = analysisResult.split('\n').filter((line)=>line.trim());
    const description = lines.slice(0, 3).join(' ');
    const extractedText = analysisResult.match(/texto[^:]*:([^]*?)(?=\n\n|\n[A-Z]|$)/i)?.[1]?.trim() || '';
    const elements = lines.filter((line)=>line.includes('botón') || line.includes('menú') || line.includes('opción') || line.includes('campo') || line.includes('enlace') || line.includes('icono'));
    const analysis = {
      description: description || analysisResult.substring(0, 200) + '...',
      extractedText: extractedText,
      elements: elements.slice(0, 10),
      confidence: 0.85,
      fullAnalysis: analysisResult
    };
    return new Response(JSON.stringify({
      success: true,
      analysis
    }), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  } catch (error) {
    console.error('Error in image-analyzer function:', error);
    return new Response(JSON.stringify({
      success: false,
      error: error.message
    }), {
      status: 500,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  }
});
