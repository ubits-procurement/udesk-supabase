import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
const supabaseUrl = Deno.env.get('SUPABASE_URL');
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};
const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});
// Rate limiting helper
let lastRequestTime = 0;
const MIN_REQUEST_INTERVAL = 1000; // 1 second between requests
async function searchCompanyInfo(query) {
  try {
    const { data, error } = await supabase.rpc('search_document_content', {
      search_query: query
    });
    if (error) {
      console.error('Error searching documents:', error);
      return [];
    }
    return data || [];
  } catch (error) {
    console.error('Error in document search:', error);
    return [];
  }
}
async function getRelevantArticles(query) {
  try {
    const { data, error } = await supabase.from('knowledge_articles').select(`
        *,
        knowledge_article_categories!inner(
          knowledge_categories(name)
        ),
        knowledge_article_tags(
          knowledge_tags(name)
        )
      `).textSearch('title', query, {
      type: 'websearch'
    }).limit(5);
    if (error) {
      console.error('Error fetching articles:', error);
      return [];
    }
    return data || [];
  } catch (error) {
    console.error('Error in article search:', error);
    return [];
  }
}
async function testOpenAIConnection() {
  console.log('🔍 Testing OpenAI connection...');
  if (!openAIApiKey) {
    console.error('❌ OpenAI API key not found in environment variables');
    return {
      connected: false,
      error: 'OPENAI_API_KEY no está configurado en Supabase Edge Function Secrets',
      details: 'Configurar OPENAI_API_KEY en la configuración de secretos de Supabase'
    };
  }
  try {
    const response = await fetch('https://api.openai.com/v1/models', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json'
      }
    });
    if (!response.ok) {
      const errorText = await response.text();
      console.error(`❌ OpenAI API test failed: ${response.status} - ${errorText}`);
      let specificError = 'Error de conexión con OpenAI API';
      if (response.status === 401) {
        specificError = 'API Key de OpenAI inválido - verifica que esté configurado correctamente';
      } else if (response.status === 429) {
        specificError = 'Límite de rate de OpenAI alcanzado - espera unos minutos';
      } else if (response.status === 402) {
        specificError = 'Créditos insuficientes en tu cuenta de OpenAI';
      }
      return {
        connected: false,
        error: specificError,
        status: response.status,
        details: errorText
      };
    }
    const data = await response.json();
    console.log('✅ OpenAI connection successful, models available:', data.data?.length || 0);
    return {
      connected: true,
      models: data.data?.length || 0
    };
  } catch (error) {
    console.error('❌ OpenAI connection test failed with exception:', error);
    return {
      connected: false,
      error: 'Error de red conectando con OpenAI: ' + error.message,
      details: error.message
    };
  }
}
async function callOpenAI(messages, options = {}) {
  // Rate limiting
  const now = Date.now();
  const timeSinceLastRequest = now - lastRequestTime;
  if (timeSinceLastRequest < MIN_REQUEST_INTERVAL) {
    await new Promise((resolve)=>setTimeout(resolve, MIN_REQUEST_INTERVAL - timeSinceLastRequest));
  }
  lastRequestTime = Date.now();
  console.log('🤖 Calling OpenAI API with messages:', messages.length);
  console.log('📊 Token usage will be logged after response');
  const requestBody = {
    model: 'gpt-4o-mini',
    messages,
    temperature: options.temperature || 0.3,
    max_tokens: options.max_tokens || 2000
  };
  console.log('📤 OpenAI request details:', {
    model: requestBody.model,
    messageCount: requestBody.messages.length,
    temperature: requestBody.temperature,
    maxTokens: requestBody.max_tokens
  });
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${openAIApiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(requestBody)
  });
  if (!response.ok) {
    const errorData = await response.text();
    console.error(`❌ OpenAI API error ${response.status}:`, errorData);
    if (response.status === 429) {
      throw new Error(`Rate limit exceeded. Please try again in a few minutes.`);
    } else if (response.status === 401) {
      throw new Error(`Invalid API key configuration.`);
    } else if (response.status === 403) {
      throw new Error(`OpenAI API access forbidden. Check your API key permissions.`);
    } else if (response.status === 402) {
      throw new Error(`Insufficient credits in OpenAI account. Please add credits.`);
    } else {
      throw new Error(`OpenAI API error: ${response.status} - ${errorData}`);
    }
  }
  const responseData = await response.json();
  // Log token usage
  if (responseData.usage) {
    console.log('📊 OpenAI token usage:', {
      prompt_tokens: responseData.usage.prompt_tokens,
      completion_tokens: responseData.usage.completion_tokens,
      total_tokens: responseData.usage.total_tokens
    });
  }
  return responseData;
}
serve(async (req)=>{
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: corsHeaders
    });
  }
  try {
    console.log('🔍 === FORM ANALYZER FUNCTION START ===');
    console.log('🔍 Request method:', req.method);
    console.log('🔍 Request URL:', req.url);
    console.log('🔍 Content-Type:', req.headers.get('content-type'));
    // Probar conexión OpenAI primero
    const connectionTest = await testOpenAIConnection();
    if (!connectionTest.connected) {
      console.error('❌ OpenAI connection failed:', connectionTest);
      return new Response(JSON.stringify({
        success: false,
        error: connectionTest.error,
        details: connectionTest.details || connectionTest.error
      }), {
        status: 503,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    console.log('✅ OpenAI connection verified');
    // Leer cuerpo de la petición con mejor manejo de errores
    let requestBody;
    try {
      const bodyText = await req.text();
      console.log('📦 Raw request body length:', bodyText?.length || 0);
      if (!bodyText || bodyText.trim() === '') {
        console.error('❌ Request body is empty');
        return new Response(JSON.stringify({
          success: false,
          error: 'Cuerpo de la petición vacío. Asegúrate de enviar los datos correctamente.',
          details: 'No se recibieron datos en la petición'
        }), {
          status: 400,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      try {
        requestBody = JSON.parse(bodyText);
        console.log('✅ JSON parsed successfully:', {
          hasFileContent: !!requestBody.fileContent,
          fileContentLength: requestBody.fileContent?.length || 0,
          fileName: requestBody.fileName,
          analysisType: requestBody.analysisType
        });
      } catch (jsonError) {
        console.error('❌ JSON parsing error:', jsonError);
        return new Response(JSON.stringify({
          success: false,
          error: 'Formato JSON inválido en el cuerpo de la petición',
          details: jsonError.message
        }), {
          status: 400,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
    } catch (bodyError) {
      console.error('❌ Error reading request body:', bodyError);
      return new Response(JSON.stringify({
        success: false,
        error: 'Error leyendo el cuerpo de la petición',
        details: bodyError.message
      }), {
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    const { fileContent, fileName, analysisType = 'extract_and_fill' } = requestBody;
    // Validación mejorada de campos requeridos
    if (!fileContent || typeof fileContent !== 'string' || fileContent.trim() === '') {
      console.error('❌ Missing or invalid fileContent');
      return new Response(JSON.stringify({
        success: false,
        error: 'fileContent es requerido y debe ser una cadena de texto válida',
        details: `Recibido: ${typeof fileContent}, longitud: ${fileContent?.length || 0}`
      }), {
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    if (!fileName || typeof fileName !== 'string') {
      console.error('❌ Missing or invalid fileName');
      return new Response(JSON.stringify({
        success: false,
        error: 'fileName es requerido y debe ser una cadena de texto válida',
        details: `Recibido: ${typeof fileName}`
      }), {
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    console.log(`🔍 Processing analysis for: ${fileName} (${fileContent.length} chars)`);
    // Limitar tamaño del contenido
    const MAX_CONTENT_SIZE = 100000;
    let extractedText = fileContent.substring(0, MAX_CONTENT_SIZE);
    console.log(`✅ Content prepared: ${extractedText.length} characters`);
    // Análisis del formulario con mejor prompt
    const formAnalysisPrompt = `
Analiza el siguiente formulario o documento y extrae información estructurada:

DOCUMENTO:
${extractedText}

Identifica y lista todos los campos, preguntas, y secciones que requieren información del usuario.
Para cada campo detectado, determina:
- Nombre descriptivo del campo
- Tipo de información solicitada 
- Categoría del campo (personal, corporativo, técnico, etc.)
- Si es requerido u opcional
- Descripción de lo que se solicita

Responde ÚNICAMENTE en formato JSON válido:
{
  "campos": [
    {
      "nombre": "string",
      "tipo": "string", 
      "categoria": "string",
      "requerido": boolean,
      "descripcion": "string"
    }
  ],
  "resumen": "string describiendo el propósito del formulario"
}`;
    console.log('🤖 Calling OpenAI for form analysis...');
    const analysisData = await callOpenAI([
      {
        role: 'system',
        content: 'Eres un experto analizador de formularios. Responde solo en JSON válido sin texto adicional.'
      },
      {
        role: 'user',
        content: formAnalysisPrompt
      }
    ]);
    let formAnalysis;
    try {
      const content = analysisData.choices[0].message.content.trim();
      const cleanContent = content.replace(/```json\n?|\n?```/g, '');
      formAnalysis = JSON.parse(cleanContent);
      console.log('✅ Form analysis completed successfully');
    } catch (e) {
      console.error('❌ Error parsing form analysis JSON:', e);
      throw new Error('Error procesando el análisis del formulario');
    }
    // Validar estructura del análisis
    if (!formAnalysis.campos || !Array.isArray(formAnalysis.campos)) {
      console.error('❌ Invalid analysis structure:', formAnalysis);
      throw new Error('Estructura de análisis inválida');
    }
    console.log(`✅ Analysis completed: found ${formAnalysis.campos.length} fields`);
    // Si solo se requiere extracción, retornar temprano
    if (analysisType === 'extract_only') {
      console.log('📤 Returning structure-only analysis');
      return new Response(JSON.stringify({
        success: true,
        analysis: formAnalysis,
        fileName: fileName,
        processedAt: new Date().toISOString()
      }), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    // Search for relevant company information
    console.log('🔍 Searching company knowledge base...');
    const searchQueries = [
      'información corporativa empresa',
      'datos contacto empresa',
      'información financiera',
      'certificaciones calidad'
    ];
    let relevantInfo = [];
    for (const query of searchQueries){
      try {
        const [docs, articles] = await Promise.all([
          searchCompanyInfo(query),
          getRelevantArticles(query)
        ]);
        relevantInfo.push(...docs, ...articles);
      } catch (error) {
        console.error(`❌ Error searching for ${query}:`, error);
      }
    }
    // Prepare company context
    const companyContext = relevantInfo.slice(0, 10).map((item)=>{
      if (item.extracted_text) {
        return `Documento: ${item.file_name}\nContenido: ${item.extracted_text.substring(0, 800)}`;
      } else if (item.content) {
        return `Artículo: ${item.title}\nContenido: ${item.content.substring(0, 800)}`;
      }
      return '';
    }).filter(Boolean).join('\n\n');
    console.log(`✅ Found ${relevantInfo.length} relevant knowledge base items`);
    // Generate field completions
    const completionPrompt = `
Completa el siguiente formulario usando la información corporativa disponible:

CAMPOS DEL FORMULARIO:
${JSON.stringify(formAnalysis.campos, null, 2)}

INFORMACIÓN CORPORATIVA:
${companyContext || 'No hay información específica disponible en la base de conocimiento.'}

INSTRUCCIONES:
- Completa cada campo con información precisa si está disponible
- Si no hay información específica, indica "INFORMACIÓN NO DISPONIBLE"
- Asigna niveles de confianza: alta (datos exactos), media (aproximaciones), baja (estimaciones)
- Marca requiere_revision=true para campos que necesitan verificación manual

Responde ÚNICAMENTE en formato JSON válido:
{
  "campos_completados": [
    {
      "nombre": "string",
      "valor_sugerido": "string",
      "confianza": "alta|media|baja",
      "fuente": "string",
      "requiere_revision": boolean
    }
  ],
  "estadisticas": {
    "campos_totales": number,
    "campos_completados": number, 
    "porcentaje_completado": number
  },
  "observaciones": "string con comentarios adicionales"
}`;
    console.log('🤖 Generating field completions...');
    const completionData = await callOpenAI([
      {
        role: 'system',
        content: 'Eres un asistente experto en completar formularios corporativos. Responde solo en JSON válido.'
      },
      {
        role: 'user',
        content: completionPrompt
      }
    ], {
      temperature: 0.2,
      max_tokens: 3000
    });
    let formCompletion;
    try {
      const content = completionData.choices[0].message.content.trim();
      const cleanContent = content.replace(/```json\n?|\n?```/g, '');
      formCompletion = JSON.parse(cleanContent);
      console.log('✅ Form completion JSON parsed successfully');
    } catch (e) {
      console.error('❌ Error parsing completion JSON:', e);
      throw new Error('Error generando completaciones de formulario');
    }
    // Validate completion structure
    if (!formCompletion.campos_completados || !formCompletion.estadisticas) {
      console.error('❌ Invalid completion structure:', formCompletion);
      throw new Error('Estructura de completación inválida');
    }
    console.log(`✅ Form completion generated: ${formCompletion.estadisticas.campos_completados}/${formCompletion.estadisticas.campos_totales} fields completed`);
    const finalResult = {
      success: true,
      analysis: formAnalysis,
      completion: formCompletion,
      fileName: fileName,
      processedAt: new Date().toISOString()
    };
    console.log('📤 Returning successful analysis result');
    console.log('🔍 === FORM ANALYZER FUNCTION END (SUCCESS) ===');
    return new Response(JSON.stringify(finalResult), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  } catch (error) {
    console.error('💥 Critical error in form-analyzer function:', error);
    console.error('💥 Error stack:', error.stack);
    let errorMessage = 'Error interno del servidor';
    let statusCode = 500;
    if (error.message.includes('OpenAI') || error.message.includes('API key')) {
      errorMessage = 'Error de configuración de OpenAI API. Verifica que la clave esté configurada correctamente.';
      statusCode = 503;
    } else if (error.message.includes('Rate limit') || error.message.includes('429')) {
      errorMessage = 'Límite de API alcanzado. Intenta de nuevo en unos minutos.';
      statusCode = 429;
    } else if (error.message.includes('credits') || error.message.includes('402')) {
      errorMessage = 'Créditos insuficientes en OpenAI. Verifica tu cuenta.';
      statusCode = 402;
    }
    const errorResult = {
      success: false,
      error: errorMessage,
      details: error.message,
      timestamp: new Date().toISOString()
    };
    console.log('📤 Returning error response:', errorResult);
    console.log('🔍 === FORM ANALYZER FUNCTION END (ERROR) ===');
    return new Response(JSON.stringify(errorResult), {
      status: statusCode,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  }
});
