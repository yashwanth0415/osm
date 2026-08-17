-- RENFLIX CLEAN MASTER DATABASE RESET
-- IMPORTANT: This resets RENFLIX application data in public schema.
-- It does NOT delete auth.users.
-- Run ONLY against the RENFLIX development/reset database.
-- After this, remove/disable client-side schema migration calls in setupDb.ts.

BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. REMOVE OLD RENFLIX OBJECTS
-- ============================================================

DROP VIEW IF EXISTS public.admin_org_summary CASCADE;
DROP VIEW IF EXISTS public.admin_system_overview CASCADE;

DROP TABLE IF EXISTS
  public.admin_audit_logs,
  public.admin_settings,
  public.system_metrics,
  public.notifications,
  public.messages,
  public.conversation_members,
  public.conversations,
  public.community_announcements,
  public.maintenance_requests,
  public.payments,
  public.leases,
  public.tenants,
  public.units,
  public.properties,
  public.profiles,
  public.organizations
CASCADE;

DROP SEQUENCE IF EXISTS
  public.property_display_id_seq,
  public.tenant_display_id_seq,
  public.tenant_display_id_seq_1
CASCADE;

DROP FUNCTION IF EXISTS public.generate_property_display_id() CASCADE;
DROP FUNCTION IF EXISTS public.generate_tenant_display_id() CASCADE;
DROP FUNCTION IF EXISTS public.create_notification(uuid, uuid, text, text, text, text, uuid, jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.notify_property_created() CASCADE;
DROP FUNCTION IF EXISTS public.notify_tenant_added() CASCADE;
DROP FUNCTION IF EXISTS public.notify_payment_received() CASCADE;
DROP FUNCTION IF EXISTS public.notify_maintenance_created() CASCADE;
DROP FUNCTION IF EXISTS public.notify_lease_created() CASCADE;
DROP FUNCTION IF EXISTS public.mark_notifications_read(uuid[]) CASCADE;
DROP FUNCTION IF EXISTS public.mark_all_notifications_read() CASCADE;
DROP FUNCTION IF EXISTS public.get_user_org_id() CASCADE;
DROP FUNCTION IF EXISTS public.is_admin() CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.log_admin_action(text, text, uuid, jsonb, jsonb) CASCADE;

-- ============================================================
-- 2. CORE TABLES
-- ============================================================

CREATE TABLE public.organizations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_organizations_owner ON public.organizations(owner_id);

CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  phone TEXT,
  avatar_url TEXT,
  role TEXT NOT NULL DEFAULT 'OWNER'
    CHECK (role IN (
      'OWNER',
      'PROPERTY_MANAGER',
      'TENANT',
      'HOSTEL_MANAGER',
      'TECHNICIAN',
      'COMMUNITY_MANAGER',
      'ADMIN'
    )),
  organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_profiles_org ON public.profiles(organization_id);
CREATE INDEX idx_profiles_role ON public.profiles(role);

CREATE TABLE public.properties (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  portfolio_id UUID,
  name TEXT NOT NULL,
  property_type TEXT NOT NULL
    CHECK (property_type IN (
      'HOUSE','APARTMENT','PG','HOSTEL','COLIVING','VILLA',
      'GATED_COMMUNITY','COMMERCIAL','SHOP','OFFICE',
      'WAREHOUSE','PLOT','LAND','MIXED'
    )),
  description TEXT,
  address TEXT NOT NULL,
  city TEXT NOT NULL,
  state TEXT NOT NULL,
  country TEXT NOT NULL DEFAULT 'India',
  postal_code TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  image_url TEXT,
  status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE','INACTIVE','ARCHIVED')),
  property_display_id TEXT UNIQUE,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_properties_org ON public.properties(organization_id);
CREATE INDEX idx_properties_status ON public.properties(status);
CREATE INDEX idx_properties_display_id ON public.properties(property_display_id);

CREATE TABLE public.units (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  building_id UUID,
  floor_id UUID,
  unit_number TEXT NOT NULL,
  unit_type TEXT,
  name TEXT,
  area NUMERIC,
  status TEXT NOT NULL DEFAULT 'AVAILABLE'
    CHECK (status IN ('AVAILABLE','OCCUPIED','MAINTENANCE','RESERVED','BLOCKED')),
  monthly_rent NUMERIC NOT NULL DEFAULT 0,
  security_deposit NUMERIC,
  metadata JSONB,
  property_display_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_units_org ON public.units(organization_id);
CREATE INDEX idx_units_property ON public.units(property_id);
CREATE INDEX idx_units_status ON public.units(status);
CREATE INDEX idx_units_property_display_id ON public.units(property_display_id);

CREATE TABLE public.tenants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL,
  email TEXT,
  phone TEXT NOT NULL,
  emergency_contact_name TEXT,
  emergency_contact_phone TEXT,
  status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE','INACTIVE','FORMER')),
  unit_id UUID REFERENCES public.units(id) ON DELETE SET NULL,
  move_in_date DATE,
  move_out_date DATE,
  tenant_display_id TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_tenants_org ON public.tenants(organization_id);
CREATE INDEX idx_tenants_unit ON public.tenants(unit_id);
CREATE INDEX idx_tenants_display_id ON public.tenants(tenant_display_id);

CREATE TABLE public.leases (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  unit_id UUID NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  monthly_rent NUMERIC NOT NULL,
  security_deposit NUMERIC NOT NULL DEFAULT 0,
  notice_period_days INTEGER NOT NULL DEFAULT 30,
  late_fee_percentage NUMERIC NOT NULL DEFAULT 2,
  payment_day INTEGER NOT NULL DEFAULT 5
    CHECK (payment_day BETWEEN 1 AND 31),
  status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('DRAFT','ACTIVE','EXPIRED','TERMINATED','RENEWED')),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_leases_org ON public.leases(organization_id);
CREATE INDEX idx_leases_property ON public.leases(property_id);
CREATE INDEX idx_leases_unit ON public.leases(unit_id);
CREATE INDEX idx_leases_tenant ON public.leases(tenant_id);
CREATE INDEX idx_leases_status ON public.leases(status);

CREATE TABLE public.payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  lease_id UUID REFERENCES public.leases(id) ON DELETE SET NULL,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  unit_id UUID REFERENCES public.units(id) ON DELETE SET NULL,
  property_id UUID REFERENCES public.properties(id) ON DELETE SET NULL,
  amount NUMERIC NOT NULL,
  due_date DATE,
  paid_date DATE,
  payment_method TEXT
    CHECK (payment_method IN ('UPI','CARD','BANK_TRANSFER','CASH','CHEQUE','OTHER')),
  reference_number TEXT,
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING','PAID','PARTIALLY_PAID','OVERDUE','WAIVED','CANCELLED')),
  receipt_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_payments_org ON public.payments(organization_id);
CREATE INDEX idx_payments_tenant ON public.payments(tenant_id);
CREATE INDEX idx_payments_property ON public.payments(property_id);
CREATE INDEX idx_payments_lease ON public.payments(lease_id);
CREATE INDEX idx_payments_status ON public.payments(status);

CREATE TABLE public.maintenance_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  property_id UUID NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  unit_id UUID REFERENCES public.units(id) ON DELETE SET NULL,
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  category TEXT NOT NULL,
  priority TEXT NOT NULL DEFAULT 'MEDIUM'
    CHECK (priority IN ('LOW','MEDIUM','HIGH','URGENT')),
  status TEXT NOT NULL DEFAULT 'SUBMITTED'
    CHECK (status IN (
      'SUBMITTED','REVIEWED','ASSIGNED','ACCEPTED','SCHEDULED',
      'IN_PROGRESS','WAITING_FOR_PARTS','COMPLETED','VERIFIED','CLOSED'
    )),
  assigned_to UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  estimated_cost NUMERIC,
  actual_cost NUMERIC,
  scheduled_date DATE,
  completed_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_maintenance_org ON public.maintenance_requests(organization_id);
CREATE INDEX idx_maintenance_property ON public.maintenance_requests(property_id);
CREATE INDEX idx_maintenance_unit ON public.maintenance_requests(unit_id);
CREATE INDEX idx_maintenance_tenant ON public.maintenance_requests(tenant_id);
CREATE INDEX idx_maintenance_status ON public.maintenance_requests(status);
CREATE INDEX idx_maintenance_priority ON public.maintenance_requests(priority);

CREATE TABLE public.conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  title TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_conversations_org ON public.conversations(organization_id);

CREATE TABLE public.conversation_members (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  UNIQUE(conversation_id, user_id)
);

CREATE INDEX idx_conversation_members_user ON public.conversation_members(user_id);

CREATE TABLE public.messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_messages_conv ON public.messages(conversation_id);
CREATE INDEX idx_messages_sender ON public.messages(sender_id);

CREATE TABLE public.community_announcements (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  priority TEXT NOT NULL DEFAULT 'NORMAL'
    CHECK (priority IN ('NORMAL','IMPORTANT','URGENT')),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_announcements_org ON public.community_announcements(organization_id);

CREATE TABLE public.notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  read BOOLEAN NOT NULL DEFAULT false,
  entity_type TEXT,
  entity_id UUID,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_user ON public.notifications(user_id);
CREATE INDEX idx_notifications_org ON public.notifications(organization_id);
CREATE INDEX idx_notifications_read ON public.notifications(read);
CREATE INDEX idx_notifications_created ON public.notifications(created_at DESC);
CREATE INDEX idx_notifications_entity ON public.notifications(entity_type, entity_id);

-- ============================================================
-- 3. ADMIN TABLES
-- ============================================================

CREATE TABLE public.admin_audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  admin_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  table_name TEXT NOT NULL,
  record_id UUID,
  old_data JSONB,
  new_data JSONB,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_admin_audit_admin ON public.admin_audit_logs(admin_user_id);
CREATE INDEX idx_admin_audit_table ON public.admin_audit_logs(table_name);
CREATE INDEX idx_admin_audit_created ON public.admin_audit_logs(created_at DESC);
CREATE INDEX idx_admin_audit_record ON public.admin_audit_logs(record_id);

CREATE TABLE public.admin_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  description TEXT,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.admin_settings (key, value, description) VALUES
  ('maintenance_mode', 'false', 'Enable maintenance mode for the platform'),
  ('max_properties_per_org', '99', 'Maximum properties per organization'),
  ('max_tenants_per_org', '99', 'Maximum tenants per organization'),
  ('default_property_status', '"ACTIVE"', 'Default status for new properties'),
  ('default_unit_status', '"AVAILABLE"', 'Default status for new units'),
  ('default_tenant_status', '"ACTIVE"', 'Default status for new tenants'),
  ('enable_notifications', 'true', 'Enable system notifications'),
  ('auto_archive_days', '365', 'Days after which inactive records are archived')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE public.system_metrics (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  metric_name TEXT NOT NULL,
  metric_value NUMERIC NOT NULL,
  metric_unit TEXT,
  tags JSONB,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_system_metrics_name ON public.system_metrics(metric_name);
CREATE INDEX idx_system_metrics_recorded ON public.system_metrics(recorded_at DESC);

-- ============================================================
-- 4. DISPLAY IDS
-- ============================================================

CREATE SEQUENCE public.property_display_id_seq START WITH 1;
CREATE SEQUENCE public.tenant_display_id_seq START WITH 1;

CREATE OR REPLACE FUNCTION public.generate_property_display_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  next_seq INT;
BEGIN
  next_seq := nextval('public.property_display_id_seq');
  IF next_seq > 99 THEN
    RAISE EXCEPTION 'Maximum of 99 property display IDs reached';
  END IF;

  NEW.property_display_id := '164' || LPAD(next_seq::TEXT, 2, '0');
  RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_property_display_id
BEFORE INSERT ON public.properties
FOR EACH ROW
EXECUTE FUNCTION public.generate_property_display_id();

CREATE OR REPLACE FUNCTION public.generate_tenant_display_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  next_seq INT;
BEGIN
  next_seq := nextval('public.tenant_display_id_seq');
  IF next_seq > 99 THEN
    RAISE EXCEPTION 'Maximum of 99 tenant display IDs reached';
  END IF;

  NEW.tenant_display_id := '164' || LPAD(next_seq::TEXT, 2, '0');
  RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_tenant_display_id
BEFORE INSERT ON public.tenants
FOR EACH ROW
EXECUTE FUNCTION public.generate_tenant_display_id();

-- Keep units' property display ID synchronized.
CREATE OR REPLACE FUNCTION public.sync_unit_property_display_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  SELECT property_display_id
    INTO NEW.property_display_id
  FROM public.properties
  WHERE id = NEW.property_id;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_sync_unit_property_display_id
BEFORE INSERT OR UPDATE OF property_id ON public.units
FOR EACH ROW
EXECUTE FUNCTION public.sync_unit_property_display_id();

-- ============================================================
-- 5. SECURITY HELPERS
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_user_org_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT organization_id
  FROM public.profiles
  WHERE id = auth.uid()
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND role = 'ADMIN'
  );
$$;

-- ============================================================
-- 6. RLS
-- ============================================================

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.units ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.community_announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_metrics ENABLE ROW LEVEL SECURITY;

-- Core policies
CREATE POLICY org_owner_all
ON public.organizations
FOR ALL
TO authenticated
USING (owner_id = auth.uid() OR public.is_admin())
WITH CHECK (owner_id = auth.uid() OR public.is_admin());

CREATE POLICY profiles_self
ON public.profiles
FOR ALL
TO authenticated
USING (id = auth.uid() OR public.is_admin())
WITH CHECK (id = auth.uid() OR public.is_admin());

CREATE POLICY profiles_org_read
ON public.profiles
FOR SELECT
TO authenticated
USING (
  organization_id = public.get_user_org_id()
  OR id = auth.uid()
  OR public.is_admin()
);

CREATE POLICY properties_org
ON public.properties
FOR ALL
TO authenticated
USING (organization_id = public.get_user_org_id() OR public.is_admin())
WITH CHECK (organization_id = public.get_user_org_id() OR public.is_admin());

CREATE POLICY units_org
ON public.units
FOR ALL
TO authenticated
USING (
  organization_id = public.get_user_org_id()
  OR public.is_admin()
)
WITH CHECK (
  organization_id = public.get_user_org_id()
  OR public.is_admin()
);

CREATE POLICY tenants_org
ON public.tenants
FOR ALL
TO authenticated
USING (organization_id = public.get_user_org_id() OR public.is_admin())
WITH CHECK (organization_id = public.get_user_org_id() OR public.is_admin());

CREATE POLICY leases_org
ON public.leases
FOR ALL
TO authenticated
USING (organization_id = public.get_user_org_id() OR public.is_admin())
WITH CHECK (organization_id = public.get_user_org_id() OR public.is_admin());

CREATE POLICY payments_org
ON public.payments
FOR ALL
TO authenticated
USING (organization_id = public.get_user_org_id() OR public.is_admin())
WITH CHECK (organization_id = public.get_user_org_id() OR public.is_admin());

CREATE POLICY maintenance_org
ON public.maintenance_requests
FOR ALL
TO authenticated
USING (organization_id = public.get_user_org_id() OR public.is_admin())
WITH CHECK (organization_id = public.get_user_org_id() OR public.is_admin());

CREATE POLICY conversations_org
ON public.conversations
FOR ALL
TO authenticated
USING (organization_id = public.get_user_org_id() OR public.is_admin())
WITH CHECK (organization_id = public.get_user_org_id() OR public.is_admin());

CREATE POLICY conversation_members_org
ON public.conversation_members
FOR ALL
TO authenticated
USING (
  conversation_id IN (
    SELECT id
    FROM public.conversations
    WHERE organization_id = public.get_user_org_id()
  )
  OR public.is_admin()
)
WITH CHECK (
  conversation_id IN (
    SELECT id
    FROM public.conversations
    WHERE organization_id = public.get_user_org_id()
  )
  OR public.is_admin()
);

CREATE POLICY messages_org
ON public.messages
FOR ALL
TO authenticated
USING (
  conversation_id IN (
    SELECT id
    FROM public.conversations
    WHERE organization_id = public.get_user_org_id()
  )
  OR public.is_admin()
)
WITH CHECK (
  conversation_id IN (
    SELECT id
    FROM public.conversations
    WHERE organization_id = public.get_user_org_id()
  )
  OR public.is_admin()
);

CREATE POLICY announcements_org
ON public.community_announcements
FOR ALL
TO authenticated
USING (organization_id = public.get_user_org_id() OR public.is_admin())
WITH CHECK (organization_id = public.get_user_org_id() OR public.is_admin());

CREATE POLICY notifications_self
ON public.notifications
FOR ALL
TO authenticated
USING (user_id = auth.uid() OR public.is_admin())
WITH CHECK (user_id = auth.uid() OR public.is_admin());

-- Admin policies
CREATE POLICY admin_audit_self
ON public.admin_audit_logs
FOR ALL
TO authenticated
USING (admin_user_id = auth.uid() OR public.is_admin())
WITH CHECK (admin_user_id = auth.uid() OR public.is_admin());

CREATE POLICY admin_settings_read
ON public.admin_settings
FOR SELECT
TO authenticated
USING (public.is_admin());

CREATE POLICY admin_settings_write
ON public.admin_settings
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

CREATE POLICY system_metrics_admin
ON public.system_metrics
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- ============================================================
-- 7. NOTIFICATION SYSTEM
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_notification(
  p_user_id UUID,
  p_organization_id UUID,
  p_type TEXT,
  p_title TEXT,
  p_message TEXT,
  p_entity_type TEXT DEFAULT NULL,
  p_entity_id UUID DEFAULT NULL,
  p_metadata JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL OR p_organization_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.notifications
    (user_id, organization_id, type, title, message, entity_type, entity_id, metadata)
  VALUES
    (p_user_id, p_organization_id, p_type, p_title, p_message,
     p_entity_type, p_entity_id, p_metadata);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_notification_recipient(p_organization_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    auth.uid(),
    (SELECT owner_id FROM public.organizations WHERE id = p_organization_id LIMIT 1)
  );
$$;

CREATE OR REPLACE FUNCTION public.notify_property_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE recipient UUID;
BEGIN
  recipient := public.get_notification_recipient(NEW.organization_id);

  PERFORM public.create_notification(
    recipient,
    NEW.organization_id,
    'property_created',
    'New Property Added',
    'Property "' || NEW.name || '" has been created.',
    'property',
    NEW.id,
    jsonb_build_object(
      'property_name', NEW.name,
      'property_type', NEW.property_type
    )
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_property_created
AFTER INSERT ON public.properties
FOR EACH ROW
EXECUTE FUNCTION public.notify_property_created();

CREATE OR REPLACE FUNCTION public.notify_tenant_added()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  recipient UUID;
  property_name TEXT;
BEGIN
  recipient := public.get_notification_recipient(NEW.organization_id);

  SELECT p.name
  INTO property_name
  FROM public.units u
  JOIN public.properties p ON p.id = u.property_id
  WHERE u.id = NEW.unit_id;

  PERFORM public.create_notification(
    recipient,
    NEW.organization_id,
    'tenant_added',
    'New Tenant Added',
    'Tenant "' || NEW.full_name || '" has been added' ||
      CASE WHEN property_name IS NOT NULL THEN ' to ' || property_name ELSE '' END || '.',
    'tenant',
    NEW.id,
    jsonb_build_object(
      'tenant_name', NEW.full_name,
      'property_name', property_name,
      'unit_id', NEW.unit_id
    )
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_tenant_added
AFTER INSERT ON public.tenants
FOR EACH ROW
EXECUTE FUNCTION public.notify_tenant_added();

CREATE OR REPLACE FUNCTION public.notify_payment_received()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE recipient UUID;
BEGIN
  recipient := public.get_notification_recipient(NEW.organization_id);

  IF NEW.status = 'PAID'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN

    PERFORM public.create_notification(
      recipient,
      NEW.organization_id,
      'payment_received',
      'Payment Received',
      'Payment of ' || NEW.amount || ' received from tenant.',
      'payment',
      NEW.id,
      jsonb_build_object(
        'amount', NEW.amount,
        'tenant_id', NEW.tenant_id,
        'property_id', NEW.property_id
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_payment_received
AFTER INSERT OR UPDATE ON public.payments
FOR EACH ROW
EXECUTE FUNCTION public.notify_payment_received();

CREATE OR REPLACE FUNCTION public.notify_maintenance_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE recipient UUID;
BEGIN
  recipient := public.get_notification_recipient(NEW.organization_id);

  PERFORM public.create_notification(
    recipient,
    NEW.organization_id,
    'maintenance_created',
    'New Maintenance Request',
    'Maintenance request: "' || NEW.title || '" (' || NEW.priority || ' priority).',
    'maintenance',
    NEW.id,
    jsonb_build_object(
      'title', NEW.title,
      'priority', NEW.priority,
      'property_id', NEW.property_id
    )
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_maintenance_created
AFTER INSERT ON public.maintenance_requests
FOR EACH ROW
EXECUTE FUNCTION public.notify_maintenance_created();

CREATE OR REPLACE FUNCTION public.notify_lease_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE recipient UUID;
BEGIN
  recipient := public.get_notification_recipient(NEW.organization_id);

  PERFORM public.create_notification(
    recipient,
    NEW.organization_id,
    'lease_created',
    'New Lease Created',
    'Lease created for tenant on unit.',
    'lease',
    NEW.id,
    jsonb_build_object(
      'tenant_id', NEW.tenant_id,
      'unit_id', NEW.unit_id,
      'monthly_rent', NEW.monthly_rent
    )
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_lease_created
AFTER INSERT ON public.leases
FOR EACH ROW
EXECUTE FUNCTION public.notify_lease_created();

CREATE OR REPLACE FUNCTION public.mark_notifications_read(p_notification_ids UUID[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.notifications
  SET read = true
  WHERE id = ANY(p_notification_ids)
    AND (user_id = auth.uid() OR public.is_admin());
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.notifications
  SET read = true
  WHERE (user_id = auth.uid() OR public.is_admin())
    AND read = false;
END;
$$;

-- ============================================================
-- 8. ADMIN FUNCTIONS + VIEWS
-- ============================================================

CREATE OR REPLACE FUNCTION public.log_admin_action(
  p_action TEXT,
  p_table_name TEXT,
  p_record_id UUID DEFAULT NULL,
  p_old_data JSONB DEFAULT NULL,
  p_new_data JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  INSERT INTO public.admin_audit_logs
    (admin_user_id, action, table_name, record_id, old_data, new_data)
  VALUES
    (auth.uid(), p_action, p_table_name, p_record_id, p_old_data, p_new_data);
END;
$$;

CREATE OR REPLACE VIEW public.admin_org_summary AS
SELECT
  o.id AS organization_id,
  o.name AS organization_name,
  o.created_at AS org_created_at,
  COUNT(DISTINCT p.id) AS total_properties,
  COUNT(DISTINCT u.id) AS total_units,
  COUNT(DISTINCT t.id) AS total_tenants,
  COUNT(DISTINCT l.id) AS total_leases,
  COUNT(DISTINCT pay.id) AS total_payments,
  COALESCE(SUM(pay.amount) FILTER (WHERE pay.status = 'PAID'), 0) AS total_revenue
FROM public.organizations o
LEFT JOIN public.properties p ON p.organization_id = o.id
LEFT JOIN public.units u ON u.property_id = p.id
LEFT JOIN public.tenants t ON t.organization_id = o.id
LEFT JOIN public.leases l ON l.organization_id = o.id
LEFT JOIN public.payments pay ON pay.organization_id = o.id
GROUP BY o.id, o.name, o.created_at;

CREATE OR REPLACE VIEW public.admin_system_overview AS
SELECT
  (SELECT COUNT(*) FROM public.organizations) AS total_organizations,
  (SELECT COUNT(*) FROM public.profiles) AS total_users,
  (SELECT COUNT(*) FROM public.properties) AS total_properties,
  (SELECT COUNT(*) FROM public.units) AS total_units,
  (SELECT COUNT(*) FROM public.tenants) AS total_tenants,
  (SELECT COUNT(*) FROM public.leases WHERE status = 'ACTIVE') AS active_leases,
  (SELECT COUNT(*) FROM public.payments WHERE status = 'PAID') AS completed_payments,
  (SELECT COUNT(*) FROM public.maintenance_requests
    WHERE status IN (
      'SUBMITTED','REVIEWED','ASSIGNED','ACCEPTED','SCHEDULED','IN_PROGRESS'
    )
  ) AS open_maintenance,
  (SELECT COALESCE(SUM(amount), 0)
    FROM public.payments WHERE status = 'PAID'
  ) AS total_collected,
  (SELECT COALESCE(SUM(amount), 0)
    FROM public.payments WHERE status = 'OVERDUE'
  ) AS total_overdue;

-- ============================================================
-- 9. IMPORTANT AUTH DESIGN
-- ============================================================
-- DO NOT create an auth.users -> profiles trigger here.
--
-- RENFLIX onboarding already inserts the profile after auth signup.
-- The previous trigger caused duplicate profile inserts during onboarding.
--
-- This intentionally leaves auth.users alone.
-- Supabase Auth remains the source of truth for authentication.

-- ============================================================
-- 10. PERMISSIONS
-- ============================================================
-- Restore schema usage for normal Supabase API roles.
-- Do NOT grant CREATE or ALL to anon/authenticated.

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- anon should not receive application-table access.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;

-- Service role remains privileged; these grants do not expose it to the browser.
GRANT USAGE ON SCHEMA public TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE, SELECT ON SEQUENCES TO authenticated;

-- ============================================================
-- 11. REALTIME — ADD ONLY IF NOT ALREADY PRESENT
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'maintenance_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.maintenance_requests;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'community_announcements'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.community_announcements;
  END IF;
END $$;

COMMIT;

-- ============================================================
-- 12. VERIFICATION
-- ============================================================

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;
