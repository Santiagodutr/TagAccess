-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.access_blocks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  card_uid text NOT NULL,
  room_id uuid NOT NULL,
  reason text,
  blocked_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT access_blocks_pkey PRIMARY KEY (id),
  CONSTRAINT access_blocks_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.rooms(id),
  CONSTRAINT access_blocks_blocked_by_fkey FOREIGN KEY (blocked_by) REFERENCES auth.users(id)
);
CREATE TABLE public.access_events (
  id bigint NOT NULL DEFAULT nextval('access_events_id_seq'::regclass),
  card_uid text,
  raspberry_id uuid,
  room_id uuid,
  event_time timestamp with time zone DEFAULT now(),
  authorized boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT access_events_pkey PRIMARY KEY (id),
  CONSTRAINT access_events_card_uid_fkey FOREIGN KEY (card_uid) REFERENCES public.rfid_cards(uid),
  CONSTRAINT access_events_raspberry_id_fkey FOREIGN KEY (raspberry_id) REFERENCES public.raspberry_devices(id),
  CONSTRAINT access_events_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.rooms(id)
);
CREATE TABLE public.buildings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT buildings_pkey PRIMARY KEY (id)
);
CREATE TABLE public.raspberry_devices (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  location text,
  room_id uuid,
  registered_by uuid,
  last_seen timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT raspberry_devices_pkey PRIMARY KEY (id),
  CONSTRAINT raspberry_devices_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.rooms(id),
  CONSTRAINT raspberry_devices_registered_by_fkey FOREIGN KEY (registered_by) REFERENCES auth.users(id)
);
CREATE TABLE public.rfid_cards (
  uid text NOT NULL,
  person_name text,
  student_code text,
  created_at timestamp with time zone DEFAULT now(),
  user_id uuid,
  CONSTRAINT rfid_cards_pkey PRIMARY KEY (uid),
  CONSTRAINT rfid_cards_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.rooms (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  building_id uuid,
  name text NOT NULL,
  type USER-DEFINED NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT rooms_pkey PRIMARY KEY (id),
  CONSTRAINT rooms_building_id_fkey FOREIGN KEY (building_id) REFERENCES public.buildings(id)
);
CREATE TABLE public.users (
  id uuid NOT NULL,
  email character varying NOT NULL UNIQUE,
  name character varying NOT NULL,
  is_admin boolean DEFAULT false,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT users_pkey PRIMARY KEY (id),
  CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);