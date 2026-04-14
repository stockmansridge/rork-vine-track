-- ============================================
-- Admin Dashboard Migration
-- Run this in your Supabase SQL Editor
-- ============================================

-- 1. Add is_admin column to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_admin boolean DEFAULT false;

-- 2. Set initial admin user
UPDATE profiles SET is_admin = true WHERE email = 'stockmansridge@gmail.com';

-- 3. Create admin dashboard function (security definer to access auth.users)
CREATE OR REPLACE FUNCTION get_admin_dashboard_users()
RETURNS TABLE (
    user_id uuid,
    email text,
    full_name text,
    provider text,
    created_at timestamptz,
    last_sign_in_at timestamptz,
    is_admin boolean,
    vineyard_count bigint,
    vineyard_names text,
    total_members bigint
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        au.id AS user_id,
        au.email::text,
        COALESCE(au.raw_user_meta_data->>'full_name', p.name, au.email::text) AS full_name,
        COALESCE(au.raw_app_meta_data->>'provider', 'email') AS provider,
        au.created_at,
        au.last_sign_in_at,
        COALESCE(p.is_admin, false) AS is_admin,
        COALESCE(vc.vineyard_count, 0) AS vineyard_count,
        COALESCE(vn.vineyard_names, '') AS vineyard_names,
        COALESCE(mc.total_members, 0) AS total_members
    FROM auth.users au
    LEFT JOIN profiles p ON p.id = au.id::text
    LEFT JOIN LATERAL (
        SELECT COUNT(DISTINCT vm.vineyard_id) AS vineyard_count
        FROM vineyard_members vm
        WHERE vm.user_id = au.id::text
    ) vc ON true
    LEFT JOIN LATERAL (
        SELECT STRING_AGG(v.name, ', ' ORDER BY v.name) AS vineyard_names
        FROM vineyard_members vm
        JOIN vineyards v ON v.id = vm.vineyard_id
        WHERE vm.user_id = au.id::text
    ) vn ON true
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS total_members
        FROM vineyard_members vm2
        WHERE vm2.vineyard_id IN (
            SELECT vm3.vineyard_id FROM vineyard_members vm3 WHERE vm3.user_id = au.id::text
        )
    ) mc ON true
    ORDER BY au.created_at DESC;
$$;

-- 4. Create function to check if current user is admin
CREATE OR REPLACE FUNCTION is_current_user_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (SELECT is_admin FROM profiles WHERE id = auth.uid()::text),
        false
    );
$$;

-- 5. Create RLS policy so only admins can call the dashboard function
-- (The function itself uses SECURITY DEFINER, but we add an internal check)
CREATE OR REPLACE FUNCTION get_admin_dashboard_users_safe()
RETURNS TABLE (
    user_id uuid,
    email text,
    full_name text,
    provider text,
    created_at timestamptz,
    last_sign_in_at timestamptz,
    is_admin boolean,
    vineyard_count bigint,
    vineyard_names text,
    total_members bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT (SELECT COALESCE((SELECT p.is_admin FROM profiles p WHERE p.id = auth.uid()::text), false)) THEN
        RAISE EXCEPTION 'Access denied: admin privileges required';
    END IF;

    RETURN QUERY SELECT * FROM get_admin_dashboard_users();
END;
$$;

-- 6. Grant execute permission
GRANT EXECUTE ON FUNCTION get_admin_dashboard_users_safe() TO authenticated;
GRANT EXECUTE ON FUNCTION is_current_user_admin() TO authenticated;
