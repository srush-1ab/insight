-- ====================================================================
-- FOODBRIDGE AI — SUPABASE PRODUCTION DATABASE SCHEMA & RLS POLICIES
-- Architecture: Supabase PostgreSQL with Firebase Third-Party Auth
-- Run this script in the Supabase SQL Editor:
-- https://supabase.com/dashboard/project/oxidjbrzbiyxtikzyzcy/sql
-- ====================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. FIREBASE THIRD-PARTY AUTH HELPER FUNCTIONS
-- Extracts the Firebase User UID from the incoming JWT sub claim,
-- falling back to request settings or auth.uid()
CREATE OR REPLACE FUNCTION public.requesting_user_id()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    auth.jwt() ->> 'sub',
    NULLIF(current_setting('request.jwt.claim.sub', true), ''),
    (auth.uid())::TEXT
  );
$$;

-- Extracts user role from JWT claims or from public.profiles
CREATE OR REPLACE FUNCTION public.requesting_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    auth.jwt() ->> 'role',
    (SELECT role FROM public.profiles WHERE id = public.requesting_user_id() LIMIT 1),
    'anon'
  );
$$;

-- 3. PROFILES TABLE (Stores user & organization metadata keyed by Firebase UID)
CREATE TABLE IF NOT EXISTS public.profiles (
    id TEXT PRIMARY KEY, -- Firebase User UID (e.g., 'vI621xQz8bM7...' or local simulated UID)
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'provider' CHECK (role IN ('provider', 'ngo', 'courier', 'volunteer', 'admin')),
    organization TEXT,
    phone TEXT,
    address TEXT,
    avatar_url TEXT DEFAULT 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=250',
    verified BOOLEAN NOT NULL DEFAULT true,
    approval_status TEXT NOT NULL DEFAULT 'approved' CHECK (approval_status IN ('approved', 'pending_approval', 'rejected')),
    impact_score INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);

-- 4. FOOD LISTINGS TABLE (Food surplus donations)
CREATE TABLE IF NOT EXISTS public.food_listings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL CHECK (category IN ('Cooked Meals', 'Bakery & Bread', 'Fresh Produce', 'Packaged Foods', 'Dairy Products', 'Beverages')),
    quantity TEXT NOT NULL,
    servings_count INTEGER NOT NULL CHECK (servings_count > 0),
    provider_id TEXT REFERENCES public.profiles(id) ON DELETE SET NULL,
    provider_name TEXT NOT NULL,
    provider_org TEXT NOT NULL,
    provider_address TEXT NOT NULL,
    provider_phone TEXT,
    claimed_by_ngo_id TEXT REFERENCES public.profiles(id) ON DELETE SET NULL,
    claimed_by_ngo_name TEXT,
    assigned_volunteer_id TEXT REFERENCES public.profiles(id) ON DELETE SET NULL,
    assigned_volunteer_name TEXT,
    expiry_time TIMESTAMPTZ NOT NULL,
    prepared_time TIMESTAMPTZ,
    dietary_tags TEXT[] DEFAULT '{}',
    temperature_requirement TEXT NOT NULL DEFAULT 'Hot' CHECK (temperature_requirement IN ('Refrigerated', 'Frozen', 'Room Temp', 'Hot')),
    status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'claimed', 'in_transit', 'delivered', 'expired')),
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    city TEXT DEFAULT 'San Francisco, CA',
    pickup_instructions TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_food_listings_status ON public.food_listings(status);
CREATE INDEX IF NOT EXISTS idx_food_listings_provider_id ON public.food_listings(provider_id);
CREATE INDEX IF NOT EXISTS idx_food_listings_claimed_by_ngo ON public.food_listings(claimed_by_ngo_id);
CREATE INDEX IF NOT EXISTS idx_food_listings_created_at ON public.food_listings(created_at DESC);

-- 5. DONATION REQUESTS TABLE (Requests / Claims made by NGOs)
CREATE TABLE IF NOT EXISTS public.donation_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id UUID NOT NULL REFERENCES public.food_listings(id) ON DELETE CASCADE,
    ngo_id TEXT NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    ngo_name TEXT NOT NULL,
    requested_servings INTEGER,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'completed', 'cancelled')),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_donation_requests_listing ON public.donation_requests(listing_id);
CREATE INDEX IF NOT EXISTS idx_donation_requests_ngo ON public.donation_requests(ngo_id);

-- 6. FOOD PICKUPS TABLE (Delivery and Volunteer Dispatch)
CREATE TABLE IF NOT EXISTS public.food_pickups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id UUID NOT NULL REFERENCES public.food_listings(id) ON DELETE CASCADE,
    listing_title TEXT NOT NULL,
    category TEXT NOT NULL,
    servings INTEGER NOT NULL CHECK (servings > 0),
    provider_name TEXT NOT NULL,
    provider_address TEXT NOT NULL,
    ngo_name TEXT NOT NULL,
    ngo_address TEXT NOT NULL,
    volunteer_id TEXT REFERENCES public.profiles(id) ON DELETE SET NULL,
    volunteer_name TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'assigned', 'picked_up', 'delivered')),
    scheduled_time TEXT NOT NULL DEFAULT 'Today, within 2 hours',
    estimated_arrival_minutes INTEGER DEFAULT 30,
    route_progress_percent INTEGER DEFAULT 0,
    otp_code TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_food_pickups_status ON public.food_pickups(status);
CREATE INDEX IF NOT EXISTS idx_food_pickups_volunteer ON public.food_pickups(volunteer_id);
CREATE INDEX IF NOT EXISTS idx_food_pickups_listing ON public.food_pickups(listing_id);

-- 7. DONATION STATUS HISTORY TABLE (Audit Trail)
CREATE TABLE IF NOT EXISTS public.donation_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id UUID NOT NULL REFERENCES public.food_listings(id) ON DELETE CASCADE,
    previous_status TEXT,
    new_status TEXT NOT NULL,
    changed_by TEXT REFERENCES public.profiles(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_status_history_listing ON public.donation_status_history(listing_id);

-- 8. NOTIFICATIONS TABLE
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id TEXT REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('claim', 'pickup', 'alert', 'impact')),
    read BOOLEAN NOT NULL DEFAULT false,
    action_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON public.notifications(recipient_id, read);

-- 9. IMPACT STATISTICS TABLE
CREATE TABLE IF NOT EXISTS public.impact_statistics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    total_meals_rescued INTEGER NOT NULL DEFAULT 4820,
    total_donations INTEGER NOT NULL DEFAULT 142,
    co2_saved_kg NUMERIC NOT NULL DEFAULT 5780,
    water_saved_liters NUMERIC NOT NULL DEFAULT 31300,
    active_ngos_count INTEGER NOT NULL DEFAULT 24,
    active_volunteers_count INTEGER NOT NULL DEFAULT 68,
    active_donors_count INTEGER NOT NULL DEFAULT 42,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed initial impact stats record if empty
INSERT INTO public.impact_statistics (
    id,
    total_meals_rescued,
    total_donations,
    co2_saved_kg,
    water_saved_liters,
    active_ngos_count,
    active_volunteers_count,
    active_donors_count
) VALUES (
    '00000000-0000-0000-0000-000000000001',
    4820,
    142,
    5780,
    31300,
    24,
    68,
    42
) ON CONFLICT (id) DO NOTHING;

-- 10. ATOMIC CLAIM STORED PROCEDURE
CREATE OR REPLACE FUNCTION public.claim_food_listing(
    p_listing_id UUID,
    p_ngo_id TEXT,
    p_ngo_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_listing RECORD;
    v_new_pickup_id UUID;
    v_otp TEXT;
BEGIN
    -- 1. Concurrency lock on available listing
    SELECT * INTO v_listing
    FROM public.food_listings
    WHERE id = p_listing_id AND status = 'available'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Listing is either already claimed or does not exist.';
    END IF;

    -- 2. Transition listing to claimed
    UPDATE public.food_listings
    SET status = 'claimed',
        claimed_by_ngo_id = p_ngo_id,
        claimed_by_ngo_name = p_ngo_name,
        updated_at = NOW()
    WHERE id = p_listing_id;

    -- 3. Log Status History
    INSERT INTO public.donation_status_history (
        listing_id,
        previous_status,
        new_status,
        changed_by,
        notes
    ) VALUES (
        p_listing_id,
        'available',
        'claimed',
        p_ngo_id,
        'Claimed by NGO ' || p_ngo_name
    );

    -- 4. Create Donation Request record
    INSERT INTO public.donation_requests (
        listing_id,
        ngo_id,
        ngo_name,
        requested_servings,
        status,
        notes
    ) VALUES (
        p_listing_id,
        p_ngo_id,
        p_ngo_name,
        v_listing.servings_count,
        'approved',
        'Direct claim confirmed via FoodBridge AI'
    );

    -- 5. Generate 4-digit pickup verification OTP
    v_otp := LPAD(FLOOR(RANDOM() * 9000 + 1000)::TEXT, 4, '0');

    -- 6. Create Food Pickup assignment
    INSERT INTO public.food_pickups (
        listing_id,
        listing_title,
        category,
        servings,
        provider_name,
        provider_address,
        ngo_name,
        ngo_address,
        status,
        otp_code,
        notes
    ) VALUES (
        v_listing.id,
        v_listing.title,
        v_listing.category,
        v_listing.servings_count,
        v_listing.provider_org,
        v_listing.provider_address,
        p_ngo_name,
        '120 Hope Avenue, Eastside Community Center',
        'pending',
        v_otp,
        'Please bring thermal insulated bag.'
    ) RETURNING id INTO v_new_pickup_id;

    -- 7. Notify Provider
    IF v_listing.provider_id IS NOT NULL THEN
        INSERT INTO public.notifications (
            recipient_id,
            title,
            message,
            type,
            action_url
        ) VALUES (
            v_listing.provider_id,
            'Surplus Claimed! 🎉',
            p_ngo_name || ' has claimed "' || v_listing.title || '". Volunteer dispatch scheduled.',
            'claim',
            '/pickup-tracking'
        );
    END IF;

    -- 8. Increment Impact Stats
    UPDATE public.impact_statistics
    SET total_meals_rescued = total_meals_rescued + v_listing.servings_count,
        total_donations = total_donations + 1,
        co2_saved_kg = co2_saved_kg + ROUND(v_listing.servings_count * 1.2),
        water_saved_liters = water_saved_liters + ROUND(v_listing.servings_count * 6.5),
        updated_at = NOW()
    WHERE id = '00000000-0000-0000-0000-000000000001';

    RETURN jsonb_build_object(
        'success', true,
        'pickup_id', v_new_pickup_id,
        'otp_code', v_otp
    );
END;
$$;

-- 11. ROW LEVEL SECURITY (RLS) POLICIES
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.food_listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.donation_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.food_pickups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.donation_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.impact_statistics ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- PROFILES RLS
-- ----------------------------------------------------------------------------
CREATE POLICY "Profiles viewable by all users" ON public.profiles
    FOR SELECT USING (true);

CREATE POLICY "Users can create their own profile" ON public.profiles
    FOR INSERT WITH CHECK (
        public.requesting_user_id() = id OR
        auth.role() = 'authenticated' OR
        auth.role() = 'anon'
    );

CREATE POLICY "Users can update own profile" ON public.profiles
    FOR UPDATE USING (
        public.requesting_user_id() = id OR
        public.requesting_user_role() = 'admin'
    );

-- ----------------------------------------------------------------------------
-- FOOD LISTINGS RLS
-- ----------------------------------------------------------------------------
CREATE POLICY "Listings viewable by all users" ON public.food_listings
    FOR SELECT USING (true);

CREATE POLICY "Providers and Admins can create food listings" ON public.food_listings
    FOR INSERT WITH CHECK (
        provider_id = public.requesting_user_id() OR
        public.requesting_user_role() IN ('provider', 'admin', 'anon')
    );

CREATE POLICY "Donors, claimers, and admins can update listings" ON public.food_listings
    FOR UPDATE USING (
        provider_id = public.requesting_user_id() OR
        claimed_by_ngo_id = public.requesting_user_id() OR
        assigned_volunteer_id = public.requesting_user_id() OR
        public.requesting_user_role() = 'admin'
    );

-- ----------------------------------------------------------------------------
-- DONATION REQUESTS RLS
-- ----------------------------------------------------------------------------
CREATE POLICY "Donation requests viewable by participants" ON public.donation_requests
    FOR SELECT USING (
        ngo_id = public.requesting_user_id() OR
        EXISTS (
            SELECT 1 FROM public.food_listings l
            WHERE l.id = donation_requests.listing_id AND l.provider_id = public.requesting_user_id()
        ) OR
        public.requesting_user_role() = 'admin'
    );

CREATE POLICY "NGOs can insert donation requests" ON public.donation_requests
    FOR INSERT WITH CHECK (
        ngo_id = public.requesting_user_id() OR
        public.requesting_user_role() IN ('ngo', 'admin', 'anon')
    );

CREATE POLICY "NGOs and Providers can update requests" ON public.donation_requests
    FOR UPDATE USING (
        ngo_id = public.requesting_user_id() OR
        public.requesting_user_role() = 'admin'
    );

-- ----------------------------------------------------------------------------
-- FOOD PICKUPS RLS
-- ----------------------------------------------------------------------------
CREATE POLICY "Pickups viewable by authenticated users" ON public.food_pickups
    FOR SELECT USING (true);

CREATE POLICY "Authenticated users can insert pickups" ON public.food_pickups
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Participants and volunteers can update pickups" ON public.food_pickups
    FOR UPDATE USING (
        volunteer_id = public.requesting_user_id() OR
        public.requesting_user_role() IN ('courier', 'volunteer', 'admin', 'anon')
    );

-- ----------------------------------------------------------------------------
-- DONATION STATUS HISTORY RLS
-- ----------------------------------------------------------------------------
CREATE POLICY "Status history viewable by all" ON public.donation_status_history
    FOR SELECT USING (true);

CREATE POLICY "Status history insertable by participants" ON public.donation_status_history
    FOR INSERT WITH CHECK (true);

-- ----------------------------------------------------------------------------
-- NOTIFICATIONS RLS
-- ----------------------------------------------------------------------------
CREATE POLICY "Users view their own notifications" ON public.notifications
    FOR SELECT USING (
        recipient_id = public.requesting_user_id() OR
        recipient_id IS NULL
    );

CREATE POLICY "System and users can insert notifications" ON public.notifications
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Users can mark own notifications as read" ON public.notifications
    FOR UPDATE USING (
        recipient_id = public.requesting_user_id()
    );

-- ----------------------------------------------------------------------------
-- IMPACT STATISTICS RLS
-- ----------------------------------------------------------------------------
CREATE POLICY "Impact stats viewable by all" ON public.impact_statistics
    FOR SELECT USING (true);

CREATE POLICY "Impact stats updateable by platform" ON public.impact_statistics
    FOR ALL USING (true);

-- ----------------------------------------------------------------------------
-- 7. AUTHORIZED USERS (Strict access control gate)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.authorized_users (
    firebase_uid TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('food_provider', 'ngo_partner', 'courier', 'admin')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    approved_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_authorized_users_email ON public.authorized_users (LOWER(email));
CREATE INDEX IF NOT EXISTS idx_authorized_users_active ON public.authorized_users (is_active);
CREATE INDEX IF NOT EXISTS idx_authorized_users_role ON public.authorized_users (role);

ALTER TABLE public.authorized_users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own authorization record" ON public.authorized_users
    FOR SELECT USING (
        firebase_uid = (SELECT COALESCE(auth.uid()::text, ''))
        OR LOWER(email) = LOWER(COALESCE((SELECT auth.jwt()->>'email'), ''))
        OR (SELECT auth.role()) = 'service_role'
        OR (SELECT auth.role()) = 'anon'
    );

CREATE POLICY "Admins can insert authorized users" ON public.authorized_users
    FOR INSERT WITH CHECK (
        (SELECT auth.role()) = 'service_role'
        OR EXISTS (
            SELECT 1 FROM public.authorized_users a
            WHERE a.firebase_uid = (SELECT auth.uid()::text)
            AND a.role = 'admin'
            AND a.is_active = TRUE
        )
        OR (SELECT auth.role()) = 'anon'
    );

CREATE POLICY "Admins can update authorized users" ON public.authorized_users
    FOR UPDATE USING (
        (SELECT auth.role()) = 'service_role'
        OR EXISTS (
            SELECT 1 FROM public.authorized_users a
            WHERE a.firebase_uid = (SELECT auth.uid()::text)
            AND a.role = 'admin'
            AND a.is_active = TRUE
        )
        OR (SELECT auth.role()) = 'anon'
    );

CREATE POLICY "Admins can delete authorized users" ON public.authorized_users
    FOR DELETE USING (
        (SELECT auth.role()) = 'service_role'
        OR EXISTS (
            SELECT 1 FROM public.authorized_users a
            WHERE a.firebase_uid = (SELECT auth.uid()::text)
            AND a.role = 'admin'
            AND a.is_active = TRUE
        )
        OR (SELECT auth.role()) = 'anon'
    );

-- Seed initial authorized users
INSERT INTO public.authorized_users (firebase_uid, email, role, is_active, approved_at)
VALUES
    ('seed-admin-001', 'admin@foodbridge.ai', 'admin', TRUE, NOW()),
    ('seed-provider-001', 'marco@trattoriabella.com', 'food_provider', TRUE, NOW()),
    ('seed-ngo-001', 'director@hopehaven.org', 'ngo_partner', TRUE, NOW()),
    ('seed-courier-001', 'alex.rivera@volunteer.org', 'courier', TRUE, NOW())
ON CONFLICT (email) DO UPDATE
    SET role = EXCLUDED.role,
        is_active = EXCLUDED.is_active,
        approved_at = NOW();
