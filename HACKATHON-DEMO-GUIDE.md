# FoodBridge AI — Hackathon Demonstration Guide

Welcome to **FoodBridge AI**, the autonomous food surplus rescue and distribution network. This guide outlines how to demonstrate the full end-to-end platform to hackathon judges.

---

## 🌟 Demo Scenario (4-Minute Judge Walkthrough)

### Step 1: Landing Page & Problem Context (1 min)
1. Navigate to the **Home** view (`landing`).
2. Show the **Real-Time Network Telemetry Counters** (14,820+ Meals Rescued, 17.8 tons of CO₂ avoided).
3. Scroll to the **Interactive What-If Simulator**:
   - Drag the portions slider from 50 to 500 meals/week.
   - Show judges how annual CO₂ reduction and water savings dynamically compute in real-time.
4. Show the **Live Food Rescue Radar** demonstrating active geo-spatial matching between donors and shelters.

### Step 2: Food Provider Lists Surplus (1 min)
1. Click **"Food Provider"** in the top **Demo Switcher Bar** (or sign in as Chef Marco Rossi).
2. Click **"+ Post Food Surplus"** to open `CreateSurplusPage`.
3. Fill in:
   - **Title**: `40 Portions Vegetable Lasagna & Organic Salad`
   - **Category**: `Cooked Meals`
   - **Quantity**: `40 portions (18 kg)`
   - **Temperature**: `Hot`
4. Click **"Run Safety Check"** to show AI Food Safety Verification.
5. Click **"Publish Food Surplus Listing"**.
6. The listing immediately appears on the provider dashboard and updates network counters.

### Step 3: Shelter Discovers & Claims Donation (1 min)
1. Click **"NGO Partner"** in the top **Demo Switcher Bar** (Sister Mary Teresa, Hope Haven Shelter).
2. Note the **Daily Intake Capacity Meter** (60% capacity utilized, room for 140 portions).
3. Scroll down to **Available Surplus Food Nearby**.
4. Click **"Claim for Shelter"** on the newly created Lasagna listing.
5. Notice that an atomic pickup order (e.g. `#PK-8903`) is instantly created, and nearby volunteer riders are pinged.

### Step 4: Volunteer Accepts Delivery & Completes Handover (1 min)
1. Click **"Volunteer Rider"** in the top **Demo Switcher Bar** (Alex Rivera).
2. In the **Active Deliveries** section, click **"Accept Delivery"**.
3. Click **"Confirm Food Picked Up"** at the donor location.
4. Click **"Confirm Handover to Shelter (Complete Mission)"**.
5. The **Delivery Success Celebration Modal** pops up with verified portions fed and CO₂ avoided!
6. Click **"Impact Hub"** in the navigation bar to see the live metrics update.

### Step 5: AI Surplus Forecasting Demo (30 sec)
1. Click **"AI Predictor"** in the top navigation.
2. Select **Corporate Catering**, **Friday**, and **Rainy / Low Footfall**.
3. Click **"Run Demand Forecast"**.
4. Highlight the transparent model explanation, influence factors, and recommended pre-rescue action plan.

---

## 🗄️ Supabase Database Architecture

The application is backed by the complete SQL schema in `supabase-schema.sql`:

1. **`profiles`**: Stores user identity, verified badge, and roles (`provider`, `ngo`, `volunteer`, `admin`).
2. **`food_listings`**: Stores food surplus postings with category, safe expiry window, portions, and status (`available`, `claimed`, `in_transit`, `delivered`).
3. **`food_pickups`**: Stores pickup tracking telemetry, origin, destination, assigned rider, status, and OTP verification code.
4. **`notifications`**: Persistent real-time alerts.
5. **`claim_food_listing(p_listing_id, p_ngo_id, p_ngo_name)`**: Stored procedure enforcing row locks to guarantee no two NGOs can claim the same listing simultaneously.

### Running the Supabase Migration
1. In your Supabase project dashboard, open the **SQL Editor**.
2. Paste the contents of `supabase-schema.sql` and click **Run**.
3. Set your project URL and Anon key in `.env`:
   ```env
   VITE_SUPABASE_URL="https://your-project.supabase.co"
   VITE_SUPABASE_ANON_KEY="your-anon-key"
   ```
4. FoodBridge AI will automatically sync live records with your Supabase backend.
