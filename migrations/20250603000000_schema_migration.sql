

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."app_role" AS ENUM (
    'admin',
    'agent',
    'client'
);


ALTER TYPE "public"."app_role" OWNER TO "postgres";


CREATE TYPE "public"."ticket_priority" AS ENUM (
    'baja',
    'media',
    'alta',
    'urgente'
);


ALTER TYPE "public"."ticket_priority" OWNER TO "postgres";


CREATE TYPE "public"."ticket_status" AS ENUM (
    'abierto',
    'en_progreso',
    'pendiente',
    'resuelto',
    'cerrado'
);


ALTER TYPE "public"."ticket_status" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_access_ticket"("ticket_id" integer, "user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tickets t
    LEFT JOIN public.users u ON u.id = user_id
    WHERE t.id = ticket_id 
    AND (
      t.created_by = user_id OR 
      t.assigned_to = user_id OR 
      COALESCE(u.role::text, 'client') IN ('admin', 'agent')
    )
  );
$$;


ALTER FUNCTION "public"."can_access_ticket"("ticket_id" integer, "user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_add_comment_to_ticket"("ticket_id" integer, "user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM tickets t
    WHERE t.id = ticket_id
    AND (
      t.created_by = user_id OR
      t.assigned_to = user_id OR
      (SELECT role FROM users WHERE id = user_id) IN ('admin', 'agent')
    )
  );
$$;


ALTER FUNCTION "public"."can_add_comment_to_ticket"("ticket_id" integer, "user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_view_ticket_comments"("user_id" "uuid", "ticket_id" integer) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM tickets t
    WHERE t.id = ticket_id 
    AND (
      t.created_by = user_id OR 
      t.assigned_to = user_id OR 
      get_user_role(user_id) IN ('admin', 'agent')
    )
  );
$$;


ALTER FUNCTION "public"."can_view_ticket_comments"("user_id" "uuid", "ticket_id" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_rate_limit"("identifier_param" "text", "endpoint_param" "text", "max_requests" integer, "window_minutes" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  current_count INTEGER;
  window_start TIMESTAMP WITH TIME ZONE;
BEGIN
  window_start := DATE_TRUNC('minute', NOW()) - INTERVAL '1 minute' * (EXTRACT(MINUTE FROM NOW())::INTEGER % window_minutes);
  
  -- Contar requests en la ventana actual
  SELECT COALESCE(SUM(requests_count), 0) INTO current_count
  FROM public.rate_limits
  WHERE identifier = identifier_param
    AND endpoint = endpoint_param
    AND window_start >= window_start;
  
  -- Si excede el límite, retornar false
  IF current_count >= max_requests THEN
    RETURN FALSE;
  END IF;
  
  -- Incrementar contador
  INSERT INTO public.rate_limits (identifier, endpoint, requests_count, window_start)
  VALUES (identifier_param, endpoint_param, 1, window_start)
  ON CONFLICT (identifier, endpoint, window_start)
  DO UPDATE SET requests_count = rate_limits.requests_count + 1;
  
  RETURN TRUE;
END;
$$;


ALTER FUNCTION "public"."check_rate_limit"("identifier_param" "text", "endpoint_param" "text", "max_requests" integer, "window_minutes" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_security_data"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Limpiar rate limits antiguos (más de 24 horas)
  DELETE FROM public.rate_limits 
  WHERE created_at < NOW() - INTERVAL '24 hours';
  
  -- Limpiar intentos de login antiguos (más de 7 días)
  DELETE FROM public.failed_login_attempts 
  WHERE attempt_time < NOW() - INTERVAL '7 days';
  
  -- Limpiar sesiones expiradas
  DELETE FROM public.user_sessions 
  WHERE expires_at < NOW();
  
  -- Limpiar logs de auditoría antiguos (más de 90 días)
  DELETE FROM public.audit_logs 
  WHERE created_at < NOW() - INTERVAL '90 days';
END;
$$;


ALTER FUNCTION "public"."cleanup_security_data"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_default_notification_settings"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  INSERT INTO public.notification_settings (user_id)
  VALUES (NEW.id);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."create_default_notification_settings"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_rating_token"("ticket_id_param" integer, "token_param" "text", "expires_at_param" timestamp with time zone) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  INSERT INTO public.rating_tokens (ticket_id, token, expires_at)
  VALUES (ticket_id_param, token_param, expires_at_param);
  
  RETURN TRUE;
END;
$$;


ALTER FUNCTION "public"."create_rating_token"("ticket_id_param" integer, "token_param" "text", "expires_at_param" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_admin_users"() RETURNS SETOF "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  SELECT user_id
  FROM public.user_roles
  WHERE role = 'admin';
$$;


ALTER FUNCTION "public"."get_admin_users"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_current_user_organization"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT organization_id FROM public.users WHERE id = auth.uid();
$$;


ALTER FUNCTION "public"."get_current_user_organization"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_current_user_role"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT role::TEXT FROM public.users WHERE id = auth.uid();
$$;


ALTER FUNCTION "public"."get_current_user_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_current_user_role_no_recursion"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  user_role TEXT;
BEGIN
  -- Usar una consulta directa sin políticas RLS
  SELECT role::TEXT INTO user_role
  FROM public.users 
  WHERE id = auth.uid()
  LIMIT 1;
  
  RETURN COALESCE(user_role, 'client');
EXCEPTION
  WHEN OTHERS THEN
    RETURN 'client';
END;
$$;


ALTER FUNCTION "public"."get_current_user_role_no_recursion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_current_user_role_safe"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  user_role TEXT;
BEGIN
  SELECT role::TEXT INTO user_role
  FROM public.users 
  WHERE id = auth.uid()
  LIMIT 1;
  
  RETURN COALESCE(user_role, 'client');
EXCEPTION
  WHEN OTHERS THEN
    RETURN 'client';
END;
$$;


ALTER FUNCTION "public"."get_current_user_role_safe"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_system_setting"("setting_key" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  setting_value JSONB;
BEGIN
  SELECT value INTO setting_value
  FROM public.system_settings
  WHERE key = setting_key;
  
  IF setting_value IS NULL THEN
    RETURN NULL;
  END IF;
  
  RETURN setting_value::TEXT;
END;
$$;


ALTER FUNCTION "public"."get_system_setting"("setting_key" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "full_name" "text" NOT NULL,
    "email" "text" NOT NULL,
    "phone_number" "text",
    "department_id" integer,
    "role" "public"."app_role" DEFAULT 'client'::"public"."app_role" NOT NULL,
    "avatar" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "organization_id" "uuid"
);


ALTER TABLE "public"."users" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_by_id"("user_id" "uuid") RETURNS SETOF "public"."users"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT * FROM users WHERE id = user_id;
$$;


ALTER FUNCTION "public"."get_user_by_id"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_role"("user_id" "uuid") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT role::TEXT FROM public.users WHERE id = user_id;
$$;


ALTER FUNCTION "public"."get_user_role"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_role_safe"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  user_role TEXT;
BEGIN
  SELECT role::TEXT INTO user_role
  FROM public.users 
  WHERE id = auth.uid()
  LIMIT 1;
  
  RETURN COALESCE(user_role, 'client');
EXCEPTION
  WHEN OTHERS THEN
    RETURN 'client';
END;
$$;


ALTER FUNCTION "public"."get_user_role_safe"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_role_safe"("user_id" "uuid") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT COALESCE(role::text, 'client') 
  FROM public.users 
  WHERE id = user_id
  LIMIT 1;
$$;


ALTER FUNCTION "public"."get_user_role_safe"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Log para debugging con toda la información disponible
  RAISE LOG 'Trigger ejecutado para usuario: % con email: %', NEW.id, NEW.email;
  RAISE LOG 'Metadatos de usuario: %', NEW.raw_user_meta_data;
  
  -- Console log para JavaScript con toda la información que se va a insertar
  RAISE LOG '🔥 CREANDO USUARIO EN TRIGGER - Datos completos: usuario_id=%, email=%, metadatos=%', 
    NEW.id, 
    NEW.email, 
    NEW.raw_user_meta_data;
  
  -- Verificar si el usuario ya existe para evitar duplicados
  IF EXISTS (SELECT 1 FROM public.users WHERE id = NEW.id) THEN
    RAISE LOG 'Usuario ya existe en tabla users: %', NEW.id;
    RETURN NEW;
  END IF;
  
  -- Extraer datos del perfil de Google si están disponibles
  DECLARE
    avatar_url TEXT;
    full_name TEXT;
  BEGIN
    -- Intentar obtener la URL del avatar de Google de los metadatos
    avatar_url := NEW.raw_user_meta_data->>'avatar_url';
    
    -- Si no hay avatar_url, intentar con picture (otro campo común de Google)
    IF avatar_url IS NULL THEN
      avatar_url := NEW.raw_user_meta_data->>'picture';
    END IF;
    
    -- Si aún no hay imagen, usar una por defecto
    IF avatar_url IS NULL THEN
      avatar_url := 'https://i.pravatar.cc/150?img=' || (floor(random() * 70) + 1)::text;
    END IF;
    
    -- Obtener el nombre completo
    full_name := COALESCE(
      NEW.raw_user_meta_data->>'full_name', 
      NEW.raw_user_meta_data->>'name', 
      NEW.email, 
      'Usuario'
    );
    
    -- Log de los datos que se van a insertar
    RAISE LOG '🔥 INSERTANDO USUARIO - avatar_url: %, full_name: %', avatar_url, full_name;
    
    -- Insertar en la tabla users
    INSERT INTO public.users (
      id,
      email,
      full_name,
      role,
      avatar,
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      NEW.email,
      full_name,
      'client'::app_role,
      avatar_url,
      NOW(),
      NOW()
    );
    
    RAISE LOG 'Usuario insertado exitosamente en tabla users: % con avatar: %', NEW.email, avatar_url;
    
  END;
  
  RETURN NEW;
EXCEPTION
  WHEN unique_violation THEN
    RAISE LOG 'Usuario ya existe (violación de unicidad): %', NEW.email;
    RETURN NEW;
  WHEN OTHERS THEN
    RAISE LOG 'Error en handle_new_user para %: %', NEW.email, SQLERRM;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_role"("user_id" "uuid", "requested_role" "public"."app_role") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = $1
      AND role = $2
  );
$_$;


ALTER FUNCTION "public"."has_role"("user_id" "uuid", "requested_role" "public"."app_role") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"("user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = user_id
      AND u.role = 'admin'
  );
$$;


ALTER FUNCTION "public"."is_admin"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_audit_event"("user_id_param" "uuid", "action_param" "text", "resource_type_param" "text", "resource_id_param" "text" DEFAULT NULL::"text", "ip_address_param" "inet" DEFAULT NULL::"inet", "user_agent_param" "text" DEFAULT NULL::"text", "details_param" "jsonb" DEFAULT NULL::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  log_id UUID;
BEGIN
  INSERT INTO public.audit_logs (
    user_id, action, resource_type, resource_id, 
    ip_address, user_agent, details
  )
  VALUES (
    user_id_param, action_param, resource_type_param, resource_id_param,
    ip_address_param, user_agent_param, details_param
  )
  RETURNING id INTO log_id;
  
  RETURN log_id;
END;
$$;


ALTER FUNCTION "public"."log_audit_event"("user_id_param" "uuid", "action_param" "text", "resource_type_param" "text", "resource_id_param" "text", "ip_address_param" "inet", "user_agent_param" "text", "details_param" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_rating_token_used"("token_param" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE public.rating_tokens
  SET used_at = NOW()
  WHERE token = token_param;
  
  RETURN FOUND;
END;
$$;


ALTER FUNCTION "public"."mark_rating_token_used"("token_param" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_document_content"("search_query" "text") RETURNS TABLE("attachment_id" "uuid", "article_id" "uuid", "file_name" "text", "extracted_text" "text", "relevance_score" real)
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  SELECT 
    dc.attachment_id,
    kaa.article_id,
    kaa.file_name,
    dc.extracted_text,
    ts_rank(to_tsvector('spanish', dc.extracted_text), plainto_tsquery('spanish', search_query)) as relevance_score
  FROM public.document_content dc
  JOIN public.knowledge_article_attachments kaa ON dc.attachment_id = kaa.id
  WHERE dc.processing_status = 'completed'
    AND to_tsvector('spanish', dc.extracted_text) @@ plainto_tsquery('spanish', search_query)
  ORDER BY relevance_score DESC
  LIMIT 10;
$$;


ALTER FUNCTION "public"."search_document_content"("search_query" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_organizations_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_organizations_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_tenant_configurations_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_tenant_configurations_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_ticket_form_responses_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_ticket_form_responses_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."upsert_system_setting"("setting_key" "text", "setting_value" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  INSERT INTO public.system_settings (key, value)
  VALUES (setting_key, setting_value::JSONB)
  ON CONFLICT (key) DO UPDATE
  SET value = setting_value::JSONB, updated_at = now();
  
  RETURN TRUE;
END;
$$;


ALTER FUNCTION "public"."upsert_system_setting"("setting_key" "text", "setting_value" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."user_exists_in_users_table"("user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.users WHERE id = user_id
  );
END;
$$;


ALTER FUNCTION "public"."user_exists_in_users_table"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_rating_token"("token_param" "text") RETURNS TABLE("valid" boolean, "ticket_id" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    TRUE as valid,
    rt.ticket_id
  FROM public.rating_tokens rt
  WHERE rt.token = token_param
    AND rt.expires_at > NOW()
    AND rt.used_at IS NULL;
    
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::INTEGER;
  END IF;
END;
$$;


ALTER FUNCTION "public"."validate_rating_token"("token_param" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verify_ticket_comment_permission"("ticket_id" integer, "user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM tickets t
    WHERE t.id = ticket_id
    AND (
      t.created_by = user_id OR
      t.assigned_to = user_id OR
      EXISTS (
        SELECT 1 FROM users u
        WHERE u.id = user_id AND u.role IN ('admin', 'agent')
      )
    )
  );
$$;


ALTER FUNCTION "public"."verify_ticket_comment_permission"("ticket_id" integer, "user_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."audit_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "action" "text" NOT NULL,
    "resource_type" "text" NOT NULL,
    "resource_id" "text",
    "ip_address" "inet",
    "user_agent" "text",
    "details" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."audit_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."comment_attachments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "comment_id" integer NOT NULL,
    "file_name" "text" NOT NULL,
    "file_url" "text" NOT NULL,
    "file_type" "text",
    "file_size" integer,
    "uploaded_by" "uuid" NOT NULL,
    "uploaded_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."comment_attachments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."custom_forms" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "schema" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "organization_id" "uuid"
);


ALTER TABLE "public"."custom_forms" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."departments" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."departments" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."departments_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."departments_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."departments_id_seq" OWNED BY "public"."departments"."id";



CREATE TABLE IF NOT EXISTS "public"."document_content" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "attachment_id" "uuid" NOT NULL,
    "extracted_text" "text" NOT NULL,
    "content_chunks" "jsonb" DEFAULT '[]'::"jsonb",
    "processing_status" "text" DEFAULT 'pending'::"text",
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "document_content_processing_status_check" CHECK (("processing_status" = ANY (ARRAY['pending'::"text", 'processing'::"text", 'completed'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."document_content" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."failed_login_attempts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email" "text" NOT NULL,
    "ip_address" "inet" NOT NULL,
    "attempt_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_agent" "text"
);


ALTER TABLE "public"."failed_login_attempts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."incident_reporters" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "full_name" "text" NOT NULL,
    "email" "text" NOT NULL,
    "phone_number" "text",
    "department_id" integer,
    "registered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."incident_reporters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."knowledge_article_attachments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "article_id" "uuid" NOT NULL,
    "file_name" "text" NOT NULL,
    "file_url" "text" NOT NULL,
    "file_type" "text",
    "file_size" integer,
    "uploaded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "uploaded_by" "uuid" NOT NULL
);


ALTER TABLE "public"."knowledge_article_attachments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."knowledge_article_categories" (
    "article_id" "uuid" NOT NULL,
    "category_id" "uuid" NOT NULL
);


ALTER TABLE "public"."knowledge_article_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."knowledge_article_tags" (
    "article_id" "uuid" NOT NULL,
    "tag_id" "uuid" NOT NULL
);


ALTER TABLE "public"."knowledge_article_tags" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."knowledge_articles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "content" "text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "organization_id" "uuid"
);


ALTER TABLE "public"."knowledge_articles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."knowledge_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."knowledge_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."knowledge_tags" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."knowledge_tags" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notification_settings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "new_tickets" boolean DEFAULT true,
    "sla_breaches" boolean DEFAULT true,
    "high_priority_tickets" boolean DEFAULT true,
    "stalled_tickets" boolean DEFAULT true,
    "reopened_tickets" boolean DEFAULT true,
    "new_users" boolean DEFAULT true,
    "kb_article_updates" boolean DEFAULT true,
    "automation_failures" boolean DEFAULT true,
    "performance_metrics" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."notification_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recipient_id" "uuid" NOT NULL,
    "type" character varying(50) NOT NULL,
    "title" character varying(255) NOT NULL,
    "message" "text" NOT NULL,
    "related_entity_type" character varying(50),
    "related_entity_id" character varying(255),
    "priority" character varying(20) DEFAULT 'normal'::character varying,
    "read" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "expires_at" timestamp with time zone
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nps_responses" (
    "id" integer NOT NULL,
    "ticket_id" integer NOT NULL,
    "user_id" "uuid" NOT NULL,
    "score" integer NOT NULL,
    "comment" "text",
    "submitted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "nps_responses_score_check" CHECK ((("score" >= 1) AND ("score" <= 5)))
);


ALTER TABLE "public"."nps_responses" OWNER TO "postgres";


COMMENT ON TABLE "public"."nps_responses" IS 'Almacena respuestas de encuestas Net Promoter Score (NPS) para tickets';



COMMENT ON COLUMN "public"."nps_responses"."id" IS 'Identificador único para cada respuesta NPS';



COMMENT ON COLUMN "public"."nps_responses"."ticket_id" IS 'ID del ticket asociado a esta respuesta NPS';



COMMENT ON COLUMN "public"."nps_responses"."user_id" IS 'ID del usuario que completó la encuesta NPS';



COMMENT ON COLUMN "public"."nps_responses"."score" IS 'Puntuación NPS en escala de 1 a 5';



COMMENT ON COLUMN "public"."nps_responses"."comment" IS 'Comentario opcional proporcionado por el usuario';



COMMENT ON COLUMN "public"."nps_responses"."submitted_at" IS 'Fecha y hora en que se envió la respuesta';



CREATE SEQUENCE IF NOT EXISTS "public"."nps_responses_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."nps_responses_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."nps_responses_id_seq" OWNED BY "public"."nps_responses"."id";



CREATE TABLE IF NOT EXISTS "public"."organizations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "domain" "text",
    "logo_url" "text",
    "settings" "jsonb" DEFAULT '{}'::"jsonb",
    "subscription_plan" "text" DEFAULT 'basic'::"text",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."organizations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rate_limits" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "identifier" "text" NOT NULL,
    "endpoint" "text" NOT NULL,
    "requests_count" integer DEFAULT 1 NOT NULL,
    "window_start" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."rate_limits" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rating_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "token" "text" NOT NULL,
    "ticket_id" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '7 days'::interval) NOT NULL,
    "used_at" timestamp with time zone
);


ALTER TABLE "public"."rating_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."request_types" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "form_id" "uuid" DEFAULT "gen_random_uuid"(),
    "organization_id" "uuid",
    "default_agent_id" "uuid"
);


ALTER TABLE "public"."request_types" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."request_types_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."request_types_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."request_types_id_seq" OWNED BY "public"."request_types"."id";



CREATE TABLE IF NOT EXISTS "public"."security_settings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "setting_key" "text" NOT NULL,
    "setting_value" "jsonb" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."security_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."system_settings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "value" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."system_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tenant_configurations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "feature_key" "text" NOT NULL,
    "configuration" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "is_enabled" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."tenant_configurations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ticket_attachments" (
    "id" integer NOT NULL,
    "ticket_id" integer NOT NULL,
    "file_name" "text" NOT NULL,
    "file_url" "text" NOT NULL,
    "file_type" "text",
    "file_size" integer,
    "uploaded_by" "uuid" NOT NULL,
    "uploaded_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ticket_attachments" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."ticket_attachments_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."ticket_attachments_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."ticket_attachments_id_seq" OWNED BY "public"."ticket_attachments"."id";



CREATE TABLE IF NOT EXISTS "public"."ticket_categories" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ticket_categories" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."ticket_categories_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."ticket_categories_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."ticket_categories_id_seq" OWNED BY "public"."ticket_categories"."id";



CREATE TABLE IF NOT EXISTS "public"."ticket_comments" (
    "id" integer NOT NULL,
    "ticket_id" integer NOT NULL,
    "content" "text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_internal" boolean DEFAULT false,
    "organization_id" "uuid"
);


ALTER TABLE "public"."ticket_comments" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."ticket_comments_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."ticket_comments_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."ticket_comments_id_seq" OWNED BY "public"."ticket_comments"."id";



CREATE TABLE IF NOT EXISTS "public"."ticket_form_responses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "ticket_id" integer NOT NULL,
    "form_id" "uuid" NOT NULL,
    "form_responses" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ticket_form_responses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ticket_ratings" (
    "id" integer NOT NULL,
    "ticket_id" integer NOT NULL,
    "rating" integer NOT NULL,
    "comment" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "organization_id" "uuid",
    CONSTRAINT "ticket_ratings_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5)))
);


ALTER TABLE "public"."ticket_ratings" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."ticket_ratings_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."ticket_ratings_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."ticket_ratings_id_seq" OWNED BY "public"."ticket_ratings"."id";



CREATE TABLE IF NOT EXISTS "public"."tickets" (
    "id" integer NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "status" "public"."ticket_status" DEFAULT 'abierto'::"public"."ticket_status" NOT NULL,
    "priority" "public"."ticket_priority" DEFAULT 'media'::"public"."ticket_priority" NOT NULL,
    "request_type" integer,
    "created_by" "uuid" NOT NULL,
    "assigned_to" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    "first_response_at" timestamp with time zone,
    "sla_breach_notified" boolean DEFAULT false,
    "stalled_notified" boolean DEFAULT false,
    "rating_requested" boolean DEFAULT false,
    "organization_id" "uuid"
);


ALTER TABLE "public"."tickets" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."tickets_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."tickets_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."tickets_id_seq" OWNED BY "public"."tickets"."id";



CREATE TABLE IF NOT EXISTS "public"."user_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "session_token" "text" NOT NULL,
    "ip_address" "inet",
    "user_agent" "text",
    "last_activity" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_sessions" OWNER TO "postgres";


ALTER TABLE ONLY "public"."departments" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."departments_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."nps_responses" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."nps_responses_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."request_types" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."request_types_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."ticket_attachments" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."ticket_attachments_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."ticket_categories" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."ticket_categories_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."ticket_comments" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."ticket_comments_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."ticket_ratings" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."ticket_ratings_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."tickets" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."tickets_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."comment_attachments"
    ADD CONSTRAINT "comment_attachments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."custom_forms"
    ADD CONSTRAINT "custom_forms_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."departments"
    ADD CONSTRAINT "departments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."document_content"
    ADD CONSTRAINT "document_content_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."failed_login_attempts"
    ADD CONSTRAINT "failed_login_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."incident_reporters"
    ADD CONSTRAINT "incident_reporters_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."incident_reporters"
    ADD CONSTRAINT "incident_reporters_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."knowledge_article_attachments"
    ADD CONSTRAINT "knowledge_article_attachments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."knowledge_article_categories"
    ADD CONSTRAINT "knowledge_article_categories_pkey" PRIMARY KEY ("article_id", "category_id");



ALTER TABLE ONLY "public"."knowledge_article_tags"
    ADD CONSTRAINT "knowledge_article_tags_pkey" PRIMARY KEY ("article_id", "tag_id");



ALTER TABLE ONLY "public"."knowledge_articles"
    ADD CONSTRAINT "knowledge_articles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."knowledge_categories"
    ADD CONSTRAINT "knowledge_categories_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."knowledge_categories"
    ADD CONSTRAINT "knowledge_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."knowledge_tags"
    ADD CONSTRAINT "knowledge_tags_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."knowledge_tags"
    ADD CONSTRAINT "knowledge_tags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_settings"
    ADD CONSTRAINT "notification_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_settings"
    ADD CONSTRAINT "notification_settings_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nps_responses"
    ADD CONSTRAINT "nps_responses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_domain_key" UNIQUE ("domain");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."rate_limits"
    ADD CONSTRAINT "rate_limits_identifier_endpoint_window_start_key" UNIQUE ("identifier", "endpoint", "window_start");



ALTER TABLE ONLY "public"."rate_limits"
    ADD CONSTRAINT "rate_limits_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rating_tokens"
    ADD CONSTRAINT "rating_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rating_tokens"
    ADD CONSTRAINT "rating_tokens_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."request_types"
    ADD CONSTRAINT "request_types_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."request_types"
    ADD CONSTRAINT "request_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."security_settings"
    ADD CONSTRAINT "security_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."security_settings"
    ADD CONSTRAINT "security_settings_setting_key_key" UNIQUE ("setting_key");



ALTER TABLE ONLY "public"."system_settings"
    ADD CONSTRAINT "system_settings_key_key" UNIQUE ("key");



ALTER TABLE ONLY "public"."system_settings"
    ADD CONSTRAINT "system_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tenant_configurations"
    ADD CONSTRAINT "tenant_configurations_organization_id_feature_key_key" UNIQUE ("organization_id", "feature_key");



ALTER TABLE ONLY "public"."tenant_configurations"
    ADD CONSTRAINT "tenant_configurations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ticket_attachments"
    ADD CONSTRAINT "ticket_attachments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ticket_categories"
    ADD CONSTRAINT "ticket_categories_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."ticket_categories"
    ADD CONSTRAINT "ticket_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ticket_comments"
    ADD CONSTRAINT "ticket_comments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ticket_form_responses"
    ADD CONSTRAINT "ticket_form_responses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ticket_form_responses"
    ADD CONSTRAINT "ticket_form_responses_ticket_id_key" UNIQUE ("ticket_id");



ALTER TABLE ONLY "public"."ticket_ratings"
    ADD CONSTRAINT "ticket_ratings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ticket_ratings"
    ADD CONSTRAINT "ticket_ratings_ticket_id_key" UNIQUE ("ticket_id");



ALTER TABLE ONLY "public"."tickets"
    ADD CONSTRAINT "tickets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_sessions"
    ADD CONSTRAINT "user_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_sessions"
    ADD CONSTRAINT "user_sessions_session_token_key" UNIQUE ("session_token");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_unique" UNIQUE ("email");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_audit_logs_user_id" ON "public"."audit_logs" USING "btree" ("user_id");



CREATE INDEX "idx_custom_forms_organization_id" ON "public"."custom_forms" USING "btree" ("organization_id");



CREATE INDEX "idx_document_content_attachment_id" ON "public"."document_content" USING "btree" ("attachment_id");



CREATE INDEX "idx_document_content_status" ON "public"."document_content" USING "btree" ("processing_status");



CREATE INDEX "idx_document_content_text_search" ON "public"."document_content" USING "gin" ("to_tsvector"('"spanish"'::"regconfig", "extracted_text"));



CREATE INDEX "idx_incident_reporters_department_id" ON "public"."incident_reporters" USING "btree" ("department_id");



CREATE INDEX "idx_incident_reporters_email" ON "public"."incident_reporters" USING "btree" ("email");



CREATE INDEX "idx_incident_reporters_registered_at" ON "public"."incident_reporters" USING "btree" ("registered_at" DESC);



CREATE INDEX "idx_knowledge_article_attachments_article_id" ON "public"."knowledge_article_attachments" USING "btree" ("article_id");



CREATE INDEX "idx_knowledge_article_categories_category_id" ON "public"."knowledge_article_categories" USING "btree" ("category_id");



CREATE INDEX "idx_knowledge_article_tags_tag_id" ON "public"."knowledge_article_tags" USING "btree" ("tag_id");



CREATE INDEX "idx_knowledge_articles_organization_id" ON "public"."knowledge_articles" USING "btree" ("organization_id");



CREATE INDEX "idx_notifications_recipient_id" ON "public"."notifications" USING "btree" ("recipient_id");



CREATE INDEX "idx_notifications_recipient_read" ON "public"."notifications" USING "btree" ("recipient_id", "read", "created_at" DESC);



CREATE INDEX "idx_rating_tokens_ticket_id" ON "public"."rating_tokens" USING "btree" ("ticket_id");



CREATE INDEX "idx_request_types_organization_id" ON "public"."request_types" USING "btree" ("organization_id");



CREATE INDEX "idx_ticket_attachments_ticket_id" ON "public"."ticket_attachments" USING "btree" ("ticket_id");



CREATE INDEX "idx_ticket_attachments_uploaded_by" ON "public"."ticket_attachments" USING "btree" ("uploaded_by");



CREATE INDEX "idx_ticket_comments_created_by" ON "public"."ticket_comments" USING "btree" ("created_by");



CREATE INDEX "idx_ticket_comments_organization_id" ON "public"."ticket_comments" USING "btree" ("organization_id");



CREATE INDEX "idx_ticket_comments_ticket_id" ON "public"."ticket_comments" USING "btree" ("ticket_id");



CREATE INDEX "idx_ticket_comments_ticket_id_created_at" ON "public"."ticket_comments" USING "btree" ("ticket_id", "created_at" DESC);



CREATE INDEX "idx_ticket_ratings_organization_id" ON "public"."ticket_ratings" USING "btree" ("organization_id");



CREATE INDEX "idx_tickets_assigned_to" ON "public"."tickets" USING "btree" ("assigned_to");



CREATE INDEX "idx_tickets_category" ON "public"."tickets" USING "btree" ("request_type");



CREATE INDEX "idx_tickets_category_id" ON "public"."tickets" USING "btree" ("request_type");



CREATE INDEX "idx_tickets_created_at" ON "public"."tickets" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_tickets_created_by" ON "public"."tickets" USING "btree" ("created_by");



CREATE INDEX "idx_tickets_description_gin" ON "public"."tickets" USING "gin" ("to_tsvector"('"spanish"'::"regconfig", "description"));



CREATE INDEX "idx_tickets_organization_id" ON "public"."tickets" USING "btree" ("organization_id");



CREATE INDEX "idx_tickets_priority" ON "public"."tickets" USING "btree" ("priority");



CREATE INDEX "idx_tickets_resolved_at" ON "public"."tickets" USING "btree" ("resolved_at");



CREATE INDEX "idx_tickets_status" ON "public"."tickets" USING "btree" ("status");



CREATE INDEX "idx_tickets_status_created_at" ON "public"."tickets" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "idx_tickets_status_priority" ON "public"."tickets" USING "btree" ("status", "priority");



CREATE INDEX "idx_tickets_title_gin" ON "public"."tickets" USING "gin" ("to_tsvector"('"spanish"'::"regconfig", "title"));



CREATE INDEX "idx_user_sessions_user_id" ON "public"."user_sessions" USING "btree" ("user_id");



CREATE INDEX "idx_users_department_id" ON "public"."users" USING "btree" ("department_id");



CREATE INDEX "idx_users_organization_id" ON "public"."users" USING "btree" ("organization_id");



CREATE INDEX "nps_responses_ticket_id_idx" ON "public"."nps_responses" USING "btree" ("ticket_id");



CREATE INDEX "nps_responses_user_id_idx" ON "public"."nps_responses" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "Ticket Updated WebHook" AFTER INSERT OR UPDATE ON "public"."tickets" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://aobhmkfncgyeehdrffce.supabase.co/functions/v1/ticket-updated-function', 'POST', '{"Content-type":"application/json"}', '{}', '5000');



CREATE OR REPLACE TRIGGER "set_custom_forms_updated_at" BEFORE UPDATE ON "public"."custom_forms" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."nps_responses" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_categories_updated_at" BEFORE UPDATE ON "public"."ticket_categories" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_incident_reporters_updated_at" BEFORE UPDATE ON "public"."incident_reporters" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_knowledge_articles_updated_at" BEFORE UPDATE ON "public"."knowledge_articles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_knowledge_categories_updated_at" BEFORE UPDATE ON "public"."knowledge_categories" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_organizations_updated_at" BEFORE UPDATE ON "public"."organizations" FOR EACH ROW EXECUTE FUNCTION "public"."update_organizations_updated_at"();



CREATE OR REPLACE TRIGGER "update_request_types_updated_at" BEFORE UPDATE ON "public"."request_types" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_tenant_configurations_updated_at" BEFORE UPDATE ON "public"."tenant_configurations" FOR EACH ROW EXECUTE FUNCTION "public"."update_tenant_configurations_updated_at"();



CREATE OR REPLACE TRIGGER "update_ticket_form_responses_updated_at" BEFORE UPDATE ON "public"."ticket_form_responses" FOR EACH ROW EXECUTE FUNCTION "public"."update_ticket_form_responses_updated_at"();



CREATE OR REPLACE TRIGGER "update_tickets_updated_at" BEFORE UPDATE ON "public"."tickets" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_users_updated_at" BEFORE UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."comment_attachments"
    ADD CONSTRAINT "comment_attachments_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "public"."ticket_comments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."custom_forms"
    ADD CONSTRAINT "custom_forms_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."document_content"
    ADD CONSTRAINT "document_content_attachment_id_fkey" FOREIGN KEY ("attachment_id") REFERENCES "public"."knowledge_article_attachments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."incident_reporters"
    ADD CONSTRAINT "incident_reporters_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id");



ALTER TABLE ONLY "public"."knowledge_article_attachments"
    ADD CONSTRAINT "knowledge_article_attachments_article_id_fkey" FOREIGN KEY ("article_id") REFERENCES "public"."knowledge_articles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."knowledge_article_categories"
    ADD CONSTRAINT "knowledge_article_categories_article_id_fkey" FOREIGN KEY ("article_id") REFERENCES "public"."knowledge_articles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."knowledge_article_categories"
    ADD CONSTRAINT "knowledge_article_categories_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."knowledge_categories"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."knowledge_article_tags"
    ADD CONSTRAINT "knowledge_article_tags_article_id_fkey" FOREIGN KEY ("article_id") REFERENCES "public"."knowledge_articles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."knowledge_article_tags"
    ADD CONSTRAINT "knowledge_article_tags_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "public"."knowledge_tags"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."knowledge_articles"
    ADD CONSTRAINT "knowledge_articles_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_settings"
    ADD CONSTRAINT "notification_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."nps_responses"
    ADD CONSTRAINT "nps_responses_ticket_id_fkey" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rating_tokens"
    ADD CONSTRAINT "rating_tokens_ticket_id_fkey" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."request_types"
    ADD CONSTRAINT "request_types_default_agent_id_fkey" FOREIGN KEY ("default_agent_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."request_types"
    ADD CONSTRAINT "request_types_form_id_fkey" FOREIGN KEY ("form_id") REFERENCES "public"."custom_forms"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."request_types"
    ADD CONSTRAINT "request_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tenant_configurations"
    ADD CONSTRAINT "tenant_configurations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ticket_attachments"
    ADD CONSTRAINT "ticket_attachments_ticket_id_fkey" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ticket_attachments"
    ADD CONSTRAINT "ticket_attachments_uploaded_by_fkey" FOREIGN KEY ("uploaded_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."ticket_comments"
    ADD CONSTRAINT "ticket_comments_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ticket_comments"
    ADD CONSTRAINT "ticket_comments_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ticket_comments"
    ADD CONSTRAINT "ticket_comments_ticket_id_fkey" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ticket_form_responses"
    ADD CONSTRAINT "ticket_form_responses_ticket_id_fkey" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ticket_ratings"
    ADD CONSTRAINT "ticket_ratings_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ticket_ratings"
    ADD CONSTRAINT "ticket_ratings_ticket_id_fkey" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tickets"
    ADD CONSTRAINT "tickets_assigned_to_fkey1" FOREIGN KEY ("assigned_to") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."tickets"
    ADD CONSTRAINT "tickets_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."tickets"
    ADD CONSTRAINT "tickets_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tickets"
    ADD CONSTRAINT "tickets_request_type_fkey" FOREIGN KEY ("request_type") REFERENCES "public"."request_types"("id");



ALTER TABLE ONLY "public"."user_sessions"
    ADD CONSTRAINT "user_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE SET NULL;



CREATE POLICY "Admin and agent access all tickets" ON "public"."tickets" FOR SELECT USING (("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Administradores y agentes pueden ver todos los reporteros" ON "public"."incident_reporters" FOR SELECT USING (("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Admins and agents can manage article attachments" ON "public"."knowledge_article_attachments" USING (("public"."get_current_user_role"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Admins and agents can manage article categories" ON "public"."knowledge_article_categories" USING (("public"."get_current_user_role"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Admins and agents can manage article tags" ON "public"."knowledge_article_tags" USING (("public"."get_current_user_role"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Admins and agents can manage knowledge articles" ON "public"."knowledge_articles" USING (("public"."get_current_user_role"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Admins and agents can manage knowledge tags" ON "public"."knowledge_tags" USING (("public"."get_current_user_role"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Admins can create users" ON "public"."users" FOR INSERT WITH CHECK (("public"."get_current_user_role_no_recursion"() = 'admin'::"text"));



CREATE POLICY "Admins can delete security settings" ON "public"."security_settings" FOR DELETE USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Admins can delete users" ON "public"."users" FOR DELETE USING (("public"."get_current_user_role_no_recursion"() = 'admin'::"text"));



CREATE POLICY "Admins can insert security settings" ON "public"."security_settings" FOR INSERT WITH CHECK (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Admins can manage all comments" ON "public"."ticket_comments" USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Admins can manage all ticket categories" ON "public"."ticket_categories" USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Admins can manage all tickets" ON "public"."tickets" USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Admins can manage all users" ON "public"."users" USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Admins can manage document content" ON "public"."document_content" USING ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."role" = ANY (ARRAY['admin'::"public"."app_role", 'agent'::"public"."app_role"]))))));



CREATE POLICY "Admins can manage forms" ON "public"."custom_forms" USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Admins can manage knowledge categories" ON "public"."knowledge_categories" USING (("public"."get_current_user_role"() = 'admin'::"text"));



CREATE POLICY "Admins can manage organizations" ON "public"."organizations" USING ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."role" = 'admin'::"public"."app_role") AND ("users"."organization_id" = "organizations"."id")))));



CREATE POLICY "Admins can manage tenant configurations" ON "public"."tenant_configurations" USING ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."role" = 'admin'::"public"."app_role") AND ("users"."organization_id" = "tenant_configurations"."organization_id")))));



CREATE POLICY "Admins can update organizations" ON "public"."organizations" FOR UPDATE USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Admins can update security settings" ON "public"."security_settings" FOR UPDATE USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Admins can update users" ON "public"."users" FOR UPDATE USING (("public"."get_current_user_role_no_recursion"() = 'admin'::"text"));



CREATE POLICY "Admins can view all NPS responses" ON "public"."nps_responses" FOR SELECT USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Admins can view all users" ON "public"."users" FOR SELECT USING (("public"."get_current_user_role_no_recursion"() = 'admin'::"text"));



CREATE POLICY "Admins can view security settings" ON "public"."security_settings" FOR SELECT USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Agentes pueden actualizar tickets" ON "public"."tickets" FOR UPDATE USING ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) OR ("assigned_to" = ( SELECT "auth"."uid"() AS "uid")) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"]))));



CREATE POLICY "Agentes pueden ver todos los comentarios" ON "public"."ticket_comments" FOR SELECT USING (("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Agents and admins can create articles" ON "public"."knowledge_articles" FOR INSERT WITH CHECK ((("created_by" = "auth"."uid"()) AND ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"]))));



CREATE POLICY "Agents and admins can manage knowledge articles" ON "public"."knowledge_articles" USING (("public"."get_user_role_safe"("auth"."uid"()) = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Agents can create comments" ON "public"."ticket_comments" FOR INSERT WITH CHECK ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) AND ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"]))));



CREATE POLICY "Agents can update assigned tickets" ON "public"."tickets" FOR UPDATE USING ((("assigned_to" = ( SELECT "auth"."uid"() AS "uid")) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"]))));



CREATE POLICY "Agents can view NPS responses for their assigned tickets" ON "public"."nps_responses" FOR SELECT USING ((("public"."get_user_role_safe"() = 'agent'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "nps_responses"."ticket_id") AND ("t"."assigned_to" = ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "Agents can view all comments" ON "public"."ticket_comments" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."role" = 'agent'::"public"."app_role")))));



CREATE POLICY "Agents can view all ticket categories" ON "public"."ticket_categories" FOR SELECT USING (("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Agents can view basic user profiles" ON "public"."users" FOR SELECT USING (("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Allow admins to delete system_settings" ON "public"."system_settings" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."role" = 'admin'::"public"."app_role")))));



CREATE POLICY "Allow admins to insert system_settings" ON "public"."system_settings" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."role" = 'admin'::"public"."app_role")))));



CREATE POLICY "Allow admins to update system_settings" ON "public"."system_settings" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."role" = 'admin'::"public"."app_role")))));



CREATE POLICY "Allow authenticated users to create rating tokens" ON "public"."rating_tokens" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Allow authenticated users to update rating tokens" ON "public"."rating_tokens" FOR UPDATE USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Allow read access to rating_tokens for authenticated users" ON "public"."rating_tokens" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Allow read access to system_settings for authenticated users" ON "public"."system_settings" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Allow user profile creation" ON "public"."users" FOR INSERT WITH CHECK (("id" = "auth"."uid"()));



CREATE POLICY "Anyone can view knowledge article attachments" ON "public"."knowledge_article_attachments" FOR SELECT USING (true);



CREATE POLICY "Anyone can view knowledge articles" ON "public"."knowledge_articles" FOR SELECT USING (true);



CREATE POLICY "Authenticated users can create attachments" ON "public"."knowledge_article_attachments" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Authenticated users can delete attachments" ON "public"."knowledge_article_attachments" FOR DELETE USING ((("uploaded_by" = ( SELECT "auth"."uid"() AS "uid")) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"]))));



CREATE POLICY "Authenticated users can update attachments" ON "public"."knowledge_article_attachments" FOR UPDATE USING ((("uploaded_by" = ( SELECT "auth"."uid"() AS "uid")) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"]))));



CREATE POLICY "Authors, agents and admins can update articles" ON "public"."knowledge_articles" FOR UPDATE USING ((("created_by" = "auth"."uid"()) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"]))));



CREATE POLICY "Clients can create comments on their tickets" ON "public"."ticket_comments" FOR INSERT WITH CHECK ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) AND (EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_comments"."ticket_id") AND ("t"."created_by" = ( SELECT "auth"."uid"() AS "uid")))))));



CREATE POLICY "Clients can create tickets" ON "public"."tickets" FOR INSERT WITH CHECK (("created_by" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Clients can insert their own NPS responses" ON "public"."nps_responses" FOR INSERT WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Clients can view all ticket categories" ON "public"."ticket_categories" FOR SELECT USING ((( SELECT "auth"."uid"() AS "uid") IS NOT NULL));



CREATE POLICY "Clients can view comments on their tickets" ON "public"."ticket_comments" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_comments"."ticket_id") AND ("t"."created_by" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Clients can view their own NPS responses" ON "public"."nps_responses" FOR SELECT USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Clients can view their own tickets" ON "public"."tickets" FOR SELECT USING (("created_by" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."ticket_comments" FOR DELETE USING ((( SELECT "auth"."uid"() AS "uid") = "created_by"));



CREATE POLICY "Enable insert for service role only" ON "public"."users" FOR INSERT TO "service_role" WITH CHECK (true);



CREATE POLICY "Enable read for authenticated users" ON "public"."users" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Enable update for service role only" ON "public"."users" FOR UPDATE TO "service_role" USING (true);



CREATE POLICY "Everyone can read forms" ON "public"."custom_forms" FOR SELECT USING (true);



CREATE POLICY "Los admin pueden eliminar valoraciones" ON "public"."ticket_ratings" FOR DELETE USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Los clientes pueden actualizar sus valoraciones" ON "public"."ticket_ratings" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_ratings"."ticket_id") AND ("t"."created_by" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Los clientes pueden valorar sus tickets" ON "public"."ticket_ratings" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_ratings"."ticket_id") AND ("t"."created_by" = ( SELECT "auth"."uid"() AS "uid"))))));



CREATE POLICY "Los usuarios pueden eliminar sus propios adjuntos" ON "public"."ticket_attachments" FOR DELETE USING ((("uploaded_by" = ( SELECT "auth"."uid"() AS "uid")) OR ("public"."get_user_role_safe"() = 'admin'::"text")));



CREATE POLICY "Los usuarios pueden subir adjuntos a sus tickets" ON "public"."ticket_attachments" FOR INSERT WITH CHECK ((("uploaded_by" = ( SELECT "auth"."uid"() AS "uid")) AND (EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_attachments"."ticket_id") AND (("t"."created_by" = ( SELECT "auth"."uid"() AS "uid")) OR ("t"."assigned_to" = ( SELECT "auth"."uid"() AS "uid")) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"]))))))));



CREATE POLICY "Los usuarios pueden ver adjuntos de sus tickets" ON "public"."ticket_attachments" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_attachments"."ticket_id") AND (("t"."created_by" = ( SELECT "auth"."uid"() AS "uid")) OR ("t"."assigned_to" = ( SELECT "auth"."uid"() AS "uid")) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])))))));



CREATE POLICY "Los usuarios pueden ver sus propios datos" ON "public"."incident_reporters" FOR SELECT USING (("email" = (( SELECT "u"."email"
   FROM "auth"."users" "u"
  WHERE ("u"."id" = ( SELECT "auth"."uid"() AS "uid"))))::"text"));



CREATE POLICY "Los usuarios pueden ver valoraciones de sus tickets" ON "public"."ticket_ratings" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_ratings"."ticket_id") AND (("t"."created_by" = ( SELECT "auth"."uid"() AS "uid")) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])))))));



CREATE POLICY "No one can delete NPS responses" ON "public"."nps_responses" FOR DELETE USING (false);



CREATE POLICY "Permitir todas las operaciones temporalmente" ON "public"."users" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Solo administradores pueden modificar departamentos" ON "public"."departments" USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Solo administradores pueden modificar reporteros" ON "public"."incident_reporters" USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Solo administradores pueden modificar tipos de solicitud" ON "public"."request_types" USING (("public"."get_user_role_safe"() = 'admin'::"text"));



CREATE POLICY "Solo agents y admin pueden actualizar artículos" ON "public"."knowledge_articles" FOR UPDATE USING ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"]))));



CREATE POLICY "Solo agents y admin pueden crear artículos" ON "public"."knowledge_articles" FOR INSERT WITH CHECK ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) AND ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"]))));



CREATE POLICY "Solo agents y admin pueden eliminar artículos" ON "public"."knowledge_articles" FOR DELETE USING (("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Solo agents y admin pueden gestionar categorías" ON "public"."knowledge_categories" USING (("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Solo agents y admin pueden gestionar etiquetas" ON "public"."knowledge_tags" USING (("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Solo agents y admin pueden gestionar relaciones artículos-cate" ON "public"."knowledge_article_categories" USING (("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "Solo agents y admin pueden gestionar relaciones artículos-etiq" ON "public"."knowledge_article_tags" USING (("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])));



CREATE POLICY "System can insert audit logs" ON "public"."audit_logs" FOR INSERT WITH CHECK (true);



CREATE POLICY "System can insert failed attempts" ON "public"."failed_login_attempts" FOR INSERT WITH CHECK (true);



CREATE POLICY "System can manage rate limits" ON "public"."rate_limits" USING (true);



CREATE POLICY "System can manage sessions" ON "public"."user_sessions" USING (true);



CREATE POLICY "Todos pueden ver departamentos" ON "public"."departments" FOR SELECT USING (true);



CREATE POLICY "Todos pueden ver las categorías" ON "public"."knowledge_categories" FOR SELECT USING (true);



CREATE POLICY "Todos pueden ver las etiquetas" ON "public"."knowledge_tags" FOR SELECT USING (true);



CREATE POLICY "Todos pueden ver las relaciones artículos-categorías" ON "public"."knowledge_article_categories" FOR SELECT USING (true);



CREATE POLICY "Todos pueden ver las relaciones artículos-etiquetas" ON "public"."knowledge_article_tags" FOR SELECT USING (true);



CREATE POLICY "Todos pueden ver los artículos" ON "public"."knowledge_articles" FOR SELECT USING (true);



CREATE POLICY "Todos pueden ver los tipos de solicitud" ON "public"."request_types" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Users can add comments to accessible tickets" ON "public"."ticket_comments" FOR INSERT WITH CHECK ("public"."can_access_ticket"("ticket_id", "auth"."uid"()));



CREATE POLICY "Users can create comments in their organization" ON "public"."ticket_comments" FOR INSERT WITH CHECK (("organization_id" IN ( SELECT "users"."organization_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Users can create tickets" ON "public"."tickets" FOR INSERT WITH CHECK (("auth"."uid"() = "created_by"));



CREATE POLICY "Users can create tickets in their organization" ON "public"."tickets" FOR INSERT WITH CHECK (("organization_id" IN ( SELECT "users"."organization_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Users can delete form responses for their tickets" ON "public"."ticket_form_responses" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_form_responses"."ticket_id") AND ("t"."created_by" = "auth"."uid"())))));



CREATE POLICY "Users can delete their own comment attachments" ON "public"."comment_attachments" FOR DELETE USING ((("uploaded_by" = "auth"."uid"()) OR ("public"."get_user_role_safe"() = 'admin'::"text")));



CREATE POLICY "Users can insert form responses for their tickets" ON "public"."ticket_form_responses" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_form_responses"."ticket_id") AND ("t"."created_by" = "auth"."uid"())))));



CREATE POLICY "Users can update accessible tickets" ON "public"."tickets" FOR UPDATE USING ("public"."can_access_ticket"("id", "auth"."uid"()));



CREATE POLICY "Users can update form responses for tickets they can access" ON "public"."ticket_form_responses" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_form_responses"."ticket_id") AND (("t"."created_by" = "auth"."uid"()) OR ("t"."assigned_to" = "auth"."uid"()) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])))))));



CREATE POLICY "Users can update own profile" ON "public"."users" FOR UPDATE USING (("id" = "auth"."uid"()));



CREATE POLICY "Users can update own profile data" ON "public"."users" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can update own profile or admins can update any" ON "public"."users" FOR UPDATE USING ((("id" = ( SELECT "auth"."uid"() AS "uid")) OR ("public"."get_user_role_safe"() = 'admin'::"text")));



CREATE POLICY "Users can update their own notification settings" ON "public"."notification_settings" FOR UPDATE USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can update their own notifications" ON "public"."notifications" FOR UPDATE USING (("recipient_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can update their own profile" ON "public"."users" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can update tickets in their organization" ON "public"."tickets" FOR UPDATE USING (("organization_id" IN ( SELECT "users"."organization_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Users can upload attachments to accessible tickets" ON "public"."ticket_attachments" FOR INSERT WITH CHECK ((("uploaded_by" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_attachments"."ticket_id") AND (("t"."created_by" = "auth"."uid"()) OR ("t"."assigned_to" = "auth"."uid"()) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"]))))))));



CREATE POLICY "Users can upload attachments to their comments" ON "public"."comment_attachments" FOR INSERT WITH CHECK ((("uploaded_by" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM ("public"."ticket_comments" "tc"
     JOIN "public"."tickets" "t" ON (("t"."id" = "tc"."ticket_id")))
  WHERE (("tc"."id" = "comment_attachments"."comment_id") AND ("tc"."created_by" = "auth"."uid"()))))));



CREATE POLICY "Users can view accessible tickets" ON "public"."tickets" FOR SELECT USING ("public"."can_access_ticket"("id", "auth"."uid"()));



CREATE POLICY "Users can view article attachments" ON "public"."knowledge_article_attachments" FOR SELECT USING (true);



CREATE POLICY "Users can view article categories" ON "public"."knowledge_article_categories" FOR SELECT USING (true);



CREATE POLICY "Users can view article tags" ON "public"."knowledge_article_tags" FOR SELECT USING (true);



CREATE POLICY "Users can view attachments on accessible comments" ON "public"."comment_attachments" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."ticket_comments" "tc"
     JOIN "public"."tickets" "t" ON (("t"."id" = "tc"."ticket_id")))
  WHERE (("tc"."id" = "comment_attachments"."comment_id") AND (("t"."created_by" = "auth"."uid"()) OR ("t"."assigned_to" = "auth"."uid"()) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])))))));



CREATE POLICY "Users can view attachments on accessible tickets" ON "public"."ticket_attachments" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_attachments"."ticket_id") AND (("t"."created_by" = "auth"."uid"()) OR ("t"."assigned_to" = "auth"."uid"()) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])))))));



CREATE POLICY "Users can view comments in their organization" ON "public"."ticket_comments" FOR SELECT USING (("organization_id" IN ( SELECT "users"."organization_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Users can view comments on accessible tickets" ON "public"."ticket_comments" FOR SELECT USING ("public"."can_access_ticket"("ticket_id", "auth"."uid"()));



CREATE POLICY "Users can view document content" ON "public"."document_content" FOR SELECT USING (true);



CREATE POLICY "Users can view form responses for tickets they can access" ON "public"."ticket_form_responses" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_form_responses"."ticket_id") AND (("t"."created_by" = "auth"."uid"()) OR ("t"."assigned_to" = "auth"."uid"()) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])))))));



CREATE POLICY "Users can view knowledge articles" ON "public"."knowledge_articles" FOR SELECT USING (true);



CREATE POLICY "Users can view knowledge categories" ON "public"."knowledge_categories" FOR SELECT USING (true);



CREATE POLICY "Users can view knowledge tags" ON "public"."knowledge_tags" FOR SELECT USING (true);



CREATE POLICY "Users can view own profile" ON "public"."users" FOR SELECT USING (("id" = "auth"."uid"()));



CREATE POLICY "Users can view own sessions" ON "public"."user_sessions" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view own tickets" ON "public"."tickets" FOR SELECT USING (("created_by" = "auth"."uid"()));



CREATE POLICY "Users can view profiles" ON "public"."users" FOR SELECT USING ((("id" = ( SELECT "auth"."uid"() AS "uid")) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"]))));



CREATE POLICY "Users can view their organization" ON "public"."organizations" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."users" "u"
  WHERE (("u"."id" = "auth"."uid"()) AND ("u"."organization_id" = "u"."id")))));



CREATE POLICY "Users can view their own notification settings" ON "public"."notification_settings" FOR SELECT USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view their own notifications" ON "public"."notifications" FOR SELECT USING (("recipient_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can view their own profile" ON "public"."users" FOR SELECT USING ((("auth"."uid"() = "id") OR ("public"."get_user_role_safe"("auth"."uid"()) = 'admin'::"text")));



CREATE POLICY "Users can view their tenant configurations" ON "public"."tenant_configurations" FOR SELECT USING (("organization_id" IN ( SELECT "users"."organization_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Users can view tickets in their organization" ON "public"."tickets" FOR SELECT USING (("organization_id" IN ( SELECT "users"."organization_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Usuarios pueden crear tickets" ON "public"."tickets" FOR INSERT WITH CHECK (("created_by" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Usuarios pueden ver comentarios de sus tickets" ON "public"."ticket_comments" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."tickets" "t"
  WHERE (("t"."id" = "ticket_comments"."ticket_id") AND (("t"."created_by" = ( SELECT "auth"."uid"() AS "uid")) OR ("t"."assigned_to" = ( SELECT "auth"."uid"() AS "uid")) OR ("public"."get_user_role_safe"() = ANY (ARRAY['admin'::"text", 'agent'::"text"])))))));



CREATE POLICY "Usuarios pueden ver sus propios tickets" ON "public"."tickets" FOR SELECT USING (("created_by" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."audit_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."comment_attachments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."custom_forms" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."departments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."document_content" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."failed_login_attempts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."incident_reporters" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."knowledge_article_attachments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."knowledge_article_categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."knowledge_article_tags" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."knowledge_articles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."knowledge_categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."knowledge_tags" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."nps_responses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."organizations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rate_limits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rating_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."request_types" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."security_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."system_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tenant_configurations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ticket_attachments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ticket_categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ticket_comments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ticket_form_responses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ticket_ratings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tickets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."can_access_ticket"("ticket_id" integer, "user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_access_ticket"("ticket_id" integer, "user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_access_ticket"("ticket_id" integer, "user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."can_add_comment_to_ticket"("ticket_id" integer, "user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_add_comment_to_ticket"("ticket_id" integer, "user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_add_comment_to_ticket"("ticket_id" integer, "user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."can_view_ticket_comments"("user_id" "uuid", "ticket_id" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."can_view_ticket_comments"("user_id" "uuid", "ticket_id" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_view_ticket_comments"("user_id" "uuid", "ticket_id" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."check_rate_limit"("identifier_param" "text", "endpoint_param" "text", "max_requests" integer, "window_minutes" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."check_rate_limit"("identifier_param" "text", "endpoint_param" "text", "max_requests" integer, "window_minutes" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_rate_limit"("identifier_param" "text", "endpoint_param" "text", "max_requests" integer, "window_minutes" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_security_data"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_security_data"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_security_data"() TO "service_role";



GRANT ALL ON FUNCTION "public"."create_default_notification_settings"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_default_notification_settings"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_default_notification_settings"() TO "service_role";



GRANT ALL ON FUNCTION "public"."create_rating_token"("ticket_id_param" integer, "token_param" "text", "expires_at_param" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."create_rating_token"("ticket_id_param" integer, "token_param" "text", "expires_at_param" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_rating_token"("ticket_id_param" integer, "token_param" "text", "expires_at_param" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_admin_users"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_admin_users"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_admin_users"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_current_user_organization"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_current_user_organization"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_current_user_organization"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_current_user_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_current_user_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_current_user_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_current_user_role_no_recursion"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_current_user_role_no_recursion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_current_user_role_no_recursion"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_current_user_role_safe"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_current_user_role_safe"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_current_user_role_safe"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_system_setting"("setting_key" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_system_setting"("setting_key" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_system_setting"("setting_key" "text") TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_by_id"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_by_id"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_by_id"("user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_role"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_role"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_role"("user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_role_safe"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_role_safe"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_role_safe"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_role_safe"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_role_safe"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_role_safe"("user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."has_role"("user_id" "uuid", "requested_role" "public"."app_role") TO "anon";
GRANT ALL ON FUNCTION "public"."has_role"("user_id" "uuid", "requested_role" "public"."app_role") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_role"("user_id" "uuid", "requested_role" "public"."app_role") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"("user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."log_audit_event"("user_id_param" "uuid", "action_param" "text", "resource_type_param" "text", "resource_id_param" "text", "ip_address_param" "inet", "user_agent_param" "text", "details_param" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."log_audit_event"("user_id_param" "uuid", "action_param" "text", "resource_type_param" "text", "resource_id_param" "text", "ip_address_param" "inet", "user_agent_param" "text", "details_param" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_audit_event"("user_id_param" "uuid", "action_param" "text", "resource_type_param" "text", "resource_id_param" "text", "ip_address_param" "inet", "user_agent_param" "text", "details_param" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_rating_token_used"("token_param" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_rating_token_used"("token_param" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_rating_token_used"("token_param" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."search_document_content"("search_query" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."search_document_content"("search_query" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_document_content"("search_query" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_organizations_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_organizations_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_organizations_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_tenant_configurations_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_tenant_configurations_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_tenant_configurations_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_ticket_form_responses_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_ticket_form_responses_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_ticket_form_responses_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



GRANT ALL ON FUNCTION "public"."upsert_system_setting"("setting_key" "text", "setting_value" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."upsert_system_setting"("setting_key" "text", "setting_value" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."upsert_system_setting"("setting_key" "text", "setting_value" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."user_exists_in_users_table"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."user_exists_in_users_table"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."user_exists_in_users_table"("user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_rating_token"("token_param" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."validate_rating_token"("token_param" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_rating_token"("token_param" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."verify_ticket_comment_permission"("ticket_id" integer, "user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."verify_ticket_comment_permission"("ticket_id" integer, "user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."verify_ticket_comment_permission"("ticket_id" integer, "user_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."audit_logs" TO "anon";
GRANT ALL ON TABLE "public"."audit_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."audit_logs" TO "service_role";



GRANT ALL ON TABLE "public"."comment_attachments" TO "anon";
GRANT ALL ON TABLE "public"."comment_attachments" TO "authenticated";
GRANT ALL ON TABLE "public"."comment_attachments" TO "service_role";



GRANT ALL ON TABLE "public"."custom_forms" TO "anon";
GRANT ALL ON TABLE "public"."custom_forms" TO "authenticated";
GRANT ALL ON TABLE "public"."custom_forms" TO "service_role";



GRANT ALL ON TABLE "public"."departments" TO "anon";
GRANT ALL ON TABLE "public"."departments" TO "authenticated";
GRANT ALL ON TABLE "public"."departments" TO "service_role";



GRANT ALL ON SEQUENCE "public"."departments_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."departments_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."departments_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."document_content" TO "anon";
GRANT ALL ON TABLE "public"."document_content" TO "authenticated";
GRANT ALL ON TABLE "public"."document_content" TO "service_role";



GRANT ALL ON TABLE "public"."failed_login_attempts" TO "anon";
GRANT ALL ON TABLE "public"."failed_login_attempts" TO "authenticated";
GRANT ALL ON TABLE "public"."failed_login_attempts" TO "service_role";



GRANT ALL ON TABLE "public"."incident_reporters" TO "anon";
GRANT ALL ON TABLE "public"."incident_reporters" TO "authenticated";
GRANT ALL ON TABLE "public"."incident_reporters" TO "service_role";



GRANT ALL ON TABLE "public"."knowledge_article_attachments" TO "anon";
GRANT ALL ON TABLE "public"."knowledge_article_attachments" TO "authenticated";
GRANT ALL ON TABLE "public"."knowledge_article_attachments" TO "service_role";



GRANT ALL ON TABLE "public"."knowledge_article_categories" TO "anon";
GRANT ALL ON TABLE "public"."knowledge_article_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."knowledge_article_categories" TO "service_role";



GRANT ALL ON TABLE "public"."knowledge_article_tags" TO "anon";
GRANT ALL ON TABLE "public"."knowledge_article_tags" TO "authenticated";
GRANT ALL ON TABLE "public"."knowledge_article_tags" TO "service_role";



GRANT ALL ON TABLE "public"."knowledge_articles" TO "anon";
GRANT ALL ON TABLE "public"."knowledge_articles" TO "authenticated";
GRANT ALL ON TABLE "public"."knowledge_articles" TO "service_role";



GRANT ALL ON TABLE "public"."knowledge_categories" TO "anon";
GRANT ALL ON TABLE "public"."knowledge_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."knowledge_categories" TO "service_role";



GRANT ALL ON TABLE "public"."knowledge_tags" TO "anon";
GRANT ALL ON TABLE "public"."knowledge_tags" TO "authenticated";
GRANT ALL ON TABLE "public"."knowledge_tags" TO "service_role";



GRANT ALL ON TABLE "public"."notification_settings" TO "anon";
GRANT ALL ON TABLE "public"."notification_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_settings" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."nps_responses" TO "anon";
GRANT ALL ON TABLE "public"."nps_responses" TO "authenticated";
GRANT ALL ON TABLE "public"."nps_responses" TO "service_role";



GRANT ALL ON SEQUENCE "public"."nps_responses_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."nps_responses_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."nps_responses_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."organizations" TO "anon";
GRANT ALL ON TABLE "public"."organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."organizations" TO "service_role";



GRANT ALL ON TABLE "public"."rate_limits" TO "anon";
GRANT ALL ON TABLE "public"."rate_limits" TO "authenticated";
GRANT ALL ON TABLE "public"."rate_limits" TO "service_role";



GRANT ALL ON TABLE "public"."rating_tokens" TO "anon";
GRANT ALL ON TABLE "public"."rating_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."rating_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."request_types" TO "anon";
GRANT ALL ON TABLE "public"."request_types" TO "authenticated";
GRANT ALL ON TABLE "public"."request_types" TO "service_role";



GRANT ALL ON SEQUENCE "public"."request_types_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."request_types_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."request_types_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."security_settings" TO "anon";
GRANT ALL ON TABLE "public"."security_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."security_settings" TO "service_role";



GRANT ALL ON TABLE "public"."system_settings" TO "anon";
GRANT ALL ON TABLE "public"."system_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."system_settings" TO "service_role";



GRANT ALL ON TABLE "public"."tenant_configurations" TO "anon";
GRANT ALL ON TABLE "public"."tenant_configurations" TO "authenticated";
GRANT ALL ON TABLE "public"."tenant_configurations" TO "service_role";



GRANT ALL ON TABLE "public"."ticket_attachments" TO "anon";
GRANT ALL ON TABLE "public"."ticket_attachments" TO "authenticated";
GRANT ALL ON TABLE "public"."ticket_attachments" TO "service_role";



GRANT ALL ON SEQUENCE "public"."ticket_attachments_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."ticket_attachments_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."ticket_attachments_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."ticket_categories" TO "anon";
GRANT ALL ON TABLE "public"."ticket_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."ticket_categories" TO "service_role";



GRANT ALL ON SEQUENCE "public"."ticket_categories_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."ticket_categories_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."ticket_categories_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."ticket_comments" TO "anon";
GRANT ALL ON TABLE "public"."ticket_comments" TO "authenticated";
GRANT ALL ON TABLE "public"."ticket_comments" TO "service_role";



GRANT ALL ON SEQUENCE "public"."ticket_comments_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."ticket_comments_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."ticket_comments_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."ticket_form_responses" TO "anon";
GRANT ALL ON TABLE "public"."ticket_form_responses" TO "authenticated";
GRANT ALL ON TABLE "public"."ticket_form_responses" TO "service_role";



GRANT ALL ON TABLE "public"."ticket_ratings" TO "anon";
GRANT ALL ON TABLE "public"."ticket_ratings" TO "authenticated";
GRANT ALL ON TABLE "public"."ticket_ratings" TO "service_role";



GRANT ALL ON SEQUENCE "public"."ticket_ratings_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."ticket_ratings_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."ticket_ratings_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."tickets" TO "anon";
GRANT ALL ON TABLE "public"."tickets" TO "authenticated";
GRANT ALL ON TABLE "public"."tickets" TO "service_role";



GRANT ALL ON SEQUENCE "public"."tickets_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."tickets_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."tickets_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."user_sessions" TO "anon";
GRANT ALL ON TABLE "public"."user_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."user_sessions" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






RESET ALL;
