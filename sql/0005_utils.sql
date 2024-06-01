create or replace function check_exec(p_role_name text, p_schema_name text, p_function_name text)
returns table(role_name text, schema_name text, function_name text, permission_type text) as $$
begin
    return query
    with direct_permissions as (
        select
            r.rolname::text as role_name,
            n.nspname::text as schema_name,
            p.proname::text as function_name,
            'direct' as permission_type
        from
            pg_roles r
        join
            pg_namespace n on n.nspname = p_schema_name
        join
            pg_proc p on p.pronamespace = n.oid and p.proname = p_function_name
        where
            r.rolname = p_role_name
            and has_function_privilege(r.rolname, p.oid, 'execute')
    ), inherited_permissions as (
        select
            r.rolname::text as role_name,
            n.nspname::text as schema_name,
            p.proname::text as function_name,
            'inherited' as permission_type
        from
            pg_roles r
        join
            pg_auth_members m on r.oid = m.member
        join
            pg_roles r_parent on m.roleid = r_parent.oid
        join
            pg_namespace n on n.nspname = p_schema_name
        join
            pg_proc p on p.pronamespace = n.oid and p.proname = p_function_name
        where
            r.rolname = p_role_name
            and has_function_privilege(r_parent.rolname, p.oid, 'execute')
    )
    select * from direct_permissions
    union all
    select * from inherited_permissions;
end;
$$ language plpgsql;

