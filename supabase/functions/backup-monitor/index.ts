import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};
serve(async (req)=>{
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: corsHeaders
    });
  }
  try {
    const supabaseClient = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
    console.log('Iniciando monitoreo de backup...');
    // Verificar estado de las tablas críticas
    const criticalTables = [
      'users',
      'tickets',
      'ticket_comments',
      'knowledge_articles',
      'audit_logs'
    ];
    const backupStatus = {
      timestamp: new Date().toISOString(),
      status: 'healthy',
      tables: {},
      alerts: []
    };
    // Verificar cada tabla crítica
    for (const table of criticalTables){
      try {
        const { count, error } = await supabaseClient.from(table).select('*', {
          count: 'exact',
          head: true
        });
        if (error) {
          backupStatus.alerts.push(`Error accediendo a tabla ${table}: ${error.message}`);
          backupStatus.status = 'warning';
        } else {
          backupStatus.tables[table] = {
            count: count || 0,
            status: 'ok',
            last_checked: new Date().toISOString()
          };
        }
      } catch (err) {
        backupStatus.alerts.push(`Excepción en tabla ${table}: ${err.message}`);
        backupStatus.status = 'error';
      }
    }
    // Verificar integridad de datos críticos
    const { data: recentTickets, error: ticketsError } = await supabaseClient.from('tickets').select('id, created_at').gte('created_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()).limit(1);
    if (ticketsError) {
      backupStatus.alerts.push(`Error verificando tickets recientes: ${ticketsError.message}`);
    } else {
      backupStatus.tables.tickets.recent_activity = recentTickets?.length || 0;
    }
    // Verificar logs de auditoría
    const { data: recentLogs, error: logsError } = await supabaseClient.from('audit_logs').select('id').gte('created_at', new Date(Date.now() - 60 * 60 * 1000).toISOString()).limit(1);
    if (logsError) {
      backupStatus.alerts.push(`Error verificando logs de auditoría: ${logsError.message}`);
    }
    // Generar plan de recuperación si hay problemas
    if (backupStatus.status !== 'healthy') {
      backupStatus.recovery_plan = {
        immediate_actions: [
          "Verificar conectividad a la base de datos",
          "Revisar logs de Supabase para errores",
          "Contactar soporte de Supabase si es necesario"
        ],
        backup_sources: [
          "Backups automáticos de Supabase (Point-in-time recovery)",
          "Exports manuales si están disponibles",
          "Replicación de datos si está configurada"
        ]
      };
    }
    // Registrar monitoreo en auditoría
    await supabaseClient.rpc('log_audit_event', {
      user_id_param: null,
      action_param: 'backup_monitor',
      resource_type_param: 'system',
      resource_id_param: null,
      ip_address_param: null,
      user_agent_param: 'system-monitor',
      details_param: JSON.stringify(backupStatus)
    });
    console.log('Monitoreo de backup completado:', backupStatus.status);
    return new Response(JSON.stringify(backupStatus), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  } catch (error) {
    console.error('Error en backup monitor:', error);
    return new Response(JSON.stringify({
      error: error.message,
      timestamp: new Date().toISOString(),
      status: 'critical'
    }), {
      status: 500,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  }
});
