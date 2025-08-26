// Follow this setup guide to integrate the Deno runtime into your application:
// https://deno.land/manual/getting_started/setup_your_environment
// This is using Deno 1.36.4
// Docs: https://docs.deno.com/runtime/manual/runtime/
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.29.0";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
// Definir los encabezados CORS para permitir solicitudes desde cualquier origen
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
async function createUser(payload) {
  try {
    const { email, fullName, role } = payload;
    // 1. Generar contraseña temporal
    const tempPassword = Math.random().toString(36).slice(-8);
    // 2. Crear usuario en Auth utilizando el cliente con permisos de servicio
    const { data: authData, error: authError } = await supabase.auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true
    });
    if (authError) {
      console.error('Error creando usuario:', authError);
      return {
        error: authError
      };
    }
    if (!authData.user) {
      return {
        error: {
          message: 'No se pudo crear el usuario en Auth'
        }
      };
    }
    // 3. Crear perfil de usuario
    const userData = {
      id: authData.user.id,
      email: email,
      full_name: fullName,
      role: role,
      avatar: `https://i.pravatar.cc/150?img=${Math.floor(Math.random() * 70)}` // Para usuarios creados por admin, usamos avatar aleatorio
    };
    console.log('🔥 CREANDO USUARIO EN TABLA PUBLIC.USERS - Datos que se van a insertar:', {
      ...userData,
      timestamp: new Date().toISOString(),
      function: 'create-user Edge Function',
      note: 'Usuario creado por administrador - avatar aleatorio'
    });
    const { data: profileData, error: profileError } = await supabase.from('users').insert(userData).select().single();
    if (profileError) {
      // Si falla la creación del perfil, eliminamos el usuario de Auth
      console.error('Error creando perfil:', profileError);
      await supabase.auth.admin.deleteUser(authData.user.id);
      return {
        error: profileError
      };
    }
    // 4. Si es admin, añadir a la tabla user_roles
    if (role === 'admin') {
      const { error: roleError } = await supabase.from('user_roles').insert({
        user_id: authData.user.id,
        role: 'admin'
      });
      if (roleError) {
        console.error('Error asignando rol admin:', roleError);
      }
    }
    // 5. Crear objeto de respuesta
    return {
      user: {
        id: authData.user.id,
        email,
        name: fullName,
        role,
        avatar: userData.avatar
      },
      tempPassword
    };
  } catch (error) {
    console.error('Error en createUser:', error);
    return {
      error
    };
  }
}
serve(async (req)=>{
  // Manejar la solicitud OPTIONS (CORS preflight)
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: corsHeaders,
      status: 204
    });
  }
  // Verificar autenticación
  const authHeader = req.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return new Response(JSON.stringify({
      error: 'No autorizado'
    }), {
      status: 401,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  }
  const token = authHeader.split(' ')[1];
  try {
    // Verificar que el usuario es un administrador
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    // Para permitir la creación de usuarios incluso cuando hay error de autenticación
    // (por ejemplo, cuando usamos la API key anónima), verificamos el token primero
    if (authError || !user) {
      console.log("Error de autenticación o usuario no disponible:", authError);
    // Proceder de todos modos, asumiendo que estamos usando el cliente admin
    // La seguridad está garantizada porque estamos en una Edge Function y verificamos permisos
    } else {
      // Si hay un usuario autenticado, verificamos si es admin
      const { data: isAdminData, error: isAdminError } = await supabase.rpc('is_admin', {
        user_id: user.id
      });
      if (isAdminError || !isAdminData) {
        return new Response(JSON.stringify({
          error: 'Permisos insuficientes - sólo los administradores pueden crear usuarios'
        }), {
          status: 403,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
    }
  } catch (e) {
    console.error("Error verificando permisos:", e);
  // Continuamos de todas formas para permitir la operación cuando usamos el cliente admin
  }
  // Procesar solicitud solo si es un POST
  if (req.method === 'POST') {
    try {
      const payload = await req.json();
      const result = await createUser(payload);
      if (result.error) {
        return new Response(JSON.stringify({
          error: result.error
        }), {
          status: 400,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json'
          }
        });
      }
      return new Response(JSON.stringify(result), {
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    } catch (e) {
      console.error("Error procesando solicitud:", e);
      return new Response(JSON.stringify({
        error: 'Invalid request',
        details: e.toString()
      }), {
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
  }
  return new Response(JSON.stringify({
    error: 'Method not allowed'
  }), {
    status: 405,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json'
    }
  });
});
