-- Run once in Supabase SQL Editor on a NEW project. GWA: lower is better (1.00 best, 5.00 lowest).
create extension if not exists pgcrypto;
create table public.profiles (id uuid primary key references auth.users(id) on delete cascade, full_name text not null default '', role text not null default 'scholar' check(role in ('admin','staff','scholar')), created_at timestamptz default now());
create table public.scholarship_programs (id uuid primary key default gen_random_uuid(), program_name text not null unique, required_gwa numeric(3,2) not null check(required_gwa between 1 and 5), min_units int not null check(min_units >= 0), allow_failing_grade boolean not null default false, active boolean not null default true, created_at timestamptz default now());
create table public.scholars (id uuid primary key default gen_random_uuid(), student_id text not null unique check(length(trim(student_id))>0), full_name text not null check(length(trim(full_name))>0), degree_program text not null, year_level int not null check(year_level between 1 and 8), scholarship_id uuid not null references public.scholarship_programs(id), user_id uuid unique references auth.users(id) on delete set null, status text not null default 'Active' check(status in ('Active','Pending Submission','For Verification','Compliant','With Deficiency','Probationary','For Renewal','Renewed','Disqualified')), created_at timestamptz default now());
create table public.grade_submissions (id uuid primary key default gen_random_uuid(), scholar_id uuid not null references public.scholars(id) on delete cascade, academic_year text not null check(academic_year ~ '^[0-9]{4}-[0-9]{4}$'), semester text not null check(semester in ('1st Semester','2nd Semester','Summer')), gwa numeric(3,2) not null check(gwa between 1 and 5), units_enrolled int not null check(units_enrolled>=0), failed_subjects int not null check(failed_subjects>=0), incomplete_subjects int not null check(incomplete_subjects>=0), submission_status text not null default 'Pending' check(submission_status in ('Pending','Verified','Returned')), submitted_at timestamptz not null default now(), submitted_by uuid not null default auth.uid() references auth.users(id), verified_by uuid references auth.users(id), verified_at timestamptz, evaluation text check(evaluation in ('Compliant','With Deficiency')), deficiency_notes text, unique(scholar_id,academic_year,semester));
create table public.audit_logs (id bigint generated always as identity primary key, actor_id uuid references auth.users(id), action text not null, submission_id uuid references public.grade_submissions(id), details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
create index on public.scholars(scholarship_id);
create index on public.grade_submissions(scholar_id,submitted_at desc);
create or replace function public.current_role() returns text language sql stable security definer set search_path=public as $$ select role from public.profiles where id=auth.uid() $$;
create or replace function public.is_staff() returns boolean language sql stable security definer set search_path=public as $$ select coalesce(public.current_role() in ('admin','staff'),false) $$;
create or replace function public.on_signup() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into public.profiles(id,full_name,role) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),'scholar'); return new; end $$;
create trigger on_auth_signup after insert on auth.users for each row execute function public.on_signup();
-- No browser client can self-promote to staff/admin; assign roles only in SQL Editor.
alter table public.profiles enable row level security;
alter table public.scholarship_programs enable row level security;
alter table public.scholars enable row level security;
alter table public.grade_submissions enable row level security;
alter table public.audit_logs enable row level security;
create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_staff());
create policy programs_read on public.scholarship_programs for select to authenticated using(true);
create policy programs_insert on public.scholarship_programs for insert to authenticated with check(public.current_role()='admin');
create policy programs_update on public.scholarship_programs for update to authenticated using(public.current_role()='admin') with check(public.current_role()='admin');
create policy scholars_read on public.scholars for select to authenticated using(public.is_staff() or user_id=auth.uid());
create policy scholars_insert on public.scholars for insert to authenticated with check(public.is_staff() and (select active from public.scholarship_programs where id=scholarship_id));
create policy scholars_update on public.scholars for update to authenticated using(public.is_staff()) with check(public.is_staff() and (select active from public.scholarship_programs where id=scholarship_id));
create policy submissions_read on public.grade_submissions for select to authenticated using(public.is_staff() or exists(select 1 from public.scholars s where s.id=scholar_id and s.user_id=auth.uid()));
create policy submissions_insert on public.grade_submissions for insert to authenticated with check(submitted_by=auth.uid() and submission_status='Pending' and evaluation is null and verified_by is null and verified_at is null and (public.is_staff() or exists(select 1 from public.scholars s where s.id=scholar_id and s.user_id=auth.uid())));
create policy audit_read on public.audit_logs for select to authenticated using(public.current_role()='admin');
-- Verification + evaluation are one atomic, server-side transaction. A second verification is rejected.
create or replace function public.verify_submission(p_submission_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare v public.grade_submissions%rowtype; s public.scholars%rowtype; p public.scholarship_programs%rowtype; problems text[] := array[]::text[]; result text;
begin
 if not public.is_staff() then raise exception 'Only authorized staff may verify submissions'; end if;
 select * into v from public.grade_submissions where id=p_submission_id for update;
 if not found then raise exception 'Submission not found'; end if;
 if v.submission_status <> 'Pending' then raise exception 'Only pending submissions can be verified'; end if;
 select * into s from public.scholars where id=v.scholar_id for update;
 select * into p from public.scholarship_programs where id=s.scholarship_id;
 if v.gwa > p.required_gwa then problems:=array_append(problems,'GWA exceeds required '||p.required_gwa); end if;
 if v.units_enrolled < p.min_units then problems:=array_append(problems,'Insufficient enrolled units (minimum '||p.min_units||')'); end if;
 if not p.allow_failing_grade and v.failed_subjects>0 then problems:=array_append(problems,'Failing subjects are not allowed'); end if;
 if v.incomplete_subjects>0 then problems:=array_append(problems,'Incomplete subjects must be resolved'); end if;
 result:=case when cardinality(problems)=0 then 'Compliant' else 'With Deficiency' end;
 update public.grade_submissions set submission_status='Verified',verified_by=auth.uid(),verified_at=now(),evaluation=result,deficiency_notes=case when cardinality(problems)=0 then null else array_to_string(problems,'; ') end where id=p_submission_id;
 update public.scholars set status=result where id=s.id;
 insert into public.audit_logs(actor_id,action,submission_id,details) values(auth.uid(),'VERIFY_SUBMISSION',p_submission_id,jsonb_build_object('result',result,'deficiencies',problems));
end $$;
revoke all on function public.verify_submission(uuid) from public;
grant execute on function public.verify_submission(uuid) to authenticated;
-- Prevent changes to already-verified records through direct API updates (no UPDATE policy on submissions).
insert into public.scholarship_programs(program_name,required_gwa,min_units,allow_failing_grade) values
('University Merit Scholarship',1.75,18,false),('Government Academic Grant',2.50,15,false),('Private Education Grant',3.00,12,true);
