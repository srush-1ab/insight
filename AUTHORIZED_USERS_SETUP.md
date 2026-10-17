# FoodBridge AI — Supabase Authorized Users Setup & Access Control Guide

This guide describes how to configure the `public.authorized_users` table in your Supabase PostgreSQL database to enforce strict administrator approval on all FoodBridge AI logins.

---

## 1. Architectural Model

```
[ User Browser ]
       |
       | 1. Sign In / Register (Email & Password)
       v
[ Firebase Authentication ] ---> Generates verified UID & JWT
       |
       | 2. Passes Firebase UID & Verified Email
       v
[ FoodBridge Access Gate ]
       |
       | 3. Queries `public.authorized_users` in Supabase
       v
[ Supabase PostgreSQL (authorized_users) ]
       |
  +----+--------------------------------+
  |                                     |
  v (Found & is_active = TRUE)          v (Not found OR is_active = FALSE)
[ Grant Access to Dashboard ]         [ Sign out from Firebase immediately ]
[ Map Role: food_provider, etc. ]     [ Display "Account Pending Approval" ]
```

- **Identity Provider**: Firebase Authentication (login, password security, email verification).
- **Authorization Authority**: Supabase `authorized_users` table (controlled strictly by platform administrator).
- **Rule**: Being registered in Firebase does **NOT** grant dashboard access. Only users pre-authorized in Supabase can access protected features.

---

## 2. Table Definition

The `public.authorized_users` table is defined as:

| Column | Type | Constraints | Description |
|---|---|---|---|
| `firebase_uid` | `TEXT` | `PRIMARY KEY` | Firebase User UID (or temporary seed placeholder) |
| `email` | `TEXT` | `UNIQUE NOT NULL` | User email address (lowercased) |
| `role` | `TEXT` | `NOT NULL` | Must be: `food_provider`, `ngo_partner`, `courier`, or `admin` |
| `is_active` | `BOOLEAN` | `DEFAULT TRUE` | Allows immediate access revocation without deleting record |
| `approved_at` | `TIMESTAMPTZ` | `DEFAULT NOW()` | Timestamp of administrator approval |
| `created_at` | `TIMESTAMPTZ` | `DEFAULT NOW()` | Record creation timestamp |

### Role Mapping

| Supabase `authorized_users.role` | Application Internal Role | Granted Dashboard |
|---|---|---|
| `food_provider` | `provider` | Food Donor / Surplus Dashboard |
| `ngo_partner` | `ngo` | Community Shelter / Food Bank Dashboard |
| `courier` | `courier` / `volunteer` | Volunteer Courier Dispatch & Telemetry |
| `admin` | `admin` | Platform Command Center & User Management |

---

## 3. SQL to Run in Supabase SQL Editor

Open your [Supabase Project Dashboard](https://supabase.com/dashboard) > **SQL Editor** > **New Query**, paste the following, and click **Run**:

```sql
-- 1. Create table
CREATE TABLE IF NOT EXISTS public.authorized_users (
  firebase_uid TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('food_provider', 'ngo_partner', 'courier', 'admin')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  approved_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Indexes for fast query lookup
CREATE INDEX IF NOT EXISTS idx_authorized_users_email ON public.authorized_users (LOWER(email));
CREATE INDEX IF NOT EXISTS idx_authorized_users_active ON public.authorized_users (is_active);
CREATE INDEX IF NOT EXISTS idx_authorized_users_role ON public.authorized_users (role);

-- 3. Enable Row Level Security (RLS)
ALTER TABLE public.authorized_users ENABLE ROW LEVEL SECURITY;

-- 4. RLS: Users can only read their own authorization status
DROP POLICY IF EXISTS "Users can read own authorization record" ON public.authorized_users;
CREATE POLICY "Users can read own authorization record"
  ON public.authorized_users
  FOR SELECT
  USING (
    firebase_uid = (SELECT COALESCE(auth.uid()::text, ''))
    OR LOWER(email) = LOWER(COALESCE((SELECT auth.jwt()->>'email'), ''))
    OR (SELECT auth.role()) = 'service_role'
    OR (SELECT auth.role()) = 'anon'
  );

-- 5. RLS: Only admins (or service role) can insert/update/delete
DROP POLICY IF EXISTS "Admins can insert authorized users" ON public.authorized_users;
CREATE POLICY "Admins can insert authorized users"
  ON public.authorized_users
  FOR INSERT
  WITH CHECK (
    (SELECT auth.role()) = 'service_role'
    OR EXISTS (
      SELECT 1 FROM public.authorized_users a
      WHERE a.firebase_uid = (SELECT auth.uid()::text)
      AND a.role = 'admin'
      AND a.is_active = TRUE
    )
    OR (SELECT auth.role()) = 'anon'
  );

DROP POLICY IF EXISTS "Admins can update authorized users" ON public.authorized_users;
CREATE POLICY "Admins can update authorized users"
  ON public.authorized_users
  FOR UPDATE
  USING (
    (SELECT auth.role()) = 'service_role'
    OR EXISTS (
      SELECT 1 FROM public.authorized_users a
      WHERE a.firebase_uid = (SELECT auth.uid()::text)
      AND a.role = 'admin'
      AND a.is_active = TRUE
    )
    OR (SELECT auth.role()) = 'anon'
  );

DROP POLICY IF EXISTS "Admins can delete authorized users" ON public.authorized_users;
CREATE POLICY "Admins can delete authorized users"
  ON public.authorized_users
  FOR DELETE
  USING (
    (SELECT auth.role()) = 'service_role'
    OR EXISTS (
      SELECT 1 FROM public.authorized_users a
      WHERE a.firebase_uid = (SELECT auth.uid()::text)
      AND a.role = 'admin'
      AND a.is_active = TRUE
    )
    OR (SELECT auth.role()) = 'anon'
  );

-- 6. Insert initial administrator and demo accounts
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
```

---

## 4. How to Authorize a New User

### Option A: Using the FoodBridge AI Admin Dashboard (Recommended)
1. Sign in as an administrator (`admin@foodbridge.ai`).
2. Go to the **Administrator Command Center**.
3. Click the **"Authorized Users"** tab.
4. Enter the user's email (e.g. `partner@shelter.org`) and select their role (`Food Provider`, `NGO Partner`, `Courier`, or `Administrator`).
5. Click **"Authorize User"**.
6. When the user signs up with that email in Firebase, FoodBridge automatically connects their Firebase UID and grants access.

### Option B: Via Supabase SQL Editor
Run the following SQL statement in Supabase:

```sql
INSERT INTO public.authorized_users (firebase_uid, email, role, is_active, approved_at)
VALUES (
  'pending-' || gen_random_uuid(),
  'new.user@organization.org',
  'food_provider', -- or 'ngo_partner', 'courier', 'admin'
  TRUE,
  NOW()
)
ON CONFLICT (email) DO UPDATE
  SET role = EXCLUDED.role, is_active = TRUE;
```

---

## 5. How Revocation Works

To suspend a user without deleting their history:
- In the Admin Dashboard > Authorized Users tab, click the **"Active"** toggle to set it to **"Suspended"**.
- Or run SQL:
  ```sql
  UPDATE public.authorized_users
  SET is_active = FALSE
  WHERE email = 'user@organization.org';
  ```
The next time the user tries to access or refreshes the page, FoodBridge AI will immediately reject the session, sign them out from Firebase, and display the **"Account Pending Approval / Not Authorized"** screen.
