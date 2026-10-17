# FoodBridge AI — Supabase & Firebase Integration Guide

This application integrates **Firebase Authentication** as the Identity Provider with **Supabase PostgreSQL** as the persistent relational database, using Supabase's official **Third-Party Auth** mechanism.

---

## 1. Architecture Overview

```
+-------------------------------------------------------------+
|                     FoodBridge AI Frontend                  |
|  - Registration, Login, Email Verification: Firebase Auth   |
|  - Role Management: Provider, NGO, Courier, Admin           |
|  - Realtime & CRUD: Supabase JavaScript Client SDK          |
+------------------------------+------------------------------+
                               |
                accessToken: getIdToken()
                               |
                               v
+-------------------------------------------------------------+
|                     Supabase PostgreSQL                     |
|  - URL: https://oxidjbrzbiyxtikzyzcy.supabase.co            |
|  - Key: sb_publishable_WebTAmP6ZRg6HFfUOYa2aQ_apqA0bfp       |
|  - Validates Firebase JWT tokens via Third-Party Auth       |
|  - RLS Policies enforce role access using auth.jwt()        |
+-------------------------------------------------------------+
```

---

## 2. Supabase Third-Party Auth Setup (Firebase Auth)

To allow Supabase to accept and verify Firebase JWT tokens:

1. Open your [Supabase Dashboard](https://supabase.com/dashboard/project/oxidjbrzbiyxtikzyzcy).
2. Navigate to **Authentication** in the sidebar.
3. Select **Third-Party Auth** (or **External Providers** depending on dashboard version).
4. Click **Add Provider** and choose **Firebase Auth**.
5. Input your **Firebase Project ID** (from your Firebase Console project settings).
6. Save changes.

### How Token Verification Works
- When a user logs in via Firebase Auth, the Supabase client sends their Firebase ID token via the `Authorization: Bearer <token>` header on every request.
- Supabase automatically checks the token's signature against Firebase's public JWKS (`https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com`).
- The user's Firebase UID is accessible in PostgreSQL via `auth.jwt() ->> 'sub'`.

---

## 3. Database Schema & RLS Policies Deployment

A complete versioned migration has been prepared:
- `supabase/migrations/20261017000000_foodbridge_schema.sql`
- `supabase-schema.sql` (root mirror)

### To Apply the Schema in Supabase:
1. Open the **SQL Editor** in your Supabase Dashboard:
   `https://supabase.com/dashboard/project/oxidjbrzbiyxtikzyzcy/sql/new`
2. Copy the entire contents of `supabase/migrations/20261017000000_foodbridge_schema.sql`.
3. Paste into the SQL editor and click **Run**.
4. The following entities and policies will be provisioned:
   - `public.profiles`: Stores organization and user metadata keyed by Firebase UID.
   - `public.food_listings`: Surplus food donations.
   - `public.donation_requests`: NGO claims and requests.
   - `public.food_pickups`: Pickup scheduling and volunteer delivery dispatch.
   - `public.donation_status_history`: Immutable audit trail of listing status changes.
   - `public.notifications`: Role-targeted alert and confirmation notifications.
   - `public.impact_statistics`: Rescued meal counts, CO2 savings, and water savings.
   - `claim_food_listing`: Atomic concurrency-safe stored procedure preventing double-claims.

---

## 4. Row Level Security (RLS) Specification

| Entity | Public / Anon | Food Provider | NGO Receiver | Courier / Volunteer | Admin |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **profiles** | Read | Read & Update Own | Read & Update Own | Read & Update Own | Full Control |
| **food_listings** | Read Available | Create & Update Own | Read All, Claim | Read All | Full Control |
| **donation_requests** | None | Read on Own Listings | Create & Read Own | Read Assigned | Full Control |
| **food_pickups** | None | Read Own Pickups | Read Claimed Pickups | Read & Update Route/Status | Full Control |
| **status_history** | Read | Read Own Listings | Read Claimed Listings | Read Assigned | Full Control |
| **notifications** | None | Read Own (UID) | Read Own (UID) | Read Own (UID) | Full Control |
| **impact_statistics** | Read Public Stats | Read | Read | Read | Update Platform |

---

## 5. Development Mode & Offline Resilience

- If Supabase environment variables are missing or remote tables haven't been applied yet, FoodBridge AI automatically operates in resilient local fallback mode.
- Users can switch personas, list surplus food, accept claims, and track pickups seamlessly without database exceptions breaking the UI.
