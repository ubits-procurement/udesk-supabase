import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
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
    const supabaseClient = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
    console.log('Iniciando limpieza de datos de seguridad...');
    // Ejecutar función de limpieza
    const { data, error } = await supabaseClient.rpc('cleanup_security_data');
    if (error) {
      console.error('Error en limpieza:', error);
      throw error;
    }
    console.log('Limpieza completada exitosamente');
    // Generar estadísticas de limpieza
    const cleanupStats = {
      timestamp: new Date().toISOString(),
      status: 'success',
      message: 'Limpieza de datos de seguridad completada'
    };
    // Registrar evento de limpieza en auditoría
    await supabaseClient.rpc('log_audit_event', {
      user_id_param: null,
      action_param: 'security_cleanup',
      resource_type_param: 'system',
      resource_id_param: null,
      ip_address_param: null,
      user_agent_param: 'system-cron',
      details_param: JSON.stringify(cleanupStats)
    });
    return new Response(JSON.stringify(cleanupStats), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  } catch (error) {
    console.error('Error en security cleanup:', error);
    return new Response(JSON.stringify({
      error: error.message,
      timestamp: new Date().toISOString()
    }), {
      status: 500,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  }
});
