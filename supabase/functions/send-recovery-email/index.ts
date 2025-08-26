import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { Resend } from "npm:resend@2.0.0";
const resend = new Resend(Deno.env.get("RESEND_API_KEY"));
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};
const handler = async (req)=>{
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: corsHeaders
    });
  }
  try {
    const { email, resetLink } = await req.json();
    const emailResponse = await resend.emails.send({
      from: "UDesk <noreply@resend.dev>",
      to: [
        email
      ],
      subject: "Recuperación de contraseña - UDesk",
      html: `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Recuperación de contraseña</title>
        </head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
          <div style="background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); padding: 30px; border-radius: 10px; margin-bottom: 30px;">
            <h1 style="color: white; margin: 0; text-align: center; font-size: 32px;">UDesk</h1>
            <p style="color: #bfdbfe; text-align: center; margin: 10px 0 0 0;">Plataforma de Mesa de Ayuda</p>
          </div>
          
          <div style="background: #f8fafc; padding: 30px; border-radius: 10px; border: 1px solid #e2e8f0;">
            <h2 style="color: #1e40af; margin-top: 0;">Recuperación de Contraseña</h2>
            
            <p>Hola,</p>
            
            <p>Recibimos una solicitud para restablecer la contraseña de tu cuenta en UDesk. Si no solicitaste este cambio, puedes ignorar este correo.</p>
            
            <div style="text-align: center; margin: 30px 0;">
              <a href="${resetLink}" 
                 style="background: #1e40af; color: white; padding: 15px 30px; text-decoration: none; border-radius: 8px; font-weight: bold; display: inline-block;">
                Restablecer Contraseña
              </a>
            </div>
            
            <p style="font-size: 14px; color: #64748b;">
              Si el botón no funciona, copia y pega el siguiente enlace en tu navegador:<br>
              <a href="${resetLink}" style="color: #1e40af; word-break: break-all;">${resetLink}</a>
            </p>
            
            <div style="background: #fef3c7; border: 1px solid #f59e0b; border-radius: 8px; padding: 15px; margin: 20px 0;">
              <p style="margin: 0; font-size: 14px; color: #92400e;">
                <strong>Importante:</strong> Este enlace expirará en 24 horas por razones de seguridad.
              </p>
            </div>
            
            <p style="font-size: 14px; color: #64748b;">
              Si tienes problemas para restablecer tu contraseña, contacta a tu administrador del sistema.
            </p>
          </div>
          
          <div style="text-align: center; margin-top: 30px; padding-top: 20px; border-top: 1px solid #e2e8f0;">
            <p style="font-size: 12px; color: #94a3b8; margin: 0;">
              © 2024 UDesk - Plataforma de Mesa de Ayuda<br>
              Este es un correo automático, por favor no respondas.
            </p>
          </div>
        </body>
        </html>
      `
    });
    console.log("Recovery email sent successfully:", emailResponse);
    return new Response(JSON.stringify(emailResponse), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        ...corsHeaders
      }
    });
  } catch (error) {
    console.error("Error in send-recovery-email function:", error);
    return new Response(JSON.stringify({
      error: error.message
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json",
        ...corsHeaders
      }
    });
  }
};
serve(handler);
