# ScholarTrack — Student Scholarship Monitoring System

A VS Code-ready HTML/CSS/JavaScript frontend with Supabase Auth + PostgreSQL backend. Covers the five core modules in the supplied Systems Analysis and Design laboratory.

## Setup (do these in order)

1. Unzip and open the `scholarship-monitoring` folder in **VS Code**.
2. Create a **new Supabase project** at https://supabase.com/dashboard . In **SQL Editor**, paste and run the entire `supabase/schema.sql` file. It creates the tables, sample scholarship programs, authentication trigger, RLS policies and atomic verification function. **Run on a new project** to avoid conflicts with existing tables.
3. Go to **Project Settings → API** (or Connect) and copy the **Project URL** and **publishable/anon key** into `js/config.js`. Never use the `service_role` or secret key in browser code.
4. Under **Authentication → Providers → Email**, enable Email. For local testing, either confirm the signup email or disable email confirmation temporarily (only for a demo).
5. In VS Code, install **Live Server**. Right-click `index.html` → **Open with Live Server**. You may also deploy the files on GitHub Pages. Do not use `file://` to open the HTML.
6. Click **Create account** to register your first user. All signups default to **scholar**. To make your first admin, copy the registered user's UUID from **Authentication → Users** and run this in Supabase SQL Editor:

```sql
update public.profiles set role='admin' where id='PASTE-AUTH-USER-UUID-HERE';
```

7. Log out and sign back in. You can now manage scholarship programs and register scholars. To create a staff user, have them sign up and use the same SQL with `role='staff'` and their UUID. Staff can manage scholars, submit grades and verify; only admin can change programs.
8. To give a scholar access to their own record, have them sign up first; then as staff/admin open **Scholars → Add/Edit Scholar → Linked scholar login** and select their account. Scholar accounts can submit grades and see only their own record and submissions. They cannot verify or change programs.

## Core workflow

1. Admin configures scholarship requirements (sample programs are inserted by SQL).
2. Staff registers scholar, selects program and optionally links a scholar login.
3. Staff or linked scholar submits semester grades. Record is `Pending`.
4. Staff clicks **Verify**. The database function locks the submission, checks the *assigned program's* GWA/unit/failing-grade rules and checks incomplete subjects, marks the submission `Verified`, writes the compliance result and scholar status, and inserts an audit log. Double verification is blocked.
5. Dashboard and Compliance screens show live database data after refreshing.

**Grading assumption:** Philippine GWA scale **1.00 (best) to 5.00 (worst)**; `gwa <= required_gwa` passes. Adjust the SQL constraints, verification function and form if your institution uses a different grading scale. Incomplete subjects are treated as a deficiency. One submission per scholar / academic year / semester. A verified submission cannot be edited from the browser; an authorized correction workflow is future scope.

**Scope:** This is the required 2.5-hour vertical-slice prototype, not the full future system. Renewal, document uploads, automated notifications and advanced reports are not implemented. The dashboard's current scholar status reflects the most recently **verified action**, not a chronological re-evaluation if old semesters are verified out of order; verify submissions in academic order during demonstrations. Database RLS protects private grades and prevents client-side role escalation.

## Quick functional test checklist

- [ ] TC-01 Sign in as admin/staff → dashboard opens.
- [ ] TC-02 Register scholar with unique student ID → record appears.
- [ ] TC-03 Leave Student ID empty → browser and DB reject.
- [ ] TC-04 Submit valid semester grades → Pending.
- [ ] TC-05 Staff verifies → Verified; cannot verify again.
- [ ] TC-06 GWA/units/failures/incompletes satisfy program → Compliant.
- [ ] TC-07 Violate a requirement in a **different term** → With Deficiency.
- [ ] TC-08 Search student ID/name → matching records.
- [ ] TC-09 Filter scholars by program/status → matching subset.
- [ ] TC-10 Publish on GitHub Pages → confirm deployed URL loads and authenticates.
- [ ] Scholar cannot read another scholar's grades or verify.

## Deployment

Push the contents of this folder to GitHub. In repository **Settings → Pages**, deploy from `main` / root. The site is static; Supabase remains the backend. Configure `js/config.js` before deploying; the publishable/anon key is designed for browser use, but RLS must remain enabled. Commit code incrementally to meet your course's four-commit requirement.

## File map

- `index.html`: login and app shell
- `css/style.css`: responsive dashboard styles
- `js/config.js`: your Supabase project URL and public key
- `js/app.js`: frontend UI, validation and Supabase API calls
- `supabase/schema.sql`: PostgreSQL tables, RLS, signup trigger and verification RPC
- `docs/`: short use case, ERD and traceability notes
