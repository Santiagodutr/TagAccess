


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


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






CREATE SCHEMA IF NOT EXISTS "pgmq_public";


ALTER SCHEMA "pgmq_public" OWNER TO "postgres";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgmq";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."room_type" AS ENUM (
    'AULA',
    'LABORATORIO'
);


ALTER TYPE "public"."room_type" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pgmq_public"."archive"("queue_name" "text", "message_id" bigint) RETURNS boolean
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$ begin return pgmq.archive( queue_name := queue_name, msg_id := message_id ); end; $$;


ALTER FUNCTION "pgmq_public"."archive"("queue_name" "text", "message_id" bigint) OWNER TO "postgres";


COMMENT ON FUNCTION "pgmq_public"."archive"("queue_name" "text", "message_id" bigint) IS 'Archives a message by moving it from the queue to a permanent archive.';



CREATE OR REPLACE FUNCTION "pgmq_public"."delete"("queue_name" "text", "message_id" bigint) RETURNS boolean
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$ begin return pgmq.delete( queue_name := queue_name, msg_id := message_id ); end; $$;


ALTER FUNCTION "pgmq_public"."delete"("queue_name" "text", "message_id" bigint) OWNER TO "postgres";


COMMENT ON FUNCTION "pgmq_public"."delete"("queue_name" "text", "message_id" bigint) IS 'Permanently deletes a message from the specified queue.';



CREATE OR REPLACE FUNCTION "pgmq_public"."pop"("queue_name" "text") RETURNS SETOF "pgmq"."message_record"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$ begin return query select * from pgmq.pop( queue_name := queue_name ); end; $$;


ALTER FUNCTION "pgmq_public"."pop"("queue_name" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "pgmq_public"."pop"("queue_name" "text") IS 'Retrieves and locks the next message from the specified queue.';



CREATE OR REPLACE FUNCTION "pgmq_public"."read"("queue_name" "text", "sleep_seconds" integer, "n" integer) RETURNS SETOF "pgmq"."message_record"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$ begin return query select * from pgmq.read( queue_name := queue_name, vt := sleep_seconds, qty := n , conditional := '{}'::jsonb ); end; $$;


ALTER FUNCTION "pgmq_public"."read"("queue_name" "text", "sleep_seconds" integer, "n" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "pgmq_public"."read"("queue_name" "text", "sleep_seconds" integer, "n" integer) IS 'Reads up to "n" messages from the specified queue with an optional "sleep_seconds" (visibility timeout).';



CREATE OR REPLACE FUNCTION "pgmq_public"."send"("queue_name" "text", "message" "jsonb", "sleep_seconds" integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$ begin return query select * from pgmq.send( queue_name := queue_name, msg := message, delay := sleep_seconds ); end; $$;


ALTER FUNCTION "pgmq_public"."send"("queue_name" "text", "message" "jsonb", "sleep_seconds" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "pgmq_public"."send"("queue_name" "text", "message" "jsonb", "sleep_seconds" integer) IS 'Sends a message to the specified queue, optionally delaying its availability by a number of seconds.';



CREATE OR REPLACE FUNCTION "pgmq_public"."send_batch"("queue_name" "text", "messages" "jsonb"[], "sleep_seconds" integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$ begin return query select * from pgmq.send_batch( queue_name := queue_name, msgs := messages, delay := sleep_seconds ); end; $$;


ALTER FUNCTION "pgmq_public"."send_batch"("queue_name" "text", "messages" "jsonb"[], "sleep_seconds" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "pgmq_public"."send_batch"("queue_name" "text", "messages" "jsonb"[], "sleep_seconds" integer) IS 'Sends a batch of messages to the specified queue, optionally delaying their availability by a number of seconds.';



CREATE OR REPLACE FUNCTION "public"."confirm_new_user_rpc"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  result json;
BEGIN
  -- This will be called via API from the backend
  result := json_build_object('status', 'success', 'message', 'Confirmation would happen via API');
  RETURN result;
END;
$$;


ALTER FUNCTION "public"."confirm_new_user_rpc"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  user_name text;
BEGIN
  -- Extract name from raw_user_meta_data or default to email
  user_name := COALESCE(NEW.raw_user_meta_data->>'name', NEW.email);
  
  -- Insert into public.users table
  INSERT INTO public.users (id, email, name, is_admin, created_at)
  VALUES (NEW.id, NEW.email, user_name, FALSE, NOW())
  ON CONFLICT (id) DO NOTHING;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_user_admin"("user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.users 
    WHERE id = user_id AND is_admin = true
  );
$$;


ALTER FUNCTION "public"."is_user_admin"("user_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."access_blocks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "card_uid" "text" NOT NULL,
    "room_id" "uuid" NOT NULL,
    "reason" "text",
    "blocked_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."access_blocks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."access_events" (
    "id" bigint NOT NULL,
    "card_uid" "text",
    "raspberry_id" "uuid",
    "room_id" "uuid",
    "event_time" timestamp with time zone DEFAULT "now"(),
    "authorized" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."access_events" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."access_events_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."access_events_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."access_events_id_seq" OWNED BY "public"."access_events"."id";



CREATE OR REPLACE VIEW "public"."access_log_actions" AS
 WITH "ordered" AS (
         SELECT "access_events"."card_uid",
            "access_events"."room_id",
            "access_events"."event_time",
            "lag"("access_events"."room_id") OVER (PARTITION BY "access_events"."card_uid" ORDER BY "access_events"."event_time") AS "prev_room"
           FROM "public"."access_events"
        ), "numbered" AS (
         SELECT "ordered"."card_uid",
            "ordered"."room_id",
            "ordered"."event_time",
            "ordered"."prev_room",
                CASE
                    WHEN ("ordered"."prev_room" IS DISTINCT FROM "ordered"."room_id") THEN 1
                    ELSE 0
                END AS "reset_flag"
           FROM "ordered"
        ), "grouped" AS (
         SELECT "numbered"."card_uid",
            "numbered"."room_id",
            "numbered"."event_time",
            "numbered"."prev_room",
            "numbered"."reset_flag",
            "sum"("numbered"."reset_flag") OVER (PARTITION BY "numbered"."card_uid" ORDER BY "numbered"."event_time") AS "session_group"
           FROM "numbered"
        )
 SELECT "card_uid",
    "room_id",
    "event_time",
        CASE
            WHEN (("row_number"() OVER (PARTITION BY "card_uid", "session_group" ORDER BY "event_time") % (2)::bigint) = 1) THEN 'ENTER'::"text"
            ELSE 'EXIT'::"text"
        END AS "inferred_action"
   FROM "grouped";


ALTER VIEW "public"."access_log_actions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."buildings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."buildings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."raspberry_devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "location" "text",
    "room_id" "uuid",
    "registered_by" "uuid",
    "last_seen" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."raspberry_devices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rfid_cards" (
    "uid" "text" NOT NULL,
    "person_name" "text",
    "student_code" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid"
);


ALTER TABLE "public"."rfid_cards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rooms" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "building_id" "uuid",
    "name" "text" NOT NULL,
    "type" "public"."room_type" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."rooms" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "email" character varying(255) NOT NULL,
    "name" character varying(255) NOT NULL,
    "is_admin" boolean DEFAULT false,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."users" OWNER TO "postgres";


ALTER TABLE ONLY "public"."access_events" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."access_events_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."access_blocks"
    ADD CONSTRAINT "access_blocks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."access_events"
    ADD CONSTRAINT "access_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."buildings"
    ADD CONSTRAINT "buildings_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."buildings"
    ADD CONSTRAINT "buildings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."raspberry_devices"
    ADD CONSTRAINT "raspberry_devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rfid_cards"
    ADD CONSTRAINT "rfid_cards_pkey" PRIMARY KEY ("uid");



ALTER TABLE ONLY "public"."rooms"
    ADD CONSTRAINT "rooms_building_id_name_key" UNIQUE ("building_id", "name");



ALTER TABLE ONLY "public"."rooms"
    ADD CONSTRAINT "rooms_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE INDEX "access_blocks_card_uid_room_id_idx" ON "public"."access_blocks" USING "btree" ("card_uid", "room_id");



CREATE INDEX "idx_rfid_cards_user_id" ON "public"."rfid_cards" USING "btree" ("user_id");



CREATE INDEX "idx_users_email" ON "public"."users" USING "btree" ("email");



CREATE INDEX "idx_users_is_admin" ON "public"."users" USING "btree" ("is_admin");



ALTER TABLE ONLY "public"."access_blocks"
    ADD CONSTRAINT "access_blocks_blocked_by_fkey" FOREIGN KEY ("blocked_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."access_blocks"
    ADD CONSTRAINT "access_blocks_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "public"."rooms"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."access_events"
    ADD CONSTRAINT "access_events_card_uid_fkey" FOREIGN KEY ("card_uid") REFERENCES "public"."rfid_cards"("uid") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."access_events"
    ADD CONSTRAINT "access_events_raspberry_id_fkey" FOREIGN KEY ("raspberry_id") REFERENCES "public"."raspberry_devices"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."access_events"
    ADD CONSTRAINT "access_events_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "public"."rooms"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."raspberry_devices"
    ADD CONSTRAINT "raspberry_devices_registered_by_fkey" FOREIGN KEY ("registered_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."raspberry_devices"
    ADD CONSTRAINT "raspberry_devices_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "public"."rooms"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."rfid_cards"
    ADD CONSTRAINT "rfid_cards_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."rooms"
    ADD CONSTRAINT "rooms_building_id_fkey" FOREIGN KEY ("building_id") REFERENCES "public"."buildings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Allow authenticated delete buildings" ON "public"."buildings" FOR DELETE USING (true);



CREATE POLICY "Allow authenticated delete rooms" ON "public"."rooms" FOR DELETE USING (true);



CREATE POLICY "Allow authenticated insert buildings" ON "public"."buildings" FOR INSERT WITH CHECK (true);



CREATE POLICY "Allow authenticated insert rooms" ON "public"."rooms" FOR INSERT WITH CHECK (true);



CREATE POLICY "Allow authenticated update buildings" ON "public"."buildings" FOR UPDATE USING (true) WITH CHECK (true);



CREATE POLICY "Allow authenticated update rooms" ON "public"."rooms" FOR UPDATE USING (true) WITH CHECK (true);



CREATE POLICY "Allow authenticated users to insert access_events" ON "public"."access_events" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Allow authenticated users to insert rfid_cards" ON "public"."rfid_cards" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Allow delete access_blocks" ON "public"."access_blocks" FOR DELETE USING (true);



CREATE POLICY "Allow insert access_blocks" ON "public"."access_blocks" FOR INSERT WITH CHECK (true);



CREATE POLICY "Allow insert access_events" ON "public"."access_events" FOR INSERT WITH CHECK (true);



CREATE POLICY "Allow insert rfid_cards" ON "public"."rfid_cards" FOR INSERT WITH CHECK (true);



CREATE POLICY "Allow public read access to access_blocks" ON "public"."access_blocks" FOR SELECT USING (true);



CREATE POLICY "Allow public read access to access_events" ON "public"."access_events" FOR SELECT USING (true);



CREATE POLICY "Allow public read access to buildings" ON "public"."buildings" FOR SELECT USING (true);



CREATE POLICY "Allow public read access to rfid_cards" ON "public"."rfid_cards" FOR SELECT USING (true);



CREATE POLICY "Allow public read access to rooms" ON "public"."rooms" FOR SELECT USING (true);



CREATE POLICY "Allow update access_blocks" ON "public"."access_blocks" FOR UPDATE USING (true) WITH CHECK (true);



CREATE POLICY "Allow update access_events" ON "public"."access_events" FOR UPDATE USING (true) WITH CHECK (true);



CREATE POLICY "Allow update rfid_cards" ON "public"."rfid_cards" FOR UPDATE USING (true) WITH CHECK (true);



CREATE POLICY "Solo staff puede bloquear" ON "public"."access_blocks" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Solo staff puede eliminar bloqueos" ON "public"."access_blocks" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "Todos pueden leer bloqueos" ON "public"."access_blocks" FOR SELECT USING (true);



ALTER TABLE "public"."access_blocks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."access_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "admin_read_all_users" ON "public"."users" FOR SELECT USING ("public"."is_user_admin"("auth"."uid"()));



CREATE POLICY "allow_public_read_access_events" ON "public"."access_events" FOR SELECT USING (true);



CREATE POLICY "allow_read_all_cards" ON "public"."rfid_cards" FOR SELECT USING (true);



CREATE POLICY "allow_signup_insert" ON "public"."users" FOR INSERT WITH CHECK (true);



ALTER TABLE "public"."buildings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."raspberry_devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "raspberry_inserts_own_events" ON "public"."access_events" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."raspberry_devices" "d"
  WHERE (("d"."id" = "access_events"."raspberry_id") AND ("d"."registered_by" = "auth"."uid"())))));



ALTER TABLE "public"."rfid_cards" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rooms" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users_can_select_own_raspberry" ON "public"."raspberry_devices" FOR SELECT USING (("registered_by" = "auth"."uid"()));



CREATE POLICY "users_delete_own" ON "public"."users" FOR DELETE USING (("auth"."uid"() = "id"));



CREATE POLICY "users_read_own" ON "public"."users" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "users_update_own" ON "public"."users" FOR UPDATE USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."access_blocks";






GRANT USAGE ON SCHEMA "pgmq_public" TO "anon";
GRANT USAGE ON SCHEMA "pgmq_public" TO "authenticated";
GRANT USAGE ON SCHEMA "pgmq_public" TO "service_role";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";
































































































































































































GRANT ALL ON FUNCTION "pgmq_public"."archive"("queue_name" "text", "message_id" bigint) TO "service_role";
GRANT ALL ON FUNCTION "pgmq_public"."archive"("queue_name" "text", "message_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "pgmq_public"."archive"("queue_name" "text", "message_id" bigint) TO "authenticated";



GRANT ALL ON FUNCTION "pgmq_public"."delete"("queue_name" "text", "message_id" bigint) TO "service_role";
GRANT ALL ON FUNCTION "pgmq_public"."delete"("queue_name" "text", "message_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "pgmq_public"."delete"("queue_name" "text", "message_id" bigint) TO "authenticated";



GRANT ALL ON FUNCTION "pgmq_public"."pop"("queue_name" "text") TO "service_role";
GRANT ALL ON FUNCTION "pgmq_public"."pop"("queue_name" "text") TO "anon";
GRANT ALL ON FUNCTION "pgmq_public"."pop"("queue_name" "text") TO "authenticated";



GRANT ALL ON FUNCTION "pgmq_public"."read"("queue_name" "text", "sleep_seconds" integer, "n" integer) TO "service_role";
GRANT ALL ON FUNCTION "pgmq_public"."read"("queue_name" "text", "sleep_seconds" integer, "n" integer) TO "anon";
GRANT ALL ON FUNCTION "pgmq_public"."read"("queue_name" "text", "sleep_seconds" integer, "n" integer) TO "authenticated";



GRANT ALL ON FUNCTION "pgmq_public"."send"("queue_name" "text", "message" "jsonb", "sleep_seconds" integer) TO "service_role";
GRANT ALL ON FUNCTION "pgmq_public"."send"("queue_name" "text", "message" "jsonb", "sleep_seconds" integer) TO "anon";
GRANT ALL ON FUNCTION "pgmq_public"."send"("queue_name" "text", "message" "jsonb", "sleep_seconds" integer) TO "authenticated";



GRANT ALL ON FUNCTION "pgmq_public"."send_batch"("queue_name" "text", "messages" "jsonb"[], "sleep_seconds" integer) TO "service_role";
GRANT ALL ON FUNCTION "pgmq_public"."send_batch"("queue_name" "text", "messages" "jsonb"[], "sleep_seconds" integer) TO "anon";
GRANT ALL ON FUNCTION "pgmq_public"."send_batch"("queue_name" "text", "messages" "jsonb"[], "sleep_seconds" integer) TO "authenticated";



GRANT ALL ON FUNCTION "public"."confirm_new_user_rpc"() TO "anon";
GRANT ALL ON FUNCTION "public"."confirm_new_user_rpc"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirm_new_user_rpc"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_user_admin"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_user_admin"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_user_admin"("user_id" "uuid") TO "service_role";



























GRANT ALL ON TABLE "public"."access_blocks" TO "anon";
GRANT ALL ON TABLE "public"."access_blocks" TO "authenticated";
GRANT ALL ON TABLE "public"."access_blocks" TO "service_role";



GRANT ALL ON TABLE "public"."access_events" TO "anon";
GRANT ALL ON TABLE "public"."access_events" TO "authenticated";
GRANT ALL ON TABLE "public"."access_events" TO "service_role";



GRANT ALL ON SEQUENCE "public"."access_events_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."access_events_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."access_events_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."access_log_actions" TO "anon";
GRANT ALL ON TABLE "public"."access_log_actions" TO "authenticated";
GRANT ALL ON TABLE "public"."access_log_actions" TO "service_role";



GRANT ALL ON TABLE "public"."buildings" TO "anon";
GRANT ALL ON TABLE "public"."buildings" TO "authenticated";
GRANT ALL ON TABLE "public"."buildings" TO "service_role";



GRANT ALL ON TABLE "public"."raspberry_devices" TO "anon";
GRANT ALL ON TABLE "public"."raspberry_devices" TO "authenticated";
GRANT ALL ON TABLE "public"."raspberry_devices" TO "service_role";



GRANT ALL ON TABLE "public"."rfid_cards" TO "anon";
GRANT ALL ON TABLE "public"."rfid_cards" TO "authenticated";
GRANT ALL ON TABLE "public"."rfid_cards" TO "service_role";



GRANT ALL ON TABLE "public"."rooms" TO "anon";
GRANT ALL ON TABLE "public"."rooms" TO "authenticated";
GRANT ALL ON TABLE "public"."rooms" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































